import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

/// 顶栏电量徽标，只在移动端渲染。
///
/// 之所以自己画而不是塞进状态栏：播放页是全屏沉浸的，系统状态栏多半被
/// 隐藏了，看不到电量正是全屏看片时最常见的抱怨。
///
/// 取值走 [Battery] 插件（五端都有实现）。拿不到电量时保持隐藏而不是显示
/// 一个 0% 或占位符 —— 一个错误的数字比没有数字更误导人。
class BatteryBadge extends StatefulWidget {
  const BatteryBadge({super.key});

  @override
  State<BatteryBadge> createState() => _BatteryBadgeState();
}

class _BatteryBadgeState extends State<BatteryBadge> {
  /// 插件内部是单例，用静态字段避免每次重建控制栏都新建一份。
  static final Battery _battery = Battery();

  StreamSubscription<BatteryState>? _sub;
  Timer? _timer;

  int _level = -1;
  bool _charging = false;

  @override
  void initState() {
    super.initState();
    _sub = _battery.onBatteryStateChanged.listen((BatteryState state) {
      _applyState(state);
    });
    _refresh();

    // 电量涨落很慢，但用户抬眼看这一行时往往正是想确认还剩多少。
    // 一分钟一次足够实时，也不至于在播放中持续唤醒平台通道。
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final int level;
    final BatteryState state;
    try {
      level = await _battery.batteryLevel;
      state = await _battery.batteryState;
    } on Object {
      // 模拟器、桌面、或者插件在该平台上未注册时会走到这里。
      if (mounted && _level >= 0) setState(() => _level = -1);
      return;
    }
    if (!mounted) return;
    setState(() {
      _level = level;
      _charging = state == BatteryState.charging || state == BatteryState.full;
    });
  }

  void _applyState(BatteryState state) {
    if (!mounted) return;
    final bool charging =
        state == BatteryState.charging || state == BatteryState.full;
    if (charging == _charging) return;
    setState(() => _charging = charging);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_level < 0) return const SizedBox.shrink();

    final bool low = !_charging && _level <= 20;
    final Color color = low
        ? const Color(0xFFFF8A80) // 低电量用浅红，黑底渐变上仍然看得清
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _charging ? Icons.battery_charging_full : _iconFor(_level),
            size: 18,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '${_level.clamp(0, 100)}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: low ? FontWeight.w600 : FontWeight.w500,
              // 与进度条时间一致用等宽数字，跳变时不会左右抖。
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(int level) {
    if (level >= 90) return Icons.battery_full;
    if (level >= 65) return Icons.battery_6_bar;
    if (level >= 45) return Icons.battery_4_bar;
    if (level >= 25) return Icons.battery_3_bar;
    if (level >= 10) return Icons.battery_2_bar;
    if (level > 0) return Icons.battery_1_bar;
    return Icons.battery_alert;
  }
}
