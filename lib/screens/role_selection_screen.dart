import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.storefront, color: Colors.blue, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Bienvenue !',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Créez votre compte en choisissant votre rôle',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
              const SizedBox(height: 56),
              _RoleButton(
                icon: Icons.storefront_rounded,
                title: 'Vendeur',
                subtitle:
                    'Publiez vos articles avec un abonnement mensuel de 20000 FC.',
                accentColor: Colors.blue,
                onTap: () => _selectRole(context, ref, UserRole.seller),
              ),
              const SizedBox(height: 20),
              _RoleButton(
                icon: Icons.shopping_bag_rounded,
                title: 'Acheteur',
                subtitle:
                    'Parcourez les articles gratuitement, sans abonnement mensuel.',
                accentColor: Colors.green,
                onTap: () => _selectRole(context, ref, UserRole.buyer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectRole(BuildContext context, WidgetRef ref, UserRole role) {
    ref.read(authNotifierProvider.notifier).selectRole(role);
    context.go('/phone-auth');
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[800]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[600], size: 14),
          ],
        ),
      ),
    );
  }
}
