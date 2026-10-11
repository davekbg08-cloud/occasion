import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_language.dart';
import '../models/report.dart';
import '../providers/auth_provider.dart';
import '../providers/directory_provider.dart';
import '../providers/moderation_provider.dart';
import '../theme/app_theme.dart';
import '../utils/user_display.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../widgets/occasion_image.dart';
import '../widgets/report_block_sheet.dart';
import '../widgets/tappable_card.dart';

/// Répertoire de tous les utilisateurs (acheteurs et vendeurs confondus) :
/// nom, photo, rôle et badge vérifié — jamais de numéro de téléphone.
/// Tapoter une fiche ouvre la conversation existante avec cette personne,
/// ou en crée une nouvelle. Un utilisateur bloqué disparaît complètement de
/// la liste (même filtre que la liste de conversations/le fil de statuts).
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChatWith(UserModel me, UserModel target) {
    // Convention déjà en place ailleurs (statuts, fiche annonce) : celui
    // qui initie le contact devient "buyerId" de CETTE conversation, quel
    // que soit son rôle réel — voir le commentaire dans
    // `_OpenChatScreen._openChat` (lib/main.dart). Aucune annonce/aucun
    // statut à l'origine ici : pas de listingId.
    context.push(
      '/open-chat',
      extra: {
        'buyerId': me.id,
        'buyerName': me.name,
        'buyerProfileImageUrl': me.profileImageUrl,
        'sellerId': target.id,
        'sellerName': target.name,
        'sellerProfileImageUrl': target.profileImageUrl,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authNotifierProvider).currentUser;
    final directoryAsync = ref.watch(directoryProvider);
    final blockedIds = me == null
        ? const <String>{}
        : ref
              .watch(blockedUserIdsProvider(me.id))
              .maybeWhen(data: (ids) => ids, orElse: () => const <String>{});

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: Text(
          tr('Répertoire'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: tr('Rechercher un nom...'),
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: directoryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(
                  tr('Impossible de charger le répertoire pour le moment.'),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              data: (all) {
                if (me == null) return const SizedBox.shrink();
                final users = filterDirectory(
                  all,
                  selfId: me.id,
                  blockedUserIds: blockedIds,
                  query: _query,
                );
                if (users.isEmpty) {
                  return Center(
                    child: Text(
                      tr('Aucun utilisateur trouvé.'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _DirectoryTile(
                      user: user,
                      currentUserId: me.id,
                      onOpen: () => _openChatWith(me, user),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({
    required this.user,
    required this.currentUserId,
    required this.onOpen,
  });

  final UserModel user;
  final String currentUserId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final initial = user.name.isEmpty
        ? '?'
        : user.name.characters.first.toUpperCase();

    final hasPhoto =
        user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty;

    // Carte distincte et visiblement cliquable (fond, bordure, bouton
    // « Écrire ») : tapoter n'importe où ouvre la conversation.
    return TappableCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
      child: Row(
        children: [
          // Distinct du tap sur le reste de la fiche (onOpen, ouvre la
          // conversation) : tapoter précisément la photo l'agrandit plutôt,
          // même geste que sur un profil (voir `profile_screen.dart`/
          // `seller_public_profile_screen.dart`).
          GestureDetector(
            onTap: hasPhoto
                ? () => FullscreenImageViewer.open(
                    context,
                    imageUrls: [user.profileImageUrl!],
                  )
                : null,
            child: ClipOval(
              child: !hasPhoto
                  ? CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.14,
                      ),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : OccasionImage.thumbnail(
                      user.profileImageUrl,
                      width: 48,
                      height: 48,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayNameWithTag(user.name, user.id),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user.isVerifiedSeller) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.verified,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  user.isSeller ? tr('Vendeur') : tr('Acheteur'),
                  style: TextStyle(
                    fontSize: 13,
                    color: user.isSeller
                        ? AppColors.price
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Rend l'action explicite : la fiche sert à écrire à la personne.
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    tr('Écrire'),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: tr('Bloquer ou signaler'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            onPressed: () => showReportOrBlockSheet(
              context,
              currentUserId: currentUserId,
              targetUserId: user.id,
              targetUserName: user.name,
              targetType: ReportTargetType.user,
            ),
          ),
        ],
      ),
    );
  }
}
