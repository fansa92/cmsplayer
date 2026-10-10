import 'package:flutter/material.dart';

import '../data/models/play_task.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import 'pages/detail_page.dart';
import 'pages/source_page.dart';
import 'player/player_page.dart';

/// 页面跳转集中在这里，方便统一改动画 / 传参。
class AppRoutes {
  AppRoutes._();

  static Future<VodItem?> openDetail(
    BuildContext context, {
    required VodItem item,
    required VodSource source,
  }) {
    return Navigator.of(context).push<VodItem>(
      MaterialPageRoute<VodItem>(
        builder: (_) => DetailPage(item: item, source: source),
      ),
    );
  }

  static Future<void> openPlayer(
    BuildContext context, {
    required PlayTask task,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: false,
        builder: (_) => PlayerPage(task: task),
      ),
    );
  }

  static Future<void> openSourceManager(
    BuildContext context, {
    bool asHome = false,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SourcePage(asHome: asHome),
      ),
    );
  }
}
