import 'package:flutter/material.dart';

import '../data/models/play_task.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import '../data/repository/vod_repository.dart';
import 'navigation.dart';

/// 页面级副作用的集中入口：加载遮罩、提示条、收藏/历史的跳转动作。
class AppActions {
  AppActions._();

  // ---------------------------------------------------------------- 反馈

  static void snack(BuildContext context, String message) {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static void snackError(BuildContext context, Object error) {
    snack(context, _friendly(error));
  }

  /// 把异常转成用户能看懂的话。
  static String _friendly(Object error) {
    final String text = error.toString();
    if (text.contains('SocketException')) return '网络连接失败，请检查网络';
    if (text.contains('TimeoutException')) return '请求超时，资源站可能繁忙';
    if (text.contains('HTTP 4')) return '资源站拒绝了请求（404），接口地址可能已失效';
    if (text.contains('HTTP 5')) return '资源站内部错误（5xx），稍后再试';
    if (text.contains('不是合法 JSON')) return '接口返回的不是数据，可能需要代理或接口已失效';
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  // ---------------------------------------------------------------- 加载遮罩

  /// 弹出一个阻塞式加载框，返回可用来关闭它的路由。
  static Route<void> showBlockingLoading(
    BuildContext context, {
    String message = '正在加载…',
  }) {
    final Route<void> route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BlockingLoading(message: message),
    );
    Navigator.of(context).push(route);
    return route;
  }

  static void dismissRoute(BuildContext context, Route<void> route) {
    final NavigatorState? navigator = Navigator.maybeOf(context);
    if (navigator == null) return;
    try {
      navigator.removeRoute(route);
    } on Object {
      // 路由可能已被 pop，忽略。
    }
  }

  // ---------------------------------------------------------------- 跳转

  /// 从只有 ID / 名称的记录（收藏、历史）补齐完整详情后进入详情页。
  static Future<void> openMinimalItem(
    BuildContext context, {
    required VodSource source,
    required int vodId,
    required String vodName,
    String vodPic = '',
  }) async {
    final Route<void> loading = showBlockingLoading(context, message: '正在获取详情…');
    try {
      final VodItem detail = await VodRepository.instance.ensureDetail(
        source: source,
        item: VodItem(id: vodId, name: vodName, pic: vodPic),
        force: true,
      );
      if (!context.mounted) return;
      dismissRoute(context, loading);
      await AppRoutes.openDetail(context, item: detail, source: source);
    } on Object catch (e) {
      if (!context.mounted) return;
      dismissRoute(context, loading);
      snackError(context, e);
    }
  }

  /// 从播放记录直接续播。
  static Future<void> resumeFromRecord(
    BuildContext context, {
    required VodSource source,
    required int vodId,
    required String vodName,
    String vodPic = '',
    required int lineIndex,
    required int episodeIndex,
  }) async {
    final Route<void> loading = showBlockingLoading(context, message: '正在准备播放…');
    try {
      final VodItem detail = await VodRepository.instance.ensureDetail(
        source: source,
        item: VodItem(id: vodId, name: vodName, pic: vodPic),
        force: true,
      );
      if (!context.mounted) return;
      dismissRoute(context, loading);

      final PlayTask task = PlayTask(
        source: source,
        item: detail,
        lineIndex: _clampIndex(lineIndex, detail.playLines.length),
        episodeIndex: episodeIndex,
      );
      await AppRoutes.openPlayer(context, task: task);
    } on Object catch (e) {
      if (!context.mounted) return;
      dismissRoute(context, loading);
      snackError(context, e);
    }
  }

  static int _clampIndex(int value, int length) {
    if (length <= 0) return 0;
    return value < 0 ? 0 : (value >= length ? length - 1 : value);
  }
}

class _BlockingLoading extends StatelessWidget {
  const _BlockingLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: <Widget>[
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
