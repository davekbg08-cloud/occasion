import 'package:flutter/material.dart';

import 'fullscreen_image_viewer.dart';
import 'occasion_image.dart';

/// Carrousel de miniatures avec balayage, indicateur de points et compteur
/// "1/5" — remplace l'affichage `imageUrls.first` utilisé jusqu'ici dans les
/// cartes produit/annonce (qui ignorait complètement les photos suivantes).
class PhotoCarousel extends StatefulWidget {
  const PhotoCarousel({
    super.key,
    required this.imageUrls,
    this.aspectRatio = 4 / 3,
    this.borderRadius,
  });

  final List<String> imageUrls;
  final double aspectRatio;
  final BorderRadius? borderRadius;

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  late final PageController _controller = PageController(viewportFraction: 1);
  int _index = 0;
  bool _hasSwiped = false;

  @override
  void didUpdateWidget(covariant PhotoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls != widget.imageUrls) {
      _index = 0;
      _hasSwiped = false;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openFullscreen(int index) {
    if (widget.imageUrls.isEmpty) return;
    FullscreenImageViewer.open(
      context,
      imageUrls: widget.imageUrls,
      initialIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;

    Widget content;
    if (urls.isEmpty) {
      content = const OccasionImage(url: null);
    } else if (urls.length == 1) {
      content = GestureDetector(
        onTap: () => _openFullscreen(0),
        child: OccasionImage.thumbnail(
          urls.first,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            key: ValueKey(urls.join('|')),
            controller: _controller,
            itemCount: urls.length,
            onPageChanged: (index) => setState(() {
              _index = index;
              _hasSwiped = true;
            }),
            itemBuilder: (context, index) => GestureDetector(
              onTap: () => _openFullscreen(index),
              child: OccasionImage.thumbnail(
                urls[index],
                key: ValueKey(urls[index]),
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _CounterBadge(current: _index + 1, total: urls.length),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: _DotsIndicator(count: urls.length, index: _index),
          ),
          if (!_hasSwiped)
            const Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: _SwipeHint(),
            ),
        ],
      );
    }

    Widget result = AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ClipRect(child: content),
    );
    final radius = widget.borderRadius;
    if (radius != null) {
      result = ClipRRect(borderRadius: radius, child: result);
    }
    return result;
  }
}

class _CounterBadge extends StatelessWidget {
  const _CounterBadge({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$current/$total',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 8 : 6,
          height: isActive ? 8 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isActive ? Colors.white : Colors.white70).withValues(
              alpha: isActive ? 0.95 : 0.6,
            ),
          ),
        );
      }),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swipe, size: 13, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Balayez pour voir les autres photos',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
