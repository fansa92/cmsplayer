/// 统一的接口 / 业务异常。
class VodException implements Exception {
  const VodException(this.message, {this.url, this.cause});

  final String message;

  /// 出错时请求的地址，便于排查。
  final String? url;

  final Object? cause;

  @override
  String toString() {
    final StringBuffer buf = StringBuffer(message);
    if (url != null && url!.isNotEmpty) buf.write(' ($url)');
    if (cause != null) buf.write(' <- $cause');
    return buf.toString();
  }
}
