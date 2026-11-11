import 'package:flutter/material.dart';

/// 设置页 / 同步页 / 源管理页共用的段落式说明文字。
///
/// 之前三处各写了一份 `TextStyle(fontSize: 12, height: 1.7)`：字号脱离
/// `TextTheme` 后，字号缩放（系统字体大小）对它无效，深色下也没有跟随
/// `onSurfaceVariant`。统一到这里。
class HintParagraph extends StatelessWidget {
  const HintParagraph(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
  });

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          height: 1.7,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
