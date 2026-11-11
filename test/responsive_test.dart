import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/utils/responsive.dart';

/// 断点行为测试。
///
/// 列数 / 侧边栏 / 双栏详情页全靠屏幕宽度分支，改一个常量的大小关系
/// 就会让手机端变成六列或桌面端退化成底部导航，所以把边界值全部钉住。
void main() {
  testWidgets('断点边界：599 / 600 / 899 / 900 / 1299 / 1300',
      (WidgetTester tester) async {
    await _check(
      tester,
      599,
      'compact=true medium=false expanded=false rail=false cols=3 '
      'twoPane=false width=599.0',
    );
    await _check(
      tester,
      600,
      'compact=false medium=true expanded=false rail=true cols=4 '
      'twoPane=false width=600.0',
    );
    await _check(
      tester,
      899,
      'compact=false medium=true expanded=false rail=true cols=4 '
      'twoPane=false width=899.0',
    );
    await _check(
      tester,
      900,
      'compact=false medium=false expanded=true rail=true cols=5 '
      'twoPane=true width=900.0',
    );
    await _check(
      tester,
      1299,
      'compact=false medium=false expanded=true rail=true cols=5 '
      'twoPane=true width=1299.0',
    );
    await _check(
      tester,
      1300,
      'compact=false medium=false expanded=true rail=true cols=6 '
      'twoPane=true width=1300.0',
    );
  });

  testWidgets('影院模式只在非桌面端开启', (WidgetTester tester) async {
    await tester.pumpWidget(_host(360));
    expect(
      find.text('theater=${!PlatformInfo.isDesktop}'),
      findsOneWidget,
      reason: '桌面端用独立播放窗口，移动端才全屏',
    );
  });
}

Future<void> _check(
  WidgetTester tester,
  double width,
  String expected,
) async {
  await tester.pumpWidget(_host(width));
  expect(find.text(expected), findsOneWidget, reason: '宽度 $width 的布局分支不对');
}

Widget _host(double width) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(
          builder: (BuildContext context) {
            final String flags = <String>[
              'compact=${context.isCompact}',
              'medium=${context.isMedium}',
              'expanded=${context.isExpanded}',
              'rail=${context.useRail}',
              'cols=${context.gridColumns}',
              'twoPane=${context.useDetailTwoPane}',
              'width=${context.screenWidth}',
            ].join(' ');
            return Column(
              children: <Widget>[
                Text(flags),
                Text('theater=${context.useTheaterMode}'),
              ],
            );
          },
        ),
      ),
    );
