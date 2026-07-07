import 'package:flutter/material.dart';

/// Aperçu plein écran d'une ou plusieurs photos d'annonce, avec zoom
/// (pincer/zoomer) et défilement entre les images.
class FullscreenImageViewer extends StatelessWidget {
  const FullscreenImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final int initialIndex;

  static Future<void> open(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    if (imageUrls.isEmpty) return Future.value();
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullscreenImageViewer(
          imageUrls: imageUrls,
          initialIndex: initialIndex.clamp(0, imageUrls.length - 1),
        ),
      ),
    );
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
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: imageUrls.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.network(
                imageUrls[index],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const CircularProgressIndicator(color: Colors.white);
                },
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
