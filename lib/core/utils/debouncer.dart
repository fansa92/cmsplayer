import 'dart:async';

/// 简单的防抖定时器。
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  /// 重新计时；到点后执行最近一次传入的回调。
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}

/// 节流：保证 [interval] 内最多执行一次。
class Throttler {
  Throttler(this.interval);

  final Duration interval;
  DateTime? _last;

  bool get shouldRun {
    final DateTime now = DateTime.now();
    final DateTime? last = _last;
    if (last == null || now.difference(last) >= interval) {
      _last = now;
      return true;
    }
    return false;
  }

  void reset() => _last = null;
}
