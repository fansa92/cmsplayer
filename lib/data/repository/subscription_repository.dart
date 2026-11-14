import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../core/storage/json_store.dart';
import '../models/subscription.dart';

/// 订阅列表持久化。
class SubscriptionRepository {
  SubscriptionRepository._();

  static Future<List<Subscription>> load() async {
    final List<Map<String, dynamic>> raw =
        await JsonStore.readList(K.boxSubscriptions);
    final List<Subscription> list = <Subscription>[];
    final Set<String> seen = <String>{};
    for (final Map<String, dynamic> json in raw) {
      try {
        final Subscription sub = Subscription.fromJson(json);
        if (!sub.isUsable) continue;
        if (!seen.add(sub.id)) continue;
        list.add(sub);
      } on Object catch (e) {
        AppLog.d('SubscriptionRepository', 'bad entry: $e');
      }
    }
    return list;
  }

  static Future<void> save(List<Subscription> items) async {
    await JsonStore.writeList(
      K.boxSubscriptions,
      items.map((Subscription s) => s.toJson()).toList(),
    );
  }

  static Future<void> clear() => JsonStore.deleteFile(K.boxSubscriptions);
}
