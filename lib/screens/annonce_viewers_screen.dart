import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../l10n/app_language.dart';
import '../models/annonce.dart';
import '../providers/annonce_viewers_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/user_display.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../widgets/occasion_image.dart';

/// « Vues de l'annonce » (vendeur uniquement) : qui a ouvert l'annonce, la
/// visite la plus récente en haut, avec un bouton pour lui écrire.
class AnnonceViewersScreen extends ConsumerWidget {
  const AnnonceViewersScreen({super.key, required this.annonce});

  final Annonce annonce;

  void _write(BuildContext context, WidgetRef ref, AnnonceViewer viewer) {
    final me = ref.read(authNotifierProvider).currentUser;
    if (me == null) return;
    // Le visiteur est l'acheteur potentiel de CETTE annonce, le vendeur
    // (moi) reste vendeur : même conversation que s'il m'avait écrit
    // depuis l'annonce.
    context.push(
      '/open-chat',
      extra: {
        'buyerId': viewer.uid,
        'buyerName': viewer.name,
        'buyerProfileImageUrl': viewer.profileImageUrl,
        'sellerId': me.id,
        'sellerName': me.name,
        'sellerProfileImageUrl': me.profileImageUrl,
        'listingId': annonce.id,
        'listingTitle': annonce.title,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewersAsync = ref.watch(annonceViewersProvider(annonce.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("Vues de l'annonce")),
        shape: const Border(
          bottom: BorderSide(color: AppColors.outline, width: 0.5),
        ),
      ),
      body: viewersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Impossible de charger les vues pour le moment.'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (viewers) {
          if (viewers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(
                    "Personne n'a encore ouvert cette annonce. Les "
                    'visiteurs apparaîtront ici.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: viewers.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    '${annonce.title} · ${viewers.length} '
                    '${viewers.length > 1 ? tr('personnes') : tr('personne')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                );
              }
              final viewer = viewers[index - 1];
              return AppearOnce(
                key: ValueKey(viewer.uid),
                order: index,
                child: _ViewerRow(
                  viewer: viewer,
                  onWrite: () => _write(context, ref, viewer),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// « il y a 5 min », « il y a 3 h », « hier », sinon la date.
String formatViewedAgo(DateTime? at, {DateTime? now}) {
  if (at == null) return tr('à l’instant');
  final current = now ?? DateTime.now();
  String ago(String amount) =>
      AppLanguage.isEnglish ? '$amount ago' : 'il y a $amount';
  final diff = current.difference(at);
  if (diff.inMinutes < 1) return tr('à l’instant');
  if (diff.inMinutes < 60) return ago('${diff.inMinutes} min');
  if (diff.inHours < 24) return ago('${diff.inHours} h');
  final days = DateTime(
    current.year,
    current.month,
    current.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days == 1) return tr('hier');
  if (days < 7) return ago('$days ${tr('jours')}');
  return DateFormat('dd/MM/yy').format(at);
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({required this.viewer, required this.onWrite});

  final AnnonceViewer viewer;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final photo = viewer.profileImageUrl;
    final initial = viewer.name.characters.first.toUpperCase();
    final when = formatViewedAgo(viewer.viewedAt);
    final subtitle = viewer.visits > 1
        ? '${tr('Vue')} $when · ${viewer.visits} ${tr('visites')}'
        : '${tr('Vue')} $when';
    return InkWell(
      onTap: onWrite,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            GestureDetector(
              onTap: photo == null
                  ? null
                  : () =>
                        FullscreenImageViewer.open(context, imageUrls: [photo]),
              child: ClipOval(
                child: photo == null
                    ? CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.14,
                        ),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : OccasionImage.thumbnail(
                        photo,
                        width: 52,
                        height: 52,
                        cacheWidth: 104,
                        cacheHeight: 104,
                        semanticsLabel: 'Photo de profil de ${viewer.name}',
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayNameWithTag(viewer.name, viewer.uid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: onWrite,
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size(0, 38),
              ),
              child: Text(tr('Écrire')),
            ),
          ],
        ),
      ),
    );
  }
}
