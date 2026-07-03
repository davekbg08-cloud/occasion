import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/notification_service.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text(isSeller ? 'Mon compte vendeur' : 'Mon compte acheteur'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            _ProfileAvatar(
              imageUrl: user?.profileImageUrl,
              fallbackIcon: isSeller ? Icons.storefront : Icons.person,
              color: isSeller ? Colors.blue : Colors.green,
            ),
            const SizedBox(height: 12),
            if (user != null)
              OutlinedButton.icon(
                onPressed: authState.isLoading ? null : _choosePhotoSource,
                icon: authState.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined),
                label: const Text('Modifier la photo'),
              ),
            const SizedBox(height: 16),
            Text(
              authState.isAuthenticated
                  ? user?.name ?? 'Bienvenue'
                  : 'Non connecté',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              authState.isAuthenticated
                  ? user?.phone.isNotEmpty == true
                        ? user!.phone
                        : 'Numéro non renseigné'
                  : 'Connecte-toi pour accéder à ton compte.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            const Divider(),
            if (authState.isAuthenticated && user != null)
              if (isSeller)
                _SellerOptions(
                  userId: user.id,
                  subscriptionSubtitle: subscriptionSubtitle,
                  onLogout: () => _logout(context, user.id),
                )
              else
                _BuyerOptions(
                  userId: user.id,
                  onLogout: () => _logout(context, user.id),
                )
            else
              const _SignedOutOptions(),
          ],
        ),
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
                title: const Text('Choisir depuis la galerie'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
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
        const SnackBar(content: Text('Photo de profil mise à jour.')),
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
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 55,
        backgroundColor: color,
        child: Icon(fallbackIcon, size: 62, color: Colors.white),
      );
    }

    return ClipOval(
      child: Image.network(
        url,
        width: 110,
        height: 110,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return CircleAvatar(
            radius: 55,
            backgroundColor: color,
            child: const CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (context, error, stackTrace) => CircleAvatar(
          radius: 55,
          backgroundColor: color,
          child: Icon(fallbackIcon, size: 62, color: Colors.white),
        ),
      ),
    );
  }
}

class _BuyerOptions extends StatelessWidget {
  const _BuyerOptions({required this.userId, required this.onLogout});

  final String userId;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileTile(
          icon: Icons.shopping_cart_outlined,
          title: 'Mon panier',
          onTap: () => context.push('/cart'),
        ),
        _ProfileTile(
          icon: Icons.receipt_long_outlined,
          title: 'Mes commandes',
          onTap: () => context.push('/orders'),
        ),
        _ProfileTile(
          icon: Icons.credit_card,
          title: 'Moyens de paiement',
          onTap: () => context.push('/payment'),
        ),
        _ProfileTile(
          icon: Icons.location_on_outlined,
          title: 'Adresses de livraison',
          onTap: () => context.push('/addresses'),
        ),
        _ProfileTile(
          icon: Icons.favorite_outline,
          title: 'Favoris',
          onTap: () => context.push('/favorites'),
        ),
        _ProfileTile(
          icon: Icons.chat_bubble_outline,
          title: 'Messages',
          onTap: () => context.push('/buyer-messages'),
        ),
        _ProfileTile(
          icon: Icons.block,
          title: 'Utilisateurs bloqués',
          onTap: () => context.push('/blocked-users', extra: userId),
        ),
        _ProfileTile(
          icon: Icons.delete_outline,
          title: 'Supprimer mon compte',
          onTap: () => context.push('/delete-account', extra: userId),
        ),
        const Divider(),
        _LogoutTile(onTap: onLogout),
      ],
    );
  }
}

class _SellerOptions extends StatelessWidget {
  const _SellerOptions({
    required this.userId,
    required this.subscriptionSubtitle,
    required this.onLogout,
  });

  final String userId;
  final String subscriptionSubtitle;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileTile(
          icon: Icons.storefront_outlined,
          title: 'Profil vendeur',
          onTap: () => context.go('/seller-dashboard'),
        ),
        _ProfileTile(
          icon: Icons.add_box_outlined,
          title: 'Publier une annonce',
          onTap: () => context.push('/publish-product'),
        ),
        _ProfileTile(
          icon: Icons.list_alt_outlined,
          title: 'Mes annonces',
          onTap: () => context.push('/my-listings'),
        ),
        _ProfileTile(
          icon: Icons.bar_chart_outlined,
          title: 'Statistiques',
          onTap: () => context.push('/seller-statistics'),
        ),
        _ProfileTile(
          icon: Icons.card_membership,
          title: 'Abonnement vendeur',
          subtitle: subscriptionSubtitle,
          onTap: () => context.push('/subscription'),
        ),
        _ProfileTile(
          icon: Icons.chat_bubble_outline,
          title: 'Messages',
          onTap: () => context.push('/seller-messages'),
        ),
        _ProfileTile(
          icon: Icons.delete_outline,
          title: 'Supprimer mon compte',
          onTap: () => context.push('/delete-account', extra: userId),
        ),
        const Divider(),
        _LogoutTile(onTap: onLogout),
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
              label: const Text('Se connecter'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/register'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Créer un compte'),
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
      trailing: const Icon(Icons.arrow_forward_ios, size: 18),
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
      title: const Text(
        'Déconnexion',
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }
}
