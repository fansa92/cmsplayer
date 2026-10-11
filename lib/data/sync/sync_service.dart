import '../repository/record_repository.dart';
import '../repository/source_repository.dart';
import 'sync_merge.dart';
import 'sync_payload.dart';
import 'sync_tombstones.dart';
import 'sync_transport.dart';

/// 一次同步的结果。
class SyncOutcome {
  const SyncOutcome({required this.diff, required this.firstTime});

  final SyncDiff diff;

  /// 远端在这次同步之前还没有任何数据（首次上传）。
  final bool firstTime;
}

/// 同步编排。
///
/// 流程固定为四步：**读本地 → 拉远端 → 合并 → 推远端**，
/// 任何一步失败都原样抛出 [SyncException]，绝不在中途把本地写坏。
///
/// 不做"覆盖式"同步是有原因的：两台设备各看各的片，整包覆盖必然丢掉
/// 一边的进度；按 key + 时间戳逐条合并才两边都保得住。
class SyncService {
  SyncService._();

  /// 把本地三份数据装配成一个数据包。
  static Future<SyncPayload> readLocal() async {
    return SyncPayload(
      updatedAt: DateTime.now(),
      history: await RecordRepository.loadHistory(),
      favorites: await RecordRepository.loadFavorites(),
      sources: await SourceRepository.load(),
      tombstones: await SyncTombstones.instance.load(),
    );
  }

  /// 把数据包写回本地三份数据。调用方随后要让各个 Store 重新 load()，
  /// 否则界面上还停着合并前的内容。
  static Future<void> writeLocal(SyncPayload payload) async {
    await RecordRepository.saveHistory(payload.history);
    await RecordRepository.saveFavorites(payload.favorites);
    await SourceRepository.save(payload.sources);
    await SyncTombstones.instance.replaceAll(payload.tombstones);
  }

  static Future<SyncOutcome> run(SyncTransport transport) async {
    final SyncPayload local = await readLocal();
    final SyncPayload? remote = await transport.download();

    SyncPayload merged = local;
    if (remote != null) merged = SyncMerger.merge(local, remote);

    // 推送与拉取之间对端可能又动了（局域网尤其常见）。推完把它合并后的
    // 结果再拉回来合一次，两轮之后两端必然收敛到同一份数据。
    final SyncPayload? back = await transport.upload(merged);
    if (back != null) merged = SyncMerger.merge(merged, back);

    await writeLocal(merged);
    return SyncOutcome(
      diff: SyncMerger.diff(local, merged),
      firstTime: remote == null,
    );
  }
}
