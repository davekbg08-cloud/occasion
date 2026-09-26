import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_language.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/notification_service.dart';
import '../services/payment_settlement_service.dart';
import '../theme/app_theme.dart';
import '../widgets/occasion_image.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final subscription = ref.watch(subscriptionNotifierProvider);
    final user = authState.user;
    final isSeller = user?.isSeller ?? false;
    final hasActiveSubscription =
        subscription != null &&
        subscription.isActive &&
        !subscription.isExpired;
    final subscriptionSubtitle = hasActiveSubscription
        ? "Actif jusqu'au ${subscription.expiryDate.toString().split(' ').first}"
        : 'Aucun abonnement vendeur actif';

    final unreadNotifications = user == null
        ? 0
        : ref.watch(unreadNotificationsCountProvider(user.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Profil')),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: tr('Notifications'),
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: unreadNotifications > 0,
              label: Text('$unreadNotifications'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _ProfileHeader(
            imageUrl: user?.profileImageUrl,
            name: authState.isAuthenticated
                ? user?.name ?? 'Bienvenue'
                : 'Non connecté',
            details: authState.isAuthenticated
                ? (user?.phone.isNotEmpty == true
                      ? user!.phone
                      : 'Numéro non renseigné')
                : 'Connecte-toi pour accéder à ton compte.',
            roleLabel: isSeller ? 'Vendeur' : 'Acheteur',
            isSeller: isSeller,
            isLoading: authState.isLoading,
            onEditPhoto: user == null ? null : _choosePhotoSource,
          ),
          const SizedBox(height: 8),
          if (authState.isAuthenticated && user != null) ...[
            const _AdminSection(),
            if (isSeller)
              _SellerSections(
                userId: user.id,
                subscriptionSubtitle: subscriptionSubtitle,
              )
            else
              const _BuyerSections(),
            _Section(
              title: tr('Compte'),
              children: [
                _ProfileTile(
                  icon: Icons.settings_outlined,
                  title: tr('Paramètres et confidentialité'),
                  onTap: () => context.push('/account-settings'),
                ),
                _LogoutTile(onTap: () => _logout(context, user.id)),
              ],
            ),
          ] else
            const _SignedOutOptions(),
        ],
      ),
    );
  }

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(tr('Choisir depuis la galerie')),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(tr('Prendre une photo')),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;

    final image = await _picker.pickImage(
      source: source,
      imageQuality: 76,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image == null) return;

    try {
      await ref.read(authNotifierProvider.notifier).updateProfilePhoto(image);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Photo de profil mise à jour.'))),
      );
    } catch (_) {
      if (!mounted) return;
      final message =
          ref.read(authNotifierProvider).errorMessage ??
          'Impossible de mettre à jour la photo.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _logout(BuildContext context, String userId) async {
    await NotificationService.clearToken(userId);
    if (!context.mounted) return;
    await ref.read(authNotifierProvider.notifier).logout();
    if (!context.mounted) return;
    context.go('/auth');
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.color,
    this.size = 110,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: color,
        child: Icon(fallbackIcon, size: size * 0.56, color: Colors.white),
      );
    }

    return ClipOval(
      child: OccasionImage.thumbnail(
        url,
        width: size,
        height: size,
        cacheWidth: (size * 2).round(),
        cacheHeight: (size * 2).round(),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.imageUrl,
    required this.name,
    required this.details,
    required this.roleLabel,
    required this.isSeller,
    required this.isLoading,
    required this.onEditPhoto,
  });

  final String? imageUrl;
  final String name;
  final String details;
  final String roleLabel;
  final bool isSeller;
  final bool isLoading;
  final VoidCallback? onEditPhoto;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _ProfileAvatar(
              imageUrl: imageUrl,
              fallbackIcon: isSeller ? Icons.storefront : Icons.person,
              color: isSeller ? AppColors.primary : Colors.green,
              size: 64,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(details, style: TextStyle(color: Colors.grey[400])),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      roleLabel,
                      style: TextStyle(color: accent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (onEditPhoto != null)
              IconButton(
                tooltip: tr('Modifier la photo'),
                onPressed: isLoading ? null : onEditPhoto,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// Outils d'administration : séparés du menu vendeur/acheteur, visibles
/// uniquement pour un administrateur (le routeur les protège aussi).
class _AdminSection extends StatelessWidget {
  const _AdminSection();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PaymentSettlementService().isCurrentUserAdmin(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return _Section(
          title: tr('Administration'),
          children: [
            _ProfileTile(
              icon: Icons.verified_user_outlined,
              title: tr('Paiements Orange Money à vérifier'),
              onTap: () => context.push('/admin/orders'),
            ),
            _ProfileTile(
              icon: Icons.flag_outlined,
              title: tr('Signalements'),
              onTap: () => context.push('/admin/reports'),
            ),
            _ProfileTile(
              icon: Icons.stars_outlined,
              title: tr('Remise à zéro des points'),
              onTap: () => context.push('/admin/loyalty'),
            ),
          ],
        );
      },
    );
  }
}

class _BuyerSections extends StatelessWidget {
  const _BuyerSections();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Section(
          title: tr('Mes achats'),
          children: [
            _ProfileTile(
              icon: Icons.shopping_cart_outlined,
              title: tr('Mon panier'),
              onTap: () => context.push('/cart'),
            ),
            _ProfileTile(
              icon: Icons.receipt_long_outlined,
              title: tr('Mes commandes'),
              onTap: () => context.push('/orders'),
            ),
            _ProfileTile(
              icon: Icons.credit_card,
              title: tr('Moyens de paiement'),
              onTap: () => context.push('/payment'),
            ),
          ],
        ),
        _Section(
          title: tr('Récompenses'),
          children: [
            _ProfileTile(
              icon: Icons.stars_outlined,
              title: tr('Mes points de fidélité'),
              onTap: () => context.push('/loyalty-points'),
            ),
            _ProfileTile(
              icon: Icons.group_add_outlined,
              title: tr('Parrainage'),
              onTap: () => context.push('/referral'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SellerSections extends StatelessWidget {
  const _SellerSections({
    required this.userId,
    required this.subscriptionSubtitle,
  });

  final String userId;
  final String subscriptionSubtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Section(
          title: tr('Ma boutique'),
          children: [
            _ProfileTile(
              icon: Icons.workspace_premium_outlined,
              title: tr('Abonnement vendeur'),
              subtitle: subscriptionSubtitle,
              onTap: () => context.push('/subscription'),
            ),
            _ProfileTile(
              icon: Icons.account_balance_wallet_outlined,
              title: tr('Numéro de reversement'),
              onTap: () => context.push('/payout-account'),
            ),
            _ProfileTile(
              icon: Icons.storefront_outlined,
              title: tr('Voir ma page vendeur'),
              onTap: () => context.push('/seller/$userId'),
            ),
          ],
        ),
        _Section(
          title: tr('Récompenses'),
          children: [
            _ProfileTile(
              icon: Icons.card_giftcard_outlined,
              title: tr('Mon catalogue de cadeaux'),
              onTap: () => context.push('/gift-catalog'),
            ),
            _ProfileTile(
              icon: Icons.redeem_outlined,
              title: tr('Demandes d\'échange'),
              onTap: () => context.push('/gift-redemptions'),
            ),
            _ProfileTile(
              icon: Icons.group_add_outlined,
              title: tr('Parrainage'),
              onTap: () => context.push('/referral'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignedOutOptions extends StatelessWidget {
  const _SignedOutOptions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.login),
              label: Text(tr('Se connecter')),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/register'),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(tr('Créer un compte')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.logout, color: Colors.red),
      title: Text(
        tr('Déconnexion'),
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }
}
