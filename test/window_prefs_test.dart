import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cms_player/core/constants.dart';
import 'package:cms_player/core/storage/settings_store.dart';

import 'helpers/fakes.dart';

/// 桌面窗口相关的偏好：位置尺寸记忆、关闭到托盘开关。
void main() {
  useIsolatedStores();

  Future<SettingsStore> settings() async {
    final SettingsStore store = SettingsStore();
    await store.init();
    return store;
  }

  test('窗口位置尺寸能存能取', () async {
    final SettingsStore store = await settings();
    expect(store.windowBounds, isNull);

    await store.setWindowBounds(const Rect.fromLTWH(120, 80, 1280, 820));
    expect(
      store.windowBounds,
      const Rect.fromLTWH(120, 80, 1280, 820),
    );

    // 再存一次要覆盖，不是追加。
    await store.setWindowBounds(const Rect.fromLTWH(-60, 40, 1600, 900));
    expect(
      store.windowBounds,
      const Rect.fromLTWH(-60, 40, 1600, 900),
    );
  });

  test('尺寸过小、字段缺失、坐标离谱的记录都当作没记过', () async {
    for (final String raw in <String>[
      '0,0,200,150', // 比最小窗口还小
      '0,0,1280', // 少一个字段
      'a,0,1280,800', // 不是数字
      '-20000,0,1280,800', // 跑到屏幕外很远
    ]) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        K.prefWindowBounds: raw,
      });
      final SettingsStore store = await settings();
      expect(store.windowBounds, isNull, reason: raw);
    }
  });

  test('关闭到托盘默认开，可以关掉', () async {
    final SettingsStore store = await settings();
    expect(store.closeToTray, isTrue);

    await store.setCloseToTray(false);
    expect(store.closeToTray, isFalse);

    final SettingsStore reloaded = await settings();
    expect(reloaded.closeToTray, isFalse);
  });
}
