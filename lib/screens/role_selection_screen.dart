import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_language.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../widgets/occasion_logo.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const OccasionLogo(size: 132),
              const SizedBox(height: 24),
              Text(
                tr('Bienvenue !'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('Créez votre compte en choisissant votre rôle'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
              const SizedBox(height: 56),
              _RoleCard(
                icon: Icons.storefront_rounded,
                title: tr('Vendeur'),
                description:
                    "Créez gratuitement votre compte vendeur et parcourez l'application.",
                accentColor: AppColors.primary,
                onTap: () =>
                    context.push('/phone-auth', extra: UserRole.seller),
              ),
              const SizedBox(height: 20),
              _RoleCard(
                icon: Icons.shopping_bag_rounded,
                title: tr('Acheteur'),
                description:
                    'Parcourez les articles gratuitement, sans abonnement mensuel.',
                accentColor: Colors.green,
                onTap: () => context.push('/phone-auth', extra: UserRole.buyer),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tr('Déjà un compte ? '),
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/login'),
                    child: Text(
                      tr('Se connecter'),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
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
                    description,
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
