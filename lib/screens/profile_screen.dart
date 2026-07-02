import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/notification_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final subscription = ref.watch(subscriptionNotifierProvider);
    final user = authState.user;
    final phoneNumber = user?.phone;
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
        title: Text(isSeller ? 'Paramètres vendeur' : 'Compte acheteur'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 55,
              backgroundColor: isSeller ? Colors.blue : Colors.green,
              child: Icon(
                isSeller ? Icons.storefront : Icons.person,
                size: 62,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              authState.isAuthenticated
                  ? user?.name ?? 'Bienvenue !'
                  : 'Non connecté',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              authState.isAuthenticated
                  ? phoneNumber?.isNotEmpty == true
                        ? phoneNumber!
                        : 'Numéro non renseigné'
                  : 'Connectez-vous pour accéder à votre compte',
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
                  onLogout: () => _logout(context, ref, user.id),
                )
              else
                _BuyerOptions(
                  userId: user.id,
                  onLogout: () => _logout(context, ref, user.id),
                )
            else
              _SignedOutOptions(),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    await NotificationService.clearToken(userId);
    if (!context.mounted) return;
    await ref.read(authNotifierProvider.notifier).logout();
    if (!context.mounted) return;
    context.go('/auth');
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
          icon: Icons.home_outlined,
          title: 'Accueil / Feed',
          onTap: () => context.go('/buyer-home'),
        ),
        _ProfileTile(
          icon: Icons.storefront_outlined,
          title: 'Nos produits',
          onTap: () => context.push('/products'),
        ),
        _ProfileTile(
          icon: Icons.search,
          title: 'Recherche',
          onTap: () => context.push('/search'),
        ),
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
          icon: Icons.chat_bubble_outline,
          title: 'Messages privés',
          onTap: () => context.push('/buyer-messages'),
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
          icon: Icons.dashboard_outlined,
          title: 'Tableau de bord vendeur',
          onTap: () => context.go('/seller-dashboard'),
        ),
        _ProfileTile(
          icon: Icons.list_alt_outlined,
          title: 'Mes annonces',
          onTap: () => context.push('/my-listings'),
        ),
        _ProfileTile(
          icon: Icons.add_box_outlined,
          title: 'Publier une annonce',
          onTap: () => context.push('/publish-product'),
        ),
        _ProfileTile(
          icon: Icons.local_shipping_outlined,
          title: 'Commandes reçues',
          onTap: () => context.push('/seller-orders'),
        ),
        _ProfileTile(
          icon: Icons.chat_bubble_outline,
          title: 'Messages acheteurs',
          onTap: () => context.push('/seller-messages'),
        ),
        _ProfileTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Revenus',
          onTap: () => context.push('/seller-revenue'),
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
          icon: Icons.settings_outlined,
          title: 'Paramètres vendeur',
          onTap: () {},
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
              onPressed: () => context.go('/auth'),
              icon: const Icon(Icons.login),
              label: const Text('Connexion'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/register'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Inscription'),
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
