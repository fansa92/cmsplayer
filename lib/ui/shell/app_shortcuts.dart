import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 主界面的键盘快捷键。
///
/// 只挂在 shell 上：播放页、设置页、资源站管理都是独立路由，它们有自己的
/// 焦点栈，首页的快捷键不该伸进去抢按键。
///
/// | 按键 | 行为 |
/// | --- | --- |
/// | `Ctrl/⌘ + F`、`/` | 跳到搜索页并聚焦输入框 |
/// | `Ctrl/⌘ + 1..5` | 切换到第 N 个页签 |
/// | `Esc` | 返回上一层；已在最外层时收起输入焦点 |
/// | `?` | 显示这份快捷键说明 |
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.tabCount,
    required this.onSelectTab,
    required this.onSearch,
    required this.child,
  });

  /// 页签数量，决定 `Ctrl/⌘ + 数字` 的上限。
  final int tabCount;

  final ValueChanged<int> onSelectTab;
  final VoidCallback onSearch;
  final Widget child;

  static const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  /// 当前焦点是否落在文本输入里。
  ///
  /// `/` 和 `?` 都是能直接打出来的字符，用户正在输入框里打字时不能让
  /// 它们变成快捷键 —— 否则搜「/」开头的片名会把焦点抢走。
  static bool get _isEditingText {
    final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Map<ShortcutActivator, VoidCallback> _bindings(BuildContext context) {
    final Map<ShortcutActivator, VoidCallback> map =
        <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): onSearch,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): onSearch,
      const SingleActivator(LogicalKeyboardKey.slash): () {
        if (!_isEditingText) onSearch();
      },
      const SingleActivator(LogicalKeyboardKey.escape): () => _back(context),
      const SingleActivator(LogicalKeyboardKey.slash, shift: true): () {
        if (!_isEditingText) showShortcutHelp(context);
      },
    };

    for (int i = 0; i < tabCount && i < _digits.length; i++) {
      map[SingleActivator(_digits[i], control: true)] = () => onSelectTab(i);
      map[SingleActivator(_digits[i], meta: true)] = () => onSelectTab(i);
    }
    return map;
  }

  void _back(BuildContext context) {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
      return;
    }
    // 已经在最外层，Esc 的合理语义是「把光标从输入框里拿出来」。
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _bindings(context),
      // 快捷键节点必须是根焦点节点的**祖先**：按键事件只会沿焦点链向上冒泡。
      // 所以 autofocus 放在内层，事件从这里向上到达 CallbackShortcuts。
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// 快捷键说明弹窗。桌面端把快捷键做出来却没人知道，等于没做。
Future<void> showShortcutHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) {
      final ThemeData theme = Theme.of(ctx);
      const List<(String, String)> rows = <(String, String)>[
        ('Ctrl/⌘ + F  ·  /', '搜索'),
        ('Ctrl/⌘ + 1 ~ 5', '切换页签'),
        ('Esc', '返回上一层'),
        ('?', '显示这份说明'),
      ];
      return AlertDialog(
        title: const Text('键盘快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (String keys, String desc) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        keys,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      desc,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}
