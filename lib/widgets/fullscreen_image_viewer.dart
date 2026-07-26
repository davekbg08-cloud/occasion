import 'package:flutter/material.dart';

import 'occasion_image.dart';

/// Aperçu plein écran d'une ou plusieurs photos d'annonce, avec zoom
/// (pincer/zoomer), défilement entre les images, points + compteur "1/5"
/// quand il y a plusieurs photos.
class FullscreenImageViewer extends StatefulWidget {
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
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    final hasMultiple = urls.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: hasMultiple
            ? Text(
                '${_index + 1}/${urls.length}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : null,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: PageController(initialPage: widget.initialIndex),
            itemCount: urls.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: OccasionImage.detail(
                    urls[index],
                    key: ValueKey(urls[index]),
                  ),
                ),
              );
            },
          ),
          if (hasMultiple)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(urls.length, (i) {
                  final isActive = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 8 : 6,
                    height: isActive ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isActive ? Colors.white : Colors.white70)
                          .withValues(alpha: isActive ? 0.95 : 0.6),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
