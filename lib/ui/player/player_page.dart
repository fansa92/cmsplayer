import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/logger.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/play_task.dart';
import '../../state/app_state.dart';
import '../../state/history_store.dart';
import 'player_controls.dart';
import 'player_controller.dart';

/// 全屏播放页。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.task});

  final PlayTask task;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final PlayerController _controller;
  bool _wakelockOn = false;

  @override
  void initState() {
    super.initState();
    _controller = PlayerController(
      task: widget.task,
      app: context.read<AppState>(),
      history: context.read<HistoryStore>(),
    );
    _enterPlaybackUi();
  }

  Future<void> _enterPlaybackUi() async {
    if (!PlatformInfo.isMobile) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
    } on Object catch (e) {
      AppLog.d('PlayerPage', 'enter playback UI failed: $e');
    }
    if (!mounted) return;
    try {
      if (context.read<AppState>().keepScreenOn && !_wakelockOn) {
        await WakelockPlus.enable();
        _wakelockOn = true;
      }
    } on Object catch (e) {
      AppLog.d('PlayerPage', 'wakelock failed: $e');
    }
  }

  Future<void> _exitPlaybackUi() async {
    if (!PlatformInfo.isMobile) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (_wakelockOn) {
        _wakelockOn = false;
        await WakelockPlus.disable();
      }
    } on Object catch (e) {
      AppLog.d('PlayerPage', 'exit playback UI failed: $e');
    }
  }

  @override
  void dispose() {
    // 先恢复系统 UI，再释放播放器（顺序反过来会在部分机型上闪一下状态栏）。
    _exitPlaybackUi();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ListenableBuilder(
            listenable: _controller,
            builder: (BuildContext context, _) {
              return Video(
                controller: _controller.videoController,
                controls: NoVideoControls,
                fit: _controller.fit,
                wakelock: false,
                pauseUponEnteringBackgroundMode: false,
                resumeUponEnteringForegroundMode: true,
              );
            },
          ),
          PlayerControls(
            controller: _controller,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
