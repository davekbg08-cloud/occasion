import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../favoris/providers/favoris_provider.dart';
import '../../../models/annonce.dart';
import '../../../providers/auth_provider.dart';

class AnnonceCard extends ConsumerWidget {
  const AnnonceCard({super.key, required this.annonce});

  final Annonce annonce;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    final userId = currentUser?.id ?? '';
    final favoris = ref.watch(favorisProvider(userId));
    final isFavorite = favoris.any((favori) => favori.annonceId == annonce.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListTile(
        leading: annonce.imageUrls.isEmpty
            ? const Icon(Icons.image_outlined)
            : Image.network(
                annonce.imageUrls.first,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
        title: Text(annonce.title),
        subtitle: Text(
          '${annonce.price.toStringAsFixed(0)} ${annonce.currency}\n${annonce.category}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
          onPressed: userId.isEmpty
              ? null
              : () => ref
                  .read(favorisProvider(userId).notifier)
                  .toggleFavori(annonce.id),
        ),
      ),
    );
  }
}
