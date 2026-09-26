import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/report.dart';
import '../models/status.dart';
import '../providers/auth_provider.dart';
import '../providers/moderation_provider.dart';
import '../providers/status_provider.dart';
import '../services/seller_subscription_guard.dart';
import '../widgets/occasion_image.dart';
import '../widgets/report_block_sheet.dart';

class StatusFeedScreen extends ConsumerStatefulWidget {
  const StatusFeedScreen({
    super.key,
    this.isVisible = true,
    this.initialSellerId,
  });

  /// L'onglet Feed est-il celui actuellement affiché ? `BuyerNav` garde cet
  /// écran monté en permanence dans un `IndexedStack` en changeant
  /// d'onglet (Profil, Messages...) — sans ce signal, la vidéo en cours
  /// continue de jouer (son compris) même invisible, faute de tout autre
  /// mécanisme de cycle de vie réagissant à un changement d'onglet.
  final bool isVisible;

  /// Vendeur dont la bulle « stories » a été touchée dans `StatusStrip` —
  /// ouvre le fil directement sur son premier statut visible au lieu de
  /// toujours démarrer au tout premier statut du fil, quel que soit le
  /// vendeur réellement choisi.
  final String? initialSellerId;

  @override
  ConsumerState<StatusFeedScreen> createState() => _StatusFeedScreenState();
}

class _StatusFeedScreenState extends ConsumerState<StatusFeedScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _didInitialSellerJump = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(statusNotifierProvider.notifier).loadFeed();
      final userId = ref.read(authNotifierProvider).currentUser?.id;
      if (userId != null) {
        ref.read(statusNotifierProvider.notifier).loadLikedStatuses(userId);
        ref.read(statusNotifierProvider.notifier).loadViewedStatuses(userId);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openPublisher() {
    final canPublish = checkSellerSubscription(context, ref);
    if (canPublish) {
      context.push('/add-status');
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusState = ref.watch(statusNotifierProvider);
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    final isSeller = currentUser?.isSeller ?? false;
    final blockedIds = currentUser == null
        ? const <String>{}
        : ref
              .watch(blockedUserIdsProvider(currentUser.id))
              .maybeWhen(data: (ids) => ids, orElse: () => const <String>{});
    final visibleStatuses = statusState.statuses
        .where((status) => !blockedIds.contains(status.sellerId))
        .toList();

    if (!_didInitialSellerJump &&
        widget.initialSellerId != null &&
        visibleStatuses.isNotEmpty) {
      _didInitialSellerJump = true;
      final index = visibleStatuses.indexWhere(
        (status) => status.sellerId == widget.initialSellerId,
      );
      if (index != -1) {
        // Pris en compte dès ce build (pas de setState) : la première page
        // active est la bonne sans flash de la page 0 au premier frame.
        // Le PageController lui-même ne peut être positionné qu'une fois
        // attaché au PageView, donc après ce build (jumpToPage sans saut
        // visible, page jamais réellement affichée à l'index 0).
        _currentPage = index;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageController.hasClients) return;
          _pageController.jumpToPage(index);
        });
      }
    }

    // Marque la page actuellement affichée comme vue (pilote la couleur
    // de sa bulle "stories" sur l'accueil) — `markViewed` est lui-même
    // idempotent, donc rien n'empêche de la réappeler à chaque build tant
    // qu'elle n'est pas encore dans `viewedIds` (devient un no-op dès
    // qu'elle y est, sur le build suivant).
    if (visibleStatuses.isNotEmpty) {
      final activeIndex = _currentPage.clamp(0, visibleStatuses.length - 1);
      final activeStatus = visibleStatuses[activeIndex];
      final userId = currentUser?.id;
      if (userId != null && !statusState.isViewed(activeStatus.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(statusNotifierProvider.notifier)
              .markViewed(activeStatus.id, userId);
        });
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: statusState.isLoading && visibleStatuses.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : statusState.error != null && visibleStatuses.isEmpty
          ? const _ErrorFeed()
          : visibleStatuses.isEmpty
          ? _EmptyFeed(isSeller: isSeller, onPublish: _openPublisher)
          : Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: visibleStatuses.length,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                    // Pagine le feed : on charge la page suivante quand
                    // l'utilisateur approche de la fin des statuts déjà
                    // chargés, plutôt que de tout charger d'un coup.
                    if (index >= visibleStatuses.length - 3) {
                      ref.read(statusNotifierProvider.notifier).loadMore();
                    }
                  },
                  itemBuilder: (context, index) {
                    final status = visibleStatuses[index];
                    return _StatusPage(
                      key: ValueKey(status.id),
                      status: status,
                      isActive: index == _currentPage && widget.isVisible,
                      currentUserId: currentUser?.id ?? '',
                    );
                  },
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        // Absent jusqu'ici : ce fil plein écran n'offrait
                        // aucun moyen visible de le quitter (contrairement
                        // à fullscreen_image_viewer.dart/
                        // fullscreen_video_viewer.dart, qui ont tous deux
                        // une AppBar avec sa flèche retour automatique) —
                        // seul le geste système "retour" fonctionnait,
                        // sans aucun indice à l'écran.
                        IconButton(
                          onPressed: () => context.canPop()
                              ? context.pop()
                              : context.go('/home'),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'Découvrir',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 8)],
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => context.push('/profile'),
                          icon: const Icon(
                            Icons.person_outline,
                            color: Colors.white,
                          ),
                        ),
                        if (isSeller)
                          FilledButton.icon(
                            onPressed: _openPublisher,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Publier'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusPage extends StatefulWidget {
  const _StatusPage({
    super.key,
    required this.status,
    required this.isActive,
    required this.currentUserId,
  });

  final Status status;
  final bool isActive;
  final String currentUserId;

  @override
  State<_StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<_StatusPage> {
  VideoPlayerController? _video;
  bool _videoError = false;
  bool _isInitializing = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    if (widget.status.type == StatusType.video) {
      _initVideo();
    }
  }

  /// Au-delà de ce délai, l'initialisation ne doit plus jamais laisser
  /// l'utilisateur face à un spinner indéfini (ex. connexion instable en
  /// plein streaming) — bascule sur l'état d'échec avec "Réessayer" plutôt
  /// que d'attendre sans fin une réponse qui ne viendra peut-être jamais.
  ///
  /// Implémenté avec un `Timer` brut plutôt que `Future.timeout()` : ce
  /// dernier chaîne timeout → catch → dispose() → setState, plusieurs
  /// maillons où un problème d'implémentation du plugin vidéo pourrait
  /// empêcher la mise à jour d'état de se produire. Un `Timer` indépendant
  /// qui force directement `setState` ne dépend d'aucun de ces maillons.
  static const _initTimeout = Duration(seconds: 15);

  Future<void> _initVideo() async {
    if (_isInitializing) return;
    _isInitializing = true;
    _videoError = false;

    final url = widget.status.mediaUrl.trim();
    if (!url.startsWith('http')) {
      if (mounted) setState(() => _videoError = true);
      _isInitializing = false;
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = controller;

    var settled = false;
    _watchdog?.cancel();
    _watchdog = Timer(_initTimeout, () {
      if (settled) return;
      settled = true;
      _isInitializing = false;
      if (mounted) setState(() => _videoError = true);
    });

    try {
      await controller.initialize();
      _watchdog?.cancel();
      if (settled) {
        // Le watchdog a déjà déclenché l'échec pendant l'attente : ne pas
        // afficher une vidéo "réussie" par-dessus l'écran d'erreur déjà
        // affiché.
        _safeDispose(controller);
        return;
      }
      settled = true;

      if (!mounted) {
        _safeDispose(controller);
        return;
      }
      setState(() {});
      controller.setLooping(true);
      if (widget.isActive) controller.play();
    } catch (_) {
      _watchdog?.cancel();
      if (!settled) {
        settled = true;
        if (mounted) setState(() => _videoError = true);
      }
      _safeDispose(controller);
      _video = null;
    } finally {
      _isInitializing = false;
    }
  }

  /// `dispose()` sur un contrôleur jamais complètement initialisé peut
  /// échouer selon la plateforme — ça ne doit jamais empêcher la mise à
  /// jour d'état (succès/échec) qui l'entoure.
  void _safeDispose(VideoPlayerController controller) {
    try {
      controller.dispose();
    } catch (_) {}
  }

  void _retryVideo() {
    _watchdog?.cancel();
    final previous = _video;
    if (previous != null) _safeDispose(previous);
    _video = null;
    setState(() => _videoError = false);
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant _StatusPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _video?.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      _video?.pause();
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMedia(),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.5, 1],
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.75),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 84,
          bottom: 24,
          child: _SellerInfo(
            status: widget.status,
            currentUserId: widget.currentUserId,
          ),
        ),
        Positioned(
          right: 12,
          bottom: 80,
          child: _Actions(status: widget.status),
        ),
      ],
    );
  }

  Widget _buildMedia() {
    if (widget.status.type == StatusType.video) {
      if (_videoError) {
        return Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Impossible de lire cette vidéo.',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _retryVideo,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        );
      }

      if (_video?.value.isInitialized == true) {
        // BoxFit.contain (comme les images) : la vidéo entière reste
        // visible sur fond noir, jamais rognée pour remplir l'écran.
        return Container(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: _video!.value.aspectRatio,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _video!.value.size.width,
                  height: _video!.value.size.height,
                  child: VideoPlayer(_video!),
                ),
              ),
            ),
          ),
        );
      }

      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Réutilise OccasionImage.detail (BoxFit.contain sur fond noir, ratio
    // préservé) au lieu de dupliquer ce comportement ici.
    return SizedBox.expand(child: OccasionImage.detail(widget.status.mediaUrl));
  }
}

class _SellerInfo extends StatelessWidget {
  const _SellerInfo({required this.status, required this.currentUserId});

  final Status status;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final initial = status.sellerName.isEmpty
        ? '?'
        : status.sellerName.characters.first.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[700],
              backgroundImage: status.sellerProfileImageUrl == null
                  ? null
                  : CachedNetworkImageProvider(status.sellerProfileImageUrl!),
              child: status.sellerProfileImageUrl == null
                  ? Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status.sellerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  shadows: [Shadow(blurRadius: 6)],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => context.push(
                '/open-chat',
                extra: {
                  'sellerId': status.sellerId,
                  'sellerName': status.sellerName,
                },
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Contacter'),
            ),
            if (currentUserId.isNotEmpty && currentUserId != status.sellerId)
              IconButton(
                tooltip: 'Signaler ou bloquer',
                onPressed: () => showReportOrBlockSheet(
                  context,
                  currentUserId: currentUserId,
                  targetUserId: status.sellerId,
                  targetUserName: status.sellerName,
                  targetType: ReportTargetType.status,
                  contentId: status.id,
                ),
                icon: const Icon(Icons.more_vert, color: Colors.white),
              ),
          ],
        ),
        if (status.caption?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(
            status.caption!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              shadows: [Shadow(blurRadius: 6)],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.status});

  final Status status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLiked = ref.watch(
      statusNotifierProvider.select((state) => state.isLiked(status.id)),
    );

    return Column(
      children: [
        _ActionButton(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? Colors.red : Colors.white,
          label: '${status.likesCount}',
          onTap: () =>
              ref.read(statusNotifierProvider.notifier).toggleLike(status.id),
        ),
        const SizedBox(height: 20),
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          color: Colors.white,
          label: 'Message',
          onTap: () => context.push(
            '/open-chat',
            extra: {
              'sellerId': status.sellerId,
              'sellerName': status.sellerName,
            },
          ),
        ),
        const SizedBox(height: 20),
        _ActionButton(
          icon: Icons.share_outlined,
          color: Colors.white,
          label: 'Partager',
          onTap: () {
            final caption = status.caption?.trim();
            final text = [
              'Découvrez ce que ${status.sellerName} propose sur Occasion !',
              if (caption != null && caption.isNotEmpty) caption,
              'https://davekbg08-cloud.github.io/occasion/',
            ].join('\n');
            Share.share(text);
          },
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 30,
            shadows: const [Shadow(blurRadius: 8)],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              shadows: [Shadow(blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.isSeller, required this.onPublish});

  final bool isSeller;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_circle_outline, color: Colors.grey, size: 72),
          const SizedBox(height: 16),
          const Text(
            'Aucun contenu pour le moment.',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (isSeller)
            FilledButton.icon(
              onPressed: onPublish,
              icon: const Icon(Icons.add),
              label: const Text('Publier le premier article'),
            )
          else
            Text(
              'Les vendeurs publieront bientôt leurs articles.',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

class _ErrorFeed extends ConsumerWidget {
  const _ErrorFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message =
        ref.watch(statusNotifierProvider).error ??
        'Impossible de charger le feed pour le moment.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.read(statusNotifierProvider.notifier).retryLoadFeed(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
