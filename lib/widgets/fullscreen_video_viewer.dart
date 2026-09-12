import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Lecture plein écran d'une vidéo (photo/vidéo de chat, statut...) — même
/// pattern de contrôleur que `status_feed_screen.dart` (`VideoPlayerController`,
/// `BoxFit.contain` sur fond noir, retry en cas d'échec), avec des contrôles
/// simples play/pause au tap.
class FullscreenVideoViewer extends StatefulWidget {
  const FullscreenVideoViewer({super.key, required this.videoUrl});

  final String videoUrl;

  static Future<void> open(BuildContext context, {required String videoUrl}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullscreenVideoViewer(videoUrl: videoUrl),
      ),
    );
  }

  @override
  State<FullscreenVideoViewer> createState() => _FullscreenVideoViewerState();
}

class _FullscreenVideoViewerState extends State<FullscreenVideoViewer> {
  VideoPlayerController? _controller;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    _error = false;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    _controller = controller;
    controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          controller.play();
        })
        .catchError((Object error) {
          if (!mounted) return;
          setState(() => _error = true);
        });
  }

  void _retry() {
    _controller?.dispose();
    _controller = null;
    setState(() => _error = false);
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Impossible de lire cette vidéo.',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
            ),
            child: const Text('Réessayer'),
          ),
        ],
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return GestureDetector(
      onTap: () => setState(() {
        controller.value.isPlaying ? controller.pause() : controller.play();
      }),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            if (!controller.value.isPlaying)
              const Icon(Icons.play_arrow, color: Colors.white70, size: 64),
          ],
        ),
      ),
    );
  }
}
