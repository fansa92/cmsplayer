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
    // 用户明确挑了默认倍速，就让它成为「下次开播用的倍速」，
    // 否则会被上一部片记忆的倍速盖掉，看起来像设置没生效。
    await _settings.setLastRate(v);
    notifyListeners();
  }

  /// 上次播放用的倍速（0 表示没记过）。
  double get lastRate => _settings.lastRate;

  Future<void> setLastRate(double v) => _settings.setLastRate(v);

  /// 上次播放用的画面比例。
  String get lastFit => _settings.lastFit;

  Future<void> setLastFit(String v) => _settings.setLastFit(v);

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

  bool get exactSearch => _settings.exactSearch;

  Future<void> setExactSearch(bool v) async {
    await _settings.setExactSearch(v);
    notifyListeners();
  }

  /// 关闭窗口时收进托盘（仅桌面端有意义）。
  bool get closeToTray => _settings.closeToTray;

  Future<void> setCloseToTray(bool v) async {
    await _settings.setCloseToTray(v);
    notifyListeners();
  }

  // ---------------- 详情页 ----------------
  bool get episodeOrderReverse => _settings.episodeOrderReverse;

  Future<void> setEpisodeOrderReverse(bool v) async {
    await _settings.setEpisodeOrderReverse(v);
    notifyListeners();
  }

  // ---------------- 片头片尾 ----------------
  bool get autoSkipIntro => _settings.autoSkipIntro;

  Future<void> setAutoSkipIntro(bool v) async {
    await _settings.setAutoSkipIntro(v);
    notifyListeners();
  }

  bool get autoSkipOutro => _settings.autoSkipOutro;

  Future<void> setAutoSkipOutro(bool v) async {
    await _settings.setAutoSkipOutro(v);
    notifyListeners();
  }

  /// 按片名记住片头片尾。
  bool get rememberSkipMarks => _settings.rememberSkipMarks;

  Future<void> setRememberSkipMarks(bool v) async {
    await _settings.setRememberSkipMarks(v);
    notifyListeners();
  }
}
