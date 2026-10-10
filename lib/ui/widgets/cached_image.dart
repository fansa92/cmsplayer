import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/logger.dart';
import '../../core/storage/app_dirs.dart';
import '../../core/theme/app_theme.dart';

/// 带两级缓存（内存 + 磁盘）的图片组件。
///
/// 不用 `cached_network_image` 的原因：它依赖 flutter_cache_manager，
/// 在桌面端行为不够可控；这里只有几十行，且五端逻辑完全一致。
class CachedImage extends StatefulWidget {
  const CachedImage({
    super.key,
    required this.url,
    this.headers = const <String, String>{},
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.icon = Icons.broken_image_outlined,
  });

  final String url;
  final Map<String, String> headers;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData icon;

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  static final Map<String, Uint8List> _memory = <String, Uint8List>{};
  static const int _maxMemoryEntries = 300;

  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolve();
  }

  Future<void> _resolve() async {
    final String url = widget.url.trim();
    if (url.isEmpty) {
      if (mounted) setState(() => _bytes = null);
      return;
    }

    final Uint8List? cached = _memory[url];
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }

    if (mounted) setState(() => _loading = true);
    try {
      final Uint8List bytes = await _load(url, widget.headers);
      _memory[url] = bytes;
      while (_memory.length > _maxMemoryEntries) {
        _memory.remove(_memory.keys.first);
      }
      if (mounted) setState(() { _bytes = bytes; _loading = false; });
    } on Object catch (e) {
      AppLog.d('CachedImage', '$url -> $e');
      if (mounted) setState(() { _bytes = null; _loading = false; });
    }
  }

  static Future<Uint8List> _load(
    String url,
    Map<String, String> headers,
  ) async {
    final String key = sha1.convert(utf8.encode(url)).toString();

    File file = _fileFor(key);
    try {
      if (await file.exists()) {
        final Uint8List bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } on Object {
      file = _fileFor(key);
    }

    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('图片地址无效');
    }

    final http.Response resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}', uri: uri);
    }
    final Uint8List bytes = resp.bodyBytes;
    if (bytes.isEmpty) throw const HttpException('空图片数据');

    try {
      await file.writeAsBytes(bytes, flush: false);
    } on Object catch (e) {
      AppLog.d('CachedImage', 'disk cache write failed: $e');
    }
    return bytes;
  }

  static File _fileFor(String key) {
    final String dir =
        AppDirs.isReady ? AppDirs.imageCache.path : AppDirs.fallback.path;
    return File(p.join(dir, '$key.img'));
  }

  Widget _placeholder(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppTheme.posterPlaceholder,
        ),
      ),
      child: Center(
        child: Icon(
          widget.icon,
          size: 28,
          color: Colors.white24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    final Uint8List? bytes = _bytes;
    if (bytes != null) {
      child = Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, Object __, StackTrace? ___) => _placeholder(context),
      );
    } else if (_loading) {
      child = _placeholder(context);
    } else {
      child = _placeholder(context);
    }

    final BorderRadius radius = widget.borderRadius ?? BorderRadius.zero;
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: child,
      ),
    );
  }
}
