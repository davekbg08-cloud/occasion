import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

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

  return true;
}
