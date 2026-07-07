import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../favoris/providers/favoris_provider.dart';
import '../../../models/annonce.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/fullscreen_image_viewer.dart';

class AnnonceCard extends ConsumerWidget {
  const AnnonceCard({super.key, required this.annonce});

  final Annonce annonce;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    final userId = currentUser?.id ?? '';
    final canFavorite = currentUser?.isBuyer == true;
    final favoris = canFavorite ? ref.watch(favorisProvider(userId)) : const [];
    final isFavorite = favoris.any((favori) => favori.annonceId == annonce.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: annonce.imageUrls.isEmpty
                ? null
                : () => FullscreenImageViewer.open(
                    context,
                    imageUrls: annonce.imageUrls,
                  ),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: annonce.imageUrls.isEmpty
                  ? Container(
                      color: Colors.grey[850],
                      child: const Center(
                        child: Icon(
                          Icons.image_outlined,
                          color: Colors.grey,
                          size: 48,
                        ),
                      ),
                    )
                  : Image.network(
                      annonce.imageUrls.first,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: Colors.grey[850],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[850],
                        child: const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.grey,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          ListTile(
            title: Text(annonce.title),
            subtitle: Text(
              '${annonce.price.toStringAsFixed(0)} ${annonce.currency}\n${annonce.category}',
            ),
            isThreeLine: true,
            trailing: canFavorite
                ? IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                    ),
                    onPressed: userId.isEmpty
                        ? null
                        : () => ref
                              .read(favorisProvider(userId).notifier)
                              .toggleFavori(annonce.id),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
