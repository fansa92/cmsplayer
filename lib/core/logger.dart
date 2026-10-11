import 'package:flutter/foundation.dart';

/// 极简日志封装：release 构建下静默。
class AppLog {
  AppLog._();

  static void d(String tag, Object message) {
    if (kDebugMode) debugPrint('[$tag] $message');
  }

  /// 同步这类"失败了但不影响主流程"的情况用这个级别。
  ///
  /// 夹在 d 和 e 之间：比 debug 显眼（release 前排查网络问题时要靠它），
  /// 又不至于像 e 那样看着像致命错误。
  static void w(String tag, Object message) {
    if (kDebugMode) debugPrint('[$tag][WARN] $message');
  }

  static void e(String tag, Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[$tag][ERROR] $error');
      if (stack != null) debugPrint('[$tag][STACK] $stack');
    }
  }
}
