import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/storage/settings_store.dart';
import 'package:cms_player/data/models/favorite_item.dart';
import 'package:cms_player/data/models/play_record.dart';
import 'package:cms_player/data/models/vod_source.dart';
import 'package:cms_player/data/sync/backup_bundle.dart';

import 'helpers/fakes.dart';

/// 完整备份：序列化往返、版本拒绝、写盘命名与去重。
void main() {
  useIsolatedStores();

  PlayRecord record(String name) => PlayRecord(
        key: 's|1',
        sourceId: 's',
        sourceName: '测试站',
        vodId: '1',
        vodName: name,
        lineIndex: 0,
        episodeIndex: 1,
        lineName: 'm3u8',
        episodeName: '第02集',
        positionMs: 120000,
        durationMs: 600000,
        introMs: 5000,
        outroMs: 550000,
        updatedAt: DateTime(2026, 11, 11, 10),
      );

  FavoriteItem favorite(String name) => FavoriteItem(
        key: 's|2',
        sourceId: 's',
        sourceName: '测试站',
        vodId: '2',
        vodName: name,
        createdAt: DateTime(2026, 11, 10),
      );

  BackupBundle sample() => BackupBundle(
        exportedAt: DateTime(2026, 11, 11, 22, 37, 5),
        appVersion: '1.0.2',
        history: <PlayRecord>[record('庆余年')],
        favorites: <FavoriteItem>[favorite('三体')],
        sources: <VodSource>[
          VodSource.fromRaw(<String, Object>{
            'name': '测试站',
            'api': 'https://a.com/api.php/provide/vod/',
          }),
        ],
        searches: <String>['庆余年', '三体'],
        settings: <String, Object?>{'themeMode': 'dark', 'defaultRate': 1.5},
        tombstones: <String, Map<String, int>>{
          'favorites': <String, int>{'s|9': 1762800000000},
        },
      );

  group('序列化', () {
    test('往返后各集合与设置都在', () {
      final BackupBundle back = BackupBundle.decode(sample().encode())!;

      expect(back.appVersion, '1.0.2');
      expect(back.totalItems, 3);
      expect(back.history.single.vodName, '庆余年');
      expect(back.history.single.introMs, 5000);
      expect(back.favorites.single.vodName, '三体');
      expect(back.sources.single.name, '测试站');
      expect(back.searches, <String>['庆余年', '三体']);
      expect(back.settings['themeMode'], 'dark');
      expect(back.settings['defaultRate'], 1.5);
      expect(back.tombstones['favorites']?['s|9'], 1762800000000);
      expect(back.exportedAt.toUtc(), sample().exportedAt.toUtc());
    });

    test('输出的是带 kind 标记的可读 JSON', () {
      final Map<String, dynamic> json =
          jsonDecode(sample().encode()) as Map<String, dynamic>;
      expect(json['kind'], 'cms_player_backup');
      expect(json['v'], kBackupFormatVersion);
      expect(sample().encode(), contains('\n  '));
    });

    test('缺字段的文件也能读，不抛异常', () {
      final BackupBundle? back =
          BackupBundle.decode('{"v":1,"exportedAt":"x"}');
      expect(back, isNotNull);
      expect(back!.history, isEmpty);
      expect(back.searches, isEmpty);
      expect(back.settings, isEmpty);
      expect(back.appVersion, '');
    });

    test('版本高于本应用时拒绝解析', () {
      expect(
        () => BackupBundle.fromJson(
          <String, dynamic>{'v': kBackupFormatVersion + 1},
        ),
        throwsA(isA<FormatException>()),
      );
      // decode 把异常收成 null，调用方只需处理「这个文件不能用」。
      expect(
        BackupBundle.decode('{"v":${kBackupFormatVersion + 1}}'),
        isNull,
      );
    });

    test('不是 JSON 或不是对象时返回 null', () {
      expect(BackupBundle.decode(''), isNull);
      expect(BackupBundle.decode('   '), isNull);
      expect(BackupBundle.decode('not json'), isNull);
      expect(BackupBundle.decode('[1,2,3]'), isNull);
    });
  });

  group('设置快照', () {
    test('只含偏好，不含 WebDAV 凭据', () async {
      final SettingsStore settings = SettingsStore();
      await settings.init();
      await settings.setSyncWebDavUrl('https://dav.example.com/dav');
      await settings.setSyncWebDavUser('me');
      await settings.setSyncWebDavPass('s3cret');
      await settings.setThemeMode(ThemeMode.dark);
      await settings.setDefaultRate(1.25);

      final Map<String, Object?> snapshot = settings.exportSnapshot();

      expect(snapshot['themeMode'], 'dark');
      expect(snapshot['defaultRate'], 1.25);
      expect(snapshot.containsKey('syncWebDavUrl'), isFalse);
      expect(snapshot.containsKey('syncWebDavUser'), isFalse);
      expect(snapshot.containsKey('syncWebDavPass'), isFalse);
      expect(snapshot.values.join('|'), isNot(contains('s3cret')));
    });
  });

  group('写盘', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cms_player_backup_');
      BackupExporter.directoryOverride = () => dir;
    });

    tearDown(() async {
      BackupExporter.directoryOverride = null;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('文件名带时间戳', () {
      expect(
        BackupExporter.fileNameAt(DateTime(2026, 11, 11, 22, 37, 5)),
        'cmsplayer-backup-20261111-223705.json',
      );
      expect(
        BackupExporter.fileNameAt(DateTime(2026, 1, 2, 3, 4, 5)),
        'cmsplayer-backup-20260102-030405.json',
      );
    });

    test('写出的文件能被自己读回来', () async {
      final File file = await BackupExporter.write(sample());

      expect(await file.exists(), isTrue);
      expect(file.path, endsWith('cmsplayer-backup-20261111-223705.json'));
      expect(await file.length(), greaterThan(0));

      final BackupBundle back =
          BackupBundle.decode(await file.readAsString())!;
      expect(back.history.single.vodName, '庆余年');
      expect(back.sources.single.name, '测试站');
    });

    test('同一秒里连写两次不会互相覆盖', () async {
      final File first = await BackupExporter.write(sample());
      final File second = await BackupExporter.write(sample());

      expect(first.path, isNot(second.path));
      expect(second.path, endsWith('-1.json'));
      expect(await first.exists(), isTrue);
      expect(await second.exists(), isTrue);
    });

    test('目录不存在时自动创建', () async {
      final Directory nested = Directory('${dir.path}/a/b');
      BackupExporter.directoryOverride = () => nested;

      final File file = await BackupExporter.write(sample());
      expect(await nested.exists(), isTrue);
      expect(await file.exists(), isTrue);
    });
  });
}
