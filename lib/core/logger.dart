import 'package:flutter/foundation.dart';

/// 极简日志封装：release 构建下静默。
class AppLog {
  AppLog._();

  static void d(String tag, Object message) {
    if (kDebugMode) debugPrint('[$tag] $message');
  }

  static void e(String tag, Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[$tag][ERROR] $error');
      if (stack != null) debugPrint('[$tag][STACK] $stack');
    }
  }
}
