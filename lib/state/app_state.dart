import 'package:flutter/material.dart';

import '../core/storage/settings_store.dart';

/// 全局设置状态。真正的值保存在 [SettingsStore]，这里只负责通知 UI。
class AppState extends ChangeNotifier {
  AppState(this._settings);

  final SettingsStore _settings;

  SettingsStore get settings => _settings;

  // ---------------- 外观 ----------------
  ThemeMode get themeMode => _settings.themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    await _settings.setThemeMode(mode);
    notifyListeners();
  }

  // ---------------- 播放 ----------------
  double get defaultRate => _settings.defaultRate;

  Future<void> setDefaultRate(double v) async {
    await _settings.setDefaultRate(v);
    notifyListeners();
  }

  bool get autoNextEpisode => _settings.autoNextEpisode;

  Future<void> setAutoNextEpisode(bool v) async {
    await _settings.setAutoNextEpisode(v);
    notifyListeners();
  }

  bool get resumePlayback => _settings.resumePlayback;

  Future<void> setResumePlayback(bool v) async {
    await _settings.setResumePlayback(v);
    notifyListeners();
  }

  bool get keepScreenOn => _settings.keepScreenOn;

  Future<void> setKeepScreenOn(bool v) async {
    await _settings.setKeepScreenOn(v);
    notifyListeners();
  }

  bool get showControlsOnStart => _settings.showControlsOnStart;

  Future<void> setShowControlsOnStart(bool v) async {
    await _settings.setShowControlsOnStart(v);
    notifyListeners();
  }

  bool get hardwareDecode => _settings.hardwareDecode;

  Future<void> setHardwareDecode(bool v) async {
    await _settings.setHardwareDecode(v);
    notifyListeners();
  }

  bool get multiSourceSearch => _settings.multiSourceSearch;

  Future<void> setMultiSourceSearch(bool v) async {
    await _settings.setMultiSourceSearch(v);
    notifyListeners();
  }
}
