import 'package:flutter/material.dart';

import '../data/models/play_task.dart';
import '../data/models/vod_item.dart';
import '../data/models/vod_source.dart';
import 'pages/detail_page.dart';
import 'pages/keyword_page.dart';
import 'pages/rank_page.dart';
import 'pages/source_compare_page.dart';
import 'pages/source_page.dart';
import 'pages/stats_page.dart';
import 'pages/subscriptions_page.dart';
import 'pages/updates_page.dart';
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

  /// 订阅管理：一个地址维护一批资源站。
  static Future<void> openSubscriptions(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SubscriptionsPage()),
    );
  }

  static Future<void> openRank(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const RankPage()),
    );
  }

  /// 追剧更新中心：收藏里哪些出了新集。
  static Future<void> openUpdates(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const UpdatesPage()),
    );
  }

  /// 全源对比：同一部片在各启用源里的集数 / 线路 / 播放地址。
  static Future<void> openCompare(
    BuildContext context, {
    required String title,
    String year = '',
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SourceComparePage(title: title, year: year),
      ),
    );
  }

  /// 观看统计。
  static Future<void> openStats(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const StatsPage()),
    );
  }

  /// 按演员 / 导演名看同一个源里还有哪些片子。
  static Future<void> openKeyword(
    BuildContext context, {
    required VodSource source,
    required String keyword,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => KeywordPage(
          source: source,
          title: keyword,
          keyword: keyword,
        ),
      ),
    );
  }

  /// 按分类看更多（详情页点分类标签）。
  static Future<void> openCategory(
    BuildContext context, {
    required VodSource source,
    required int typeId,
    required String title,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => KeywordPage(
          source: source,
          title: title,
          typeId: typeId,
        ),
      ),
    );
  }
}
