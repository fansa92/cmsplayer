import 'package:flutter/material.dart';

/// 通用的单项选择器（底部弹窗），用于年代 / 地区 / 排序等筛选。
///
/// 返回选中的值；用户点"不限"时返回 [clearValue]；直接下滑关闭返回 null。
Future<String?> showOptionPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? selected,
  bool allowClear = true,
  String clearLabel = '不限',
  String clearValue = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      final ThemeData theme = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (allowClear)
                ListTile(
                  dense: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  leading: _checkMark(
                    theme,
                    selected == null || selected == clearValue,
                  ),
                  title: Text(clearLabel),
                  onTap: () => Navigator.of(ctx).pop(clearValue),
                ),
              for (final String option in options)
                ListTile(
                  dense: true,
                  selected: option == selected,
                  selectedTileColor: theme.colorScheme.secondaryContainer,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  leading: _checkMark(theme, option == selected),
                  title: Text(option),
                  onTap: () => Navigator.of(ctx).pop(option),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 未选中留空位而不是画一个 ✗ / 空方框 —— 单选列表里那些符号会被读成
/// 「这一项被否定了」，实际只是没选中。20 宽的占位保证文字左边缘对齐。
Widget _checkMark(ThemeData theme, bool checked) {
  return SizedBox(
    width: 20,
    child: checked
        ? Icon(Icons.check, size: 20, color: theme.colorScheme.primary)
        : null,
  );
}
