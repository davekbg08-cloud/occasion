import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_language.dart';
import '../models/status.dart';
import '../providers/auth_provider.dart';
import '../services/status_service.dart';
import '../theme/app_theme.dart';
import '../widgets/occasion_image.dart';

/// Historique complet des statuts d'un vendeur — y compris ceux déjà
/// expirés du fil public (72 h, voir `StatusService.feed`) : le fil est
/// volontairement temporaire, mais rien n'est jamais supprimé, ce que
/// cet écran rend visible/consultable (répond à "où se trouve
/// l'historique une fois le statut sorti du fil ?").
class MyStatusesScreen extends ConsumerWidget {
  const MyStatusesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authNotifierProvider).currentUser?.id ?? '';
    final service = StatusService();

    return Scaffold(
      appBar: AppBar(title: Text(tr('Mes statuts'))),
      body: StreamBuilder<List<Status>>(
        stream: service.sellerStatuses(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                tr('Impossible de charger tes statuts pour le moment.'),
              ),
            );
          }
          final statuses = snapshot.data ?? const [];
          if (statuses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr(
                    "Aucun statut publié pour l'instant. Tes statuts restent "
                    "visibles ici même après avoir disparu du fil public "
                    "(72 h).",
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.7,
            ),
            itemCount: statuses.length,
            itemBuilder: (context, index) {
              final status = statuses[index];
              final isExpired =
                  DateTime.now().difference(status.createdAt) >
                  StatusService.feedTtl;
              return _StatusTile(
                status: status,
                isExpired: isExpired,
                onDelete: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(tr('Supprimer ce statut ?')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(tr('Annuler')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(tr('Supprimer')),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    await service.deleteStatus(status.id);
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(tr('Impossible de supprimer ce statut.')),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.status,
    required this.isExpired,
    required this.onDelete,
  });

  final Status status;
  final bool isExpired;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          OccasionImage.thumbnail(status.mediaUrl),
          if (status.type == StatusType.video)
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
                size: 32,
              ),
            ),
          Positioned(
            left: 4,
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isExpired ? tr('Expiré') : tr('Dans le fil'),
                style: TextStyle(
                  color: isExpired ? Colors.grey[300] : AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: IconButton(
              tooltip: tr('Supprimer'),
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: onDelete,
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            right: 6,
            child: Text(
              DateFormat('dd/MM/yyyy HH:mm').format(status.createdAt),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
