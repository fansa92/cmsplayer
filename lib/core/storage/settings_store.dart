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

  // ---------------- 同步 ----------------
  //
  // WebDAV 密码按明文存在应用配置里。这个应用不联网上送任何用户数据，
  // 但本机被他人拿到就能读到 —— 设置页里如实写明了这一点，不假装加密。

  String get syncWebDavUrl => _prefs?.getString(K.prefWebDavUrl) ?? '';

  Future<void> setSyncWebDavUrl(String v) async {
    await _prefs?.setString(K.prefWebDavUrl, v);
  }

  String get syncWebDavUser => _prefs?.getString(K.prefWebDavUser) ?? '';

  Future<void> setSyncWebDavUser(String v) async {
    await _prefs?.setString(K.prefWebDavUser, v);
  }

  String get syncWebDavPass => _prefs?.getString(K.prefWebDavPass) ?? '';

  Future<void> setSyncWebDavPass(String v) async {
    await _prefs?.setString(K.prefWebDavPass, v);
  }

  String get syncWebDavPath {
    final String v = _prefs?.getString(K.prefWebDavPath) ?? '';
    return v.trim().isEmpty ? K.defaultWebDavPath : v.trim();
  }

  Future<void> setSyncWebDavPath(String v) async {
    await _prefs?.setString(K.prefWebDavPath, v);
  }

  String get syncLanHost => _prefs?.getString(K.prefLanHost) ?? '';

  Future<void> setSyncLanHost(String v) async {
    await _prefs?.setString(K.prefLanHost, v);
  }

  int get syncLanPort {
    final int v = _prefs?.getInt(K.prefLanPort) ?? 0;
    return v > 0 ? v : K.defaultLanPort;
  }

  Future<void> setSyncLanPort(int v) async {
    await _prefs?.setInt(K.prefLanPort, v);
  }

  /// 上次同步时刻（毫秒）。0 表示从没同步过。
  int get syncLastAt => _prefs?.getInt(K.prefLastSyncAt) ?? 0;

  Future<void> setSyncLastAt(int v) async {
    await _prefs?.setInt(K.prefLastSyncAt, v);
  }

  String get syncDeviceName => _prefs?.getString(K.prefDeviceName) ?? '';

  Future<void> setSyncDeviceName(String v) async {
    await _prefs?.setString(K.prefDeviceName, v);
  }

  /// 设置是否真的落盘成功（用于"设置已保存"的提示）。
  bool get persisted => _ok;
}
