import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_language.dart';
import '../providers/moderation_provider.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key, required this.currentUserId});

  final String currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedUsersDetailedProvider(currentUserId));

    return Scaffold(
      appBar: AppBar(title: Text(tr('Utilisateurs bloqués'))),
      body: currentUserId.isEmpty
          ? Center(child: Text(tr('Connectez-vous pour voir cette liste.')))
          : blockedAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Erreur : $error')),
              data: (blocked) {
                if (blocked.isEmpty) {
                  return Center(
                    child: Text(
                      tr("Vous n'avez bloqué personne pour le moment."),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: blocked.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = blocked[index];
                    final name = user['userName'] as String? ?? 'Utilisateur';
                    final initial = name.isEmpty
                        ? '?'
                        : name.characters.first.toUpperCase();

                    return ListTile(
                      leading: CircleAvatar(child: Text(initial)),
                      title: Text(name),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          await ref
                              .read(moderationServiceProvider)
                              .unblockUser(
                                currentUserId: currentUserId,
                                blockedUserId: user['id'] as String,
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(tr('Utilisateur débloqué')),
                              ),
                            );
                          }
                        },
                        child: Text(tr('Débloquer')),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
