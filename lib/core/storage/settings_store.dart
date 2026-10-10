import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../logger.dart';

/// 轻量设置存储（SharedPreferences）。
///
/// 初始化失败时会退化为"全部使用默认值"，保证应用在任何环境都能启动。
class SettingsStore {
  SharedPreferences? _prefs;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } on Object catch (e, s) {
      AppLog.e('SettingsStore', 'init failed: $e', s);
      _prefs = null;
    }
  }

  bool get _ok => _prefs != null;

  // ---------------- 外观 ----------------
  ThemeMode get themeMode {
    final int raw = _prefs?.getInt(K.prefThemeMode) ?? 0;
    switch (raw) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final int raw = switch (mode) {
      ThemeMode.light => 1,
      ThemeMode.dark => 2,
      ThemeMode.system => 0,
    };
    await _prefs?.setInt(K.prefThemeMode, raw);
  }

  // ---------------- 源 ----------------
  String get activeSourceId => _prefs?.getString(K.prefActiveSource) ?? '';

  Future<void> setActiveSourceId(String id) async {
    await _prefs?.setString(K.prefActiveSource, id);
  }

  // ---------------- 播放 ----------------
  double get defaultRate {
    final double v = _prefs?.getDouble(K.prefDefaultRate) ?? 1.0;
    return v <= 0 ? 1.0 : v;
  }

  Future<void> setDefaultRate(double v) async {
    await _prefs?.setDouble(K.prefDefaultRate, v);
  }

  bool get autoNextEpisode => _prefs?.getBool(K.prefAutoNext) ?? true;

  Future<void> setAutoNextEpisode(bool v) async {
    await _prefs?.setBool(K.prefAutoNext, v);
  }

  bool get resumePlayback => _prefs?.getBool(K.prefResume) ?? true;

  Future<void> setResumePlayback(bool v) async {
    await _prefs?.setBool(K.prefResume, v);
  }

  bool get keepScreenOn => _prefs?.getBool(K.prefKeepScreenOn) ?? true;

  Future<void> setKeepScreenOn(bool v) async {
    await _prefs?.setBool(K.prefKeepScreenOn, v);
  }

  bool get showControlsOnStart =>
      _prefs?.getBool(K.prefShowControlsOnStart) ?? true;

  Future<void> setShowControlsOnStart(bool v) async {
    await _prefs?.setBool(K.prefShowControlsOnStart, v);
  }

  bool get hardwareDecode => _prefs?.getBool(K.prefHardwareDecode) ?? true;

  Future<void> setHardwareDecode(bool v) async {
    await _prefs?.setBool(K.prefHardwareDecode, v);
  }

  bool get multiSourceSearch =>
      _prefs?.getBool(K.prefMultiSourceSearch) ?? false;

  Future<void> setMultiSourceSearch(bool v) async {
    await _prefs?.setBool(K.prefMultiSourceSearch, v);
  }

  /// 设置是否真的落盘成功（用于"设置已保存"的提示）。
  bool get persisted => _ok;
}
