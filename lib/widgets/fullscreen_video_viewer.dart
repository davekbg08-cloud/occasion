import '../l10n/app_language.dart';
import 'dart:async';

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
  bool _isInitializing = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Au-delà de ce délai, l'initialisation ne doit plus jamais laisser
  /// l'utilisateur face à un spinner indéfini (ex. connexion instable en
  /// plein streaming) — bascule sur l'état d'échec avec "Réessayer" plutôt
  /// que d'attendre sans fin une réponse qui ne viendra peut-être jamais.
  ///
  /// Implémenté avec un `Timer` brut plutôt que `Future.timeout()` : voir
  /// le commentaire équivalent dans `status_feed_screen.dart` — ce
  /// mécanisme force directement `setState` sans dépendre d'une chaîne
  /// timeout → catch → dispose() qui pourrait échouer silencieusement.
  static const _initTimeout = Duration(seconds: 15);

  Future<void> _init() async {
    if (_isInitializing) return;
    _isInitializing = true;
    _error = false;

    final url = widget.videoUrl.trim();
    if (!url.startsWith('http')) {
      if (mounted) setState(() => _error = true);
      _isInitializing = false;
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;

    var settled = false;
    _watchdog?.cancel();
    _watchdog = Timer(_initTimeout, () {
      if (settled) return;
      settled = true;
      _isInitializing = false;
      if (mounted) setState(() => _error = true);
    });

    try {
      await controller.initialize();
      _watchdog?.cancel();
      if (settled) {
        _safeDispose(controller);
        return;
      }
      settled = true;

      if (!mounted) {
        _safeDispose(controller);
        return;
      }
      setState(() {});
      controller.play();
    } catch (_) {
      _watchdog?.cancel();
      if (!settled) {
        settled = true;
        if (mounted) setState(() => _error = true);
      }
      _safeDispose(controller);
      _controller = null;
    } finally {
      _isInitializing = false;
    }
  }

  void _safeDispose(VideoPlayerController controller) {
    try {
      controller.dispose();
    } catch (_) {}
  }

  void _retry() {
    _watchdog?.cancel();
    final previous = _controller;
    if (previous != null) _safeDispose(previous);
    _controller = null;
    setState(() => _error = false);
    _init();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
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
          Text(
            tr('Impossible de lire cette vidéo.'),
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
            ),
            child: Text(tr('Réessayer')),
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
