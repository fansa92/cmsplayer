import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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
///
/// 三个和观感直接相关的细节：
/// * 按**显示宽度**解码（`cacheWidth`），海报原图常见 1000px+，网格里只显示
///   120px，全尺寸解码会让几十张海报吃掉几百 MB；
/// * 内存缓存按字节数做 LRU，而不是按条目数 —— 条目数限制挡不住大图；
/// * 用递增的 [_generation] 丢弃过期请求，快速滚动复用卡片时旧图不会盖住新图。
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

  /// 下面三个只给测试用：验证内存缓存按字节淘汰、用例之间互不污染。
  /// 放在 public 类上而不是私有的 State 里，测试才拿得到。
  @visibleForTesting
  static int get memoryBytes => _CachedImageState._memoryBytes;

  @visibleForTesting
  static void clearMemoryCache() {
    _CachedImageState._memory.clear();
    _CachedImageState._memoryBytes = 0;
  }

  @visibleForTesting
  static void putMemoryCache(String url, Uint8List bytes) =>
      _CachedImageState._writeMemory(url, bytes);

  @visibleForTesting
  static bool hasMemoryCache(String url) =>
      _CachedImageState._memory.containsKey(url);

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  /// 内存缓存。Map 的插入顺序当作 LRU 顺序：命中时删掉再插回末尾。
  static final Map<String, Uint8List> _memory = <String, Uint8List>{};
  static int _memoryBytes = 0;

  /// 48 MB 上限。桌面端 6 列网格全屏可见约 30 张，留足余量又不至于无限增长。
  static const int _maxMemoryBytes = 48 * 1024 * 1024;

  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.headers != widget.headers) {
      _resolve();
    }
  }

  static Uint8List? _readMemory(String url) {
    final Uint8List? bytes = _memory.remove(url);
    if (bytes != null) _memory[url] = bytes;
    return bytes;
  }

  static void _writeMemory(String url, Uint8List bytes) {
    final Uint8List? previous = _memory.remove(url);
    if (previous != null) _memoryBytes -= previous.length;
    _memory[url] = bytes;
    _memoryBytes += bytes.length;
    while (_memoryBytes > _maxMemoryBytes && _memory.isNotEmpty) {
      final String oldest = _memory.keys.first;
      final Uint8List? removed = _memory.remove(oldest);
      if (removed != null) _memoryBytes -= removed.length;
    }
  }

  Future<void> _resolve() async {
    final int generation = ++_generation;
    final String url = widget.url.trim();
    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _loading = false;
          _failed = false;
        });
      }
      return;
    }

    final Uint8List? cached = _readMemory(url);
    if (cached != null) {
      if (mounted && generation == _generation) {
        setState(() {
          _bytes = cached;
          _loading = false;
          _failed = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _bytes = null;
        _loading = true;
        _failed = false;
      });
    }
    try {
      final Uint8List bytes = await _load(url, widget.headers);
      _writeMemory(url, bytes);
      if (!mounted || generation != _generation) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
        _failed = false;
      });
    } on Object catch (e) {
      AppLog.d('CachedImage', '$url -> $e');
      if (!mounted || generation != _generation) return;
      setState(() {
        _bytes = null;
        _loading = false;
        _failed = true;
      });
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

  /// 加载中与加载失败必须是两种样子：原来是同一个占位（if/else 两个分支
  /// 返回同一个 widget），用户完全看不出图片是还在下还是已经挂了。
  ///
  /// 加载态刻意不用 CircularProgressIndicator：它是无限动画，会让任何
  /// pump 到海报卡片的 widget test 里的 `pumpAndSettle()` 永远等不到稳定帧。
  Widget _placeholder(
    BuildContext context, {
    required bool loading,
    VoidCallback? onRetry,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final List<Color> colors = dark
        ? AppTheme.posterPlaceholder
        : <Color>[
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainerLow,
          ];
    final Color foreground =
        dark ? Colors.white38 : theme.colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        children: <Widget>[
          Center(
            child: Icon(
              loading ? Icons.image_outlined : widget.icon,
              size: 26,
              color: foreground.withValues(alpha: loading ? 0.35 : 0.55),
            ),
          ),
          if (onRetry != null)
            Positioned(
              right: 4,
              bottom: 4,
              child: Semantics(
                button: true,
                label: '重新加载图片',
                child: GestureDetector(
                  onTap: onRetry,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _image(BuildContext context, Uint8List bytes) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final double? targetWidth = widget.width ??
            (constraints.hasBoundedWidth ? constraints.maxWidth : null);
        final int? cacheWidth = targetWidth == null
            ? null
            : (targetWidth * pixelRatio).ceil().clamp(1, 2048);

        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          frameBuilder: (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, Object __, StackTrace? ___) => _placeholder(
            context,
            loading: false,
            onRetry: _resolve,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = _bytes;
    final Widget child;
    if (bytes != null) {
      child = _image(context, bytes);
    } else if (_loading) {
      child = _placeholder(context, loading: true);
    } else {
      child = _placeholder(
        context,
        loading: false,
        onRetry: _failed && widget.url.trim().isNotEmpty ? _resolve : null,
      );
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
