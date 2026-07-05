import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';

/// Vérifie qu'un vendeur a le droit de publier (annonce ou statut).
///
/// Conditions, dans l'ordre :
///  1. l'utilisateur est connecté ;
///  2. l'utilisateur est un vendeur ;
///  3. l'utilisateur possède un abonnement vendeur ACTIF et non expiré.
///
/// Si l'abonnement est absent, inactif ou expiré, le vendeur est redirigé
/// vers l'écran d'abonnement et la fonction renvoie `false` (publication
/// bloquée). C'est ce qui garantit que l'abonnement de 20 000 FC sert
/// réellement à débloquer la publication.
bool checkSellerSubscription(BuildContext context, WidgetRef ref) {
  final user = ref.read(authNotifierProvider).currentUser;
  if (user == null) {
    context.go('/auth');
    return false;
  }

  if (!user.isSeller) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seuls les vendeurs peuvent publier une annonce.'),
      ),
    );
    return false;
  }

  final subscription = ref.read(subscriptionNotifierProvider);
  final hasActiveSubscription =
      subscription != null && subscription.isActive && !subscription.isExpired;

  if (!hasActiveSubscription) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Ton abonnement vendeur n'est pas actif. Active-le pour publier.",
        ),
      ),
    );
    context.push('/subscription');
    return false;
  }

  return true;
}
