import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Widget image unique pour toute l'app : gère les URL null/vides, les
/// erreurs réseau, un placeholder de chargement, et met en cache via
/// [CachedNetworkImage] (au lieu du `Image.network` brut utilisé jusqu'ici à
/// plusieurs endroits, sans cache ni gestion d'erreur uniforme).
///
/// Deux usages typiques :
/// - [OccasionImage.thumbnail] : ratio fixe, `BoxFit.cover`, pour les listes
///   (cartes produit/annonce).
/// - [OccasionImage.detail] : `BoxFit.contain` sur fond noir, pour l'aperçu
///   plein écran/détail, où l'image entière doit rester visible.
class OccasionImage extends StatelessWidget {
  const OccasionImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.backgroundColor,
    this.cacheWidth,
    this.cacheHeight,
    this.semanticsLabel,
  });

  factory OccasionImage.thumbnail(
    String? url, {
    Key? key,
    double? width,
    double? height,
    BorderRadius? borderRadius,
    int? cacheWidth,
    int? cacheHeight,
    String? semanticsLabel,
  }) {
    return OccasionImage(
      key: key,
      url: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      borderRadius: borderRadius,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      semanticsLabel: semanticsLabel,
    );
  }

  factory OccasionImage.detail(
    String? url, {
    Key? key,
    double? width,
    double? height,
    String? semanticsLabel,
  }) {
    return OccasionImage(
      key: key,
      url: url,
      width: width,
      height: height,
      fit: BoxFit.contain,
      backgroundColor: Colors.black,
      semanticsLabel: semanticsLabel,
    );
  }

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final int? cacheWidth;
  final int? cacheHeight;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final trimmed = url?.trim();
    final isMissing = trimmed == null || trimmed.isEmpty;

    Widget child = isMissing
        ? _placeholder(icon: Icons.image_outlined)
        : CachedNetworkImage(
            imageUrl: trimmed,
            width: width,
            height: height,
            fit: fit,
            memCacheWidth: cacheWidth,
            memCacheHeight: cacheHeight,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (context, url) => _placeholder(loading: true),
            errorWidget: (context, url, error) =>
                _placeholder(icon: Icons.broken_image_outlined),
          );

    if (backgroundColor != null) {
      child = Container(
        width: width,
        height: height,
        color: backgroundColor,
        child: child,
      );
    }

    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }

    return Semantics(
      image: true,
      label: semanticsLabel,
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _placeholder({
    IconData icon = Icons.image_outlined,
    bool loading = false,
  }) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: Center(
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 40, color: Colors.grey[600]),
      ),
    );
  }
}
