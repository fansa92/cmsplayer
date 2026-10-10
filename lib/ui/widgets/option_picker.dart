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
            padding: const EdgeInsets.only(bottom: 12),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                  leading: Icon(
                    selected == null || selected == clearValue
                        ? Icons.check
                        : Icons.close,
                    size: 20,
                  ),
                  title: Text(clearLabel),
                  onTap: () => Navigator.of(ctx).pop(clearValue),
                ),
              for (final String option in options)
                ListTile(
                  dense: true,
                  leading: Icon(
                    option == selected ? Icons.check : Icons.square_outlined,
                    size: 20,
                  ),
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
