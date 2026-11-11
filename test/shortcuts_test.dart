import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/ui/shell/app_shortcuts.dart';

/// 主界面快捷键：按键映射、文本输入时不抢字符、说明弹窗。
void main() {
  late int searches;
  late int tab;

  setUp(() {
    searches = 0;
    tab = -1;
  });

  Widget host({Widget body = const SizedBox.expand()}) {
    return MaterialApp(
      home: Scaffold(
        body: AppShortcuts(
          tabCount: 5,
          onSelectTab: (int i) => tab = i,
          onSearch: () => searches++,
          child: body,
        ),
      ),
    );
  }

  Future<void> pressWith(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl/⌘ + F 触发搜索', (WidgetTester tester) async {
    await tester.pumpWidget(host());

    await pressWith(
        tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF);
    expect(searches, 1);

    await pressWith(
        tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyF);
    expect(searches, 2, reason: 'macOS 的 ⌘ + F 也要能用');
  });

  testWidgets('Ctrl + 数字切换页签，超出页签数不响应', (WidgetTester tester) async {
    await tester.pumpWidget(host());

    await pressWith(
        tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.digit3);
    expect(tab, 2, reason: '数字 3 对应第 3 个页签（下标 2）');

    await pressWith(
        tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.digit9);
    expect(tab, 2, reason: '只有 5 个页签，9 不该有映射');
  });

  testWidgets('斜杠跳到搜索，但在输入框里打字时不会抢走光标', (WidgetTester tester) async {
    await tester.pumpWidget(host(body: const TextField()));

    // 没有焦点时，/ 直接触发搜索。
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();
    expect(searches, 1);

    // 输入框拿到焦点后，/ 应该是一个普通字符。
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();
    expect(searches, 1, reason: '正在输入时不能把 / 当快捷键');
  });

  testWidgets('问号弹出快捷键说明', (WidgetTester tester) async {
    await tester.pumpWidget(host());

    await pressWith(
        tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.slash);
    expect(find.text('键盘快捷键'), findsOneWidget);
    expect(find.text('Ctrl/⌘ + 1 ~ 5'), findsOneWidget);
  });

  testWidgets('最外层按 Esc 不崩，也不会把页面弹掉', (WidgetTester tester) async {
    await tester.pumpWidget(host());

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppShortcuts), findsOneWidget);
  });
}
