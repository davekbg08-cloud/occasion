import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../models/report.dart';
import '../models/status.dart';
import '../providers/auth_provider.dart';
import '../providers/moderation_provider.dart';
import '../providers/status_provider.dart';
import '../services/seller_subscription_guard.dart';
import '../widgets/report_block_sheet.dart';

class StatusFeedScreen extends ConsumerStatefulWidget {
  const StatusFeedScreen({super.key});

  @override
  ConsumerState<StatusFeedScreen> createState() => _StatusFeedScreenState();
}

class _StatusFeedScreenState extends ConsumerState<StatusFeedScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(statusNotifierProvider.notifier).loadFeed();
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
                      status: status,
                      isActive: index == _currentPage,
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

  @override
  void initState() {
    super.initState();
    if (widget.status.type == StatusType.video) {
      _initVideo();
    }
  }

  void _initVideo() {
    _video = VideoPlayerController.networkUrl(Uri.parse(widget.status.mediaUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _video?.setLooping(true);
        if (widget.isActive) _video?.play();
      });
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
      if (_video?.value.isInitialized == true) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _video!.value.size.width,
            height: _video!.value.size.height,
            child: VideoPlayer(_video!),
          ),
        );
      }

      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.status.mediaUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      errorWidget: (context, url, error) => const Center(
        child: Icon(Icons.broken_image, color: Colors.white, size: 48),
      ),
    );
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Partage à venir')));
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

class _ErrorFeed extends StatelessWidget {
  const _ErrorFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Impossible de charger le feed pour le moment.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
