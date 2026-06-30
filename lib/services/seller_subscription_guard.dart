import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';

bool checkSellerSubscription(BuildContext context, WidgetRef ref) {
  final user = ref.read(authNotifierProvider).currentUser;
  if (user == null) {
    context.go('/role-selection');
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
  if (hasActiveSubscription) {
    return true;
  }

  context.push('/subscription');
  return false;
}
