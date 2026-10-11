import 'sync_payload.dart';

/// 同步通道。WebDAV 与局域网各实现一份，[SyncService] 只认这个接口。
abstract class SyncTransport {
  /// 通道名，用于日志与提示。
  String get label;

  /// 拉取远端数据包。远端还没有任何数据时返回 null。
  Future<SyncPayload?> download();

  /// 推送本地合并结果。
  ///
  /// 返回值是**对方合并之后**的数据包：局域网的对端会再合一次并回传，
  /// 而 WebDAV 是原样落盘，此时返回 null 表示"对方现在就是我发的这份"。
  Future<SyncPayload?> upload(SyncPayload payload);

  /// 关闭底层连接。
  void close() {}
}

/// 同步失败。[message] 是直接给用户看的中文原因，不要再拼堆栈进去。
class SyncException implements Exception {
  const SyncException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
