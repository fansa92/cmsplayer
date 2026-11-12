import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/constants.dart';
import 'package:cms_player/core/errors.dart';
import 'package:cms_player/data/api/update_checker.dart';
import 'package:cms_player/ui/widgets/update_prompt.dart';

import 'helpers/fakes.dart';

/// 更新检查：版本比对、响应解析、失败分支，以及提示框里的复制行为。
void main() {
  group('版本比对', () {
    test('归一化去掉前缀 v 与构建号', () {
      expect(UpdateChecker.normalizeVersion('v1.0.2'), '1.0.2');
      expect(UpdateChecker.normalizeVersion('1.0.2+3'), '1.0.2');
      expect(UpdateChecker.normalizeVersion(' V1.2.3-beta.1 '), '1.2.3');
      expect(UpdateChecker.normalizeVersion(''), '');
    });

    test('按数字段比较，不是按字符串', () {
      expect(UpdateChecker.compareVersions('1.0.10', '1.0.9'), 1);
      expect(UpdateChecker.compareVersions('1.0.9', '1.0.10'), -1);
      expect(UpdateChecker.compareVersions('1.0.2', '1.0.2'), 0);
    });

    test('段数不同时短的补 0', () {
      expect(UpdateChecker.compareVersions('1.1', '1.1.0'), 0);
      expect(UpdateChecker.compareVersions('1.1.1', '1.1'), 1);
      expect(UpdateChecker.compareVersions('2', '1.9.9'), 1);
    });

    test('前缀 v 与构建号不影响判断', () {
      expect(UpdateChecker.isNewer('v1.0.3', '1.0.2+3'), isTrue);
      expect(UpdateChecker.isNewer('v1.0.2', '1.0.2+3'), isFalse);
      expect(UpdateChecker.isNewer('1.0.1', '1.0.2'), isFalse);
    });

    test('无法解析的段按 0 处理，不把用户引向降级', () {
      expect(UpdateChecker.compareVersions('abc', '1.0.0'), -1);
      expect(UpdateChecker.isNewer('weird', K.appVersion), isFalse);
    });
  });

  group('响应解析', () {
    Map<String, dynamic> release({
      String tag = 'v1.0.3',
      bool prerelease = false,
      bool draft = false,
      String body = '修了一些问题',
    }) =>
        <String, dynamic>{
          'tag_name': tag,
          'html_url': 'https://github.com/fansa92/cmsplayer/releases/tag/$tag',
          'body': body,
          'published_at': '2026-11-11T08:00:00Z',
          'prerelease': prerelease,
          'draft': draft,
        };

    test('正常发行版解析出结构化信息', () {
      // 用远期版本号做夹具，避免每次升版本都要跟着改这里。
      final UpdateInfo? info =
          UpdateChecker.parseRelease(release(tag: 'v9.9.9'));
      expect(info, isNotNull);
      expect(info!.version, '9.9.9');
      expect(info.tag, 'v9.9.9');
      expect(info.url, contains('/releases/tag/v9.9.9'));
      expect(info.notes, '修了一些问题');
      expect(info.publishedAt?.toUtc().hour, 8);
      expect(info.isNewer, isTrue);
    });

    test('预发布版与草稿不提示', () {
      expect(UpdateChecker.parseRelease(release(prerelease: true)), isNull);
      expect(UpdateChecker.parseRelease(release(draft: true)), isNull);
    });

    test('没有标签时返回 null，缺链接时回落到发行版列表', () {
      expect(UpdateChecker.parseRelease(<String, dynamic>{}), isNull);
      final UpdateInfo? info = UpdateChecker.parseRelease(
        <String, dynamic>{'tag_name': 'v1.0.3'},
      );
      expect(info?.url, K.releasesPage);
      expect(info?.notes, '');
    });
  });

  group('网络', () {
    test('200 时返回最新发行版', () async {
      final FakeHttpClient client = FakeHttpClient();
      client.queued.add(fakeJson(<String, Object>{
        'tag_name': 'v1.0.9',
        'html_url': 'https://example.com/r/v1.0.9',
        'body': '更新说明',
      }));

      final UpdateInfo? info =
          await UpdateChecker(client: client).latest();

      expect(info?.version, '1.0.9');
      expect(client.last.url.host, 'api.github.com');
      expect(client.last.url.path, contains('/releases/latest'));
      expect(client.last.headers['Accept'], contains('github'));
    });

    test('404 视为「还没有发行版」，不是错误', () async {
      final FakeHttpClient client = FakeHttpClient();
      client.queued.add(fakeResponse(404, '{"message":"Not Found"}'));
      expect(await UpdateChecker(client: client).latest(), isNull);
    });

    test('5xx 抛可读异常', () async {
      final FakeHttpClient client = FakeHttpClient();
      client.queued.add(fakeResponse(503, 'down'));
      await expectLater(
        UpdateChecker(client: client).latest(),
        throwsA(
          isA<VodException>().having(
            (VodException e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });

    test('返回内容不是对象时抛异常', () async {
      final FakeHttpClient client = FakeHttpClient();
      client.queued.add(fakeResponse(200, jsonEncode(<String>['a'])));
      await expectLater(
        UpdateChecker(client: client).latest(),
        throwsA(isA<VodException>()),
      );
    });

    test('网络异常包成 VodException', () async {
      final FakeHttpClient client = FakeHttpClient(
        (RecordedRequest _) => throw const SocketExceptionStub(),
      );
      await expectLater(
        UpdateChecker(client: client).latest(),
        throwsA(isA<VodException>()),
      );
    });
  });

  group('提示框', () {
    const UpdateInfo info = UpdateInfo(
      version: '1.0.3',
      tag: 'v1.0.3',
      url: 'https://github.com/fansa92/cmsplayer/releases/tag/v1.0.3',
      notes: '1. 修了若干问题\n2. 新增榜单页',
    );

    testWidgets('展示版本与发行说明，复制后给出提示', (WidgetTester tester) async {
      final List<MethodCall> platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: ElevatedButton(
                  onPressed: () => showUpdatePrompt(context, info),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 1.0.3'), findsOneWidget);
      expect(find.text('当前 ${K.appVersion} · 最新 1.0.3'), findsOneWidget);
      expect(find.textContaining('新增榜单页'), findsOneWidget);
      expect(find.text(info.url), findsOneWidget);

      await tester.tap(find.text('复制下载链接'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 1.0.3'), findsNothing);
      expect(find.text('下载链接已复制'), findsOneWidget);
      final MethodCall write = platformCalls.firstWhere(
        (MethodCall c) => c.method == 'Clipboard.setData',
      );
      expect((write.arguments as Map)['text'], info.url);
    });

    testWidgets('选择以后再说时不提示复制', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: ElevatedButton(
                  onPressed: () => showUpdatePrompt(context, info),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('以后再说'));
      await tester.pumpAndSettle();

      expect(find.text('下载链接已复制'), findsNothing);
    });
  });
}

/// [FakeHttpClient] 的 responder 要求返回响应，这里用一个只用来抛出的占位异常。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'SocketException: 网络不可用';
}
