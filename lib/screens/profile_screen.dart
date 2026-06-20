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
        ? "Actif jusqu'au ${subscription!.expiryDate.toString().split(' ').first}"
        : 'Aucun abonnement vendeur actif';

    return Scaffold(
      appBar: AppBar(
        title: Text(isSeller ? 'Mon Compte Vendeur' : 'Mon Compte Acheteur'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const CircleAvatar(
              radius: 55,
              backgroundColor: Colors.blue,
              child: Icon(Icons.person, size: 70, color: Colors.white),
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
                  ? phoneNumber ?? 'Numéro non renseigné'
                  : 'Connectez-vous pour accéder à votre compte',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            const Divider(),
            if (authState.isAuthenticated) ...[
              _ProfileTile(
                icon: Icons.shopping_cart,
                title: 'Mon Panier',
                onTap: () => context.push('/cart'),
              ),
              _ProfileTile(
                icon: Icons.history,
                title: 'Historique des commandes',
                onTap: () {},
              ),
              _ProfileTile(
                icon: Icons.credit_card,
                title: 'Moyens de paiement',
                onTap: () => context.push('/payment'),
              ),
              if (isSeller)
                ListTile(
                  leading: const Icon(Icons.card_membership),
                  title: const Text('Abonnement vendeur'),
                  subtitle: Text(subscriptionSubtitle),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                  onTap: () => context.push('/subscription'),
                )
              else
                const ListTile(
                  leading: Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  title: Text('Compte acheteur gratuit'),
                  subtitle: Text('Aucun abonnement mensuel'),
                ),
              _ProfileTile(
                icon: Icons.location_on,
                title: 'Adresses de livraison',
                onTap: () {},
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Déconnexion',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  if (user != null) {
                    await NotificationService.clearToken(user.id);
                  }
                  if (!context.mounted) return;
                  ref.read(authNotifierProvider.notifier).logout();
                  context.go('/auth');
                },
              ),
            ] else ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () => context.go('/auth'),
                  icon: const Icon(Icons.login),
                  label: const Text('Se connecter'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 18),
      onTap: onTap,
    );
  }
}
