import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/utils/responsive.dart';
import 'package:cms_player/ui/player/player_chrome.dart';

/// 播放器外观层：拆分出来的 8 个纯展示组件，不需要 media_kit 原生插件。
/// 颜色一律白字 + 黑遮罩（背景是视频画面），这里重点钉住「什么状态显示什么」
/// 以及按钮有没有把回调传出去。
void main() {
  Widget host(Widget child) => MaterialApp(
        home:
            Scaffold(backgroundColor: Colors.black, body: Center(child: child)),
      );

  PlayerTopBar topBar({
    bool locked = false,
    bool fullScreen = false,
    String subtitle = 'm3u8 · 第01集',
    VoidCallback? onBack,
    VoidCallback? onInfo,
    VoidCallback? onEpisodes,
    VoidCallback? onFullScreen,
  }) {
    return PlayerTopBar(
      title: '庆余年',
      subtitle: subtitle,
      locked: locked,
      fullScreen: fullScreen,
      onBack: onBack ?? () {},
      onToggleOrientation: () {},
      onToggleFullScreen: onFullScreen ?? () {},
      onInfo: onInfo ?? () {},
      onEpisodes: onEpisodes ?? () {},
    );
  }

  group('顶栏', () {
    testWidgets('标题、副标题与桌面全屏按钮', (WidgetTester tester) async {
      int backs = 0;
      int fullScreens = 0;
      int infos = 0;
      int episodes = 0;

      await tester.pumpWidget(host(topBar(
        onBack: () => backs++,
        onInfo: () => infos++,
        onEpisodes: () => episodes++,
        onFullScreen: () => fullScreens++,
      )));

      expect(find.text('庆余年'), findsOneWidget);
      expect(find.text('m3u8 · 第01集'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.tap(find.byTooltip('视频信息'));
      await tester.tap(find.byTooltip('选集'));
      expect(<int>[backs, infos, episodes], <int>[1, 1, 1]);

      if (PlatformInfo.isDesktop) {
        expect(find.byTooltip('全屏 (F)'), findsOneWidget);
        await tester.tap(find.byTooltip('全屏 (F)'));
        expect(fullScreens, 1);
      }
    });

    testWidgets('全屏态改成退出图标与对应提示', (WidgetTester tester) async {
      await tester.pumpWidget(host(topBar(fullScreen: true)));
      if (!PlatformInfo.isDesktop) return;

      expect(find.byTooltip('退出全屏 (Esc)'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    });

    testWidgets('锁定时禁用全屏并收起信息/选集，返回键仍可用', (WidgetTester tester) async {
      int backs = 0;
      await tester.pumpWidget(host(topBar(
        locked: true,
        onBack: () => backs++,
      )));

      expect(find.text('庆余年'), findsOneWidget);
      expect(find.byTooltip('视频信息'), findsNothing);
      expect(find.byTooltip('选集'), findsNothing);
      await tester.tap(find.byTooltip('返回'));
      expect(backs, 1);

      if (PlatformInfo.isDesktop) {
        // 禁用的 IconButton 不挂 Tooltip 子树，用图标找它更稳。
        final Finder button = find.ancestor(
          of: find.byIcon(Icons.fullscreen),
          matching: find.byType(IconButton),
        );
        expect(button, findsOneWidget);
        expect(
          tester.widget<IconButton>(button).onPressed,
          isNull,
          reason: '锁定时不能改窗口形态',
        );
      }
    });

    testWidgets('副标题为空时只留一行标题', (WidgetTester tester) async {
      await tester.pumpWidget(host(topBar(subtitle: '')));
      expect(find.byType(Text), findsOneWidget);
    });
  });

  group('中央键', () {
    testWidgets('缓冲 / 起播中显示转圈，不显示播放键', (WidgetTester tester) async {
      for (final bool buffering in <bool>[true, false]) {
        await tester.pumpWidget(host(PlayerCenterButton(
          buffering: buffering,
          starting: !buffering,
          playing: true,
          onTap: () {},
        )));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.pause), findsNothing);
      }
    });

    testWidgets('播放中显示暂停，暂停时显示播放，点击回调', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(host(PlayerCenterButton(
        buffering: false,
        starting: false,
        playing: false,
        onTap: () => taps++,
      )));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      expect(taps, 1);

      await tester.pumpWidget(host(PlayerCenterButton(
        buffering: false,
        starting: false,
        playing: true,
        onTap: () => taps++,
      )));
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });
  });

  testWidgets('锁定键的图标 / 提示随状态翻转且可点', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(host(PlayerLockButton(
      locked: false,
      onTap: () => taps++,
    )));
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    expect(find.byTooltip('锁定播放控件'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.lock_open));
    expect(taps, 1);

    await tester.pumpWidget(host(PlayerLockButton(
      locked: true,
      onTap: () => taps++,
    )));
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.byTooltip('已锁定播放控件，点击解锁'), findsOneWidget);
  });

  group('降级横幅', () {
    testWidgets('没有提示时完全不渲染', (WidgetTester tester) async {
      await tester.pumpWidget(host(const PlayerFallbackBanner()));
      expect(find.byType(Text), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('正在尝试时是转圈，切换完成是箭头图标', (WidgetTester tester) async {
      await tester.pumpWidget(host(
        const PlayerFallbackBanner(trying: '正在尝试备用地址…'),
      ));
      expect(find.text('正在尝试备用地址…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsNothing);

      await tester.pumpWidget(host(
        const PlayerFallbackBanner(notice: '已切换到 备用站'),
      ));
      expect(find.text('已切换到 备用站'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('尝试中优先于完成通知', (WidgetTester tester) async {
      await tester.pumpWidget(host(const PlayerFallbackBanner(
        trying: '尝试中',
        notice: '已切换',
      )));
      expect(find.text('尝试中'), findsOneWidget);
      expect(find.text('已切换'), findsNothing);
    });
  });

  testWidgets('错误面板显示原因、限 4 行且能重试', (WidgetTester tester) async {
    int retries = 0;
    final String message = List<String>.filled(8, '连接超时').join('\n');
    await tester.pumpWidget(host(PlayerErrorPanel(
      message: message,
      onRetry: () => retries++,
    )));

    expect(find.text('播放失败'), findsOneWidget);
    final Text body = tester.widget<Text>(find.text(message));
    expect(body.maxLines, 4);
    expect(body.overflow, TextOverflow.ellipsis);

    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    expect(retries, 1);
  });

  testWidgets('药丸可点、信息标签不可点、玻璃盒透传尺寸', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(host(Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PlayerPillButton(label: '1.5x', onTap: () => taps++),
        const PlayerInfoChip(label: '1080P'),
        const PlayerGlassBox(width: 180, child: Text('亮度 80%')),
      ],
    )));

    expect(find.text('1.5x'), findsOneWidget);
    expect(find.text('1080P'), findsOneWidget);
    expect(find.text('亮度 80%'), findsOneWidget);
    await tester.tap(find.text('1.5x'));
    expect(taps, 1);

    // 只读标签下面不该挂 InkWell：一个点不动的按钮比一段普通文字更困惑。
    expect(
      find.ancestor(
        of: find.text('1080P'),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.ancestor(
            of: find.text('亮度 80%'),
            matching: find.byType(Container),
          ))
          .width,
      180,
    );
  });
}
