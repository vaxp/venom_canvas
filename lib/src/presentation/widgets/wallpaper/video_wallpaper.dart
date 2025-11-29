import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoWallpaper extends StatefulWidget {
  final String videoPath;
  const VideoWallpaper({super.key, required this.videoPath});

  @override
  State<VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends State<VideoWallpaper>
    with SingleTickerProviderStateMixin {
  Player? player;
  VideoController? controller;
  StreamSubscription<bool>? _completedSubscription;
  bool isRestarting = false;
  late AnimationController fadeController;

  @override
  void initState() {
    super.initState();
    fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..value = 1.0;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 1024 * 1024, // 1MB buffer for smoother playback
        ),
      );
      controller = VideoController(player!);

      await player!.setVolume(0);
      await player!.setPlaylistMode(PlaylistMode.none);

      await player!.open(Media(widget.videoPath), play: true);

      // restart on completion from 0.5s instead of full reload
      _completedSubscription = player!.stream.completed.listen((
        bool isCompleted,
      ) async {
        if (isCompleted && mounted && !isRestarting) {
          await _restartSmooth();
        }
      });

      setState(() {});
    } catch (e) {
      debugPrint('VideoWallpaper init error: $e');
    }
  }

  Future<void> _restartSmooth() async {
    if (player == null || isRestarting) return;
    isRestarting = true;

    try {
      // Smooth fade out then seek then fade in
      await fadeController.reverse();
      await player!.pause();
      await player!.seek(const Duration(milliseconds: 100)); // ثانيتك 0.5
      await player!.play();
      await fadeController.forward();
    } catch (e) {
      await _hardRestart();
    }

    isRestarting = false;
  }

  Future<void> _hardRestart() async {
    try {
      await player?.dispose();
      player = null;
      controller = null;
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) await _initPlayer();
    } catch (_) {}
  }

  @override
  void dispose() {
    _completedSubscription?.cancel();
    player?.dispose();
    fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (player == null || controller == null) {
      return const SizedBox.expand();
    }

    return FadeTransition(
      opacity: fadeController,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Video(
              controller: controller!,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
          ),
        ),
      ),
    );
  }
}
