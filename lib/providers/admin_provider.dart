import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_service.dart';
import 'auth_provider.dart';

final adminServiceProvider = Provider<AdminService>((ref) => AdminService());

/// Vrai si l'utilisateur connecté est administrateur. Une seule lecture par
/// compte connecté, partagée par le menu, le garde des routes /admin/* et
/// le paiement ; recalculée automatiquement à chaque changement de compte.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(
    authNotifierProvider.select((state) => state.currentUser?.id),
  );
  if (uid == null) return false;
  return ref.watch(adminServiceProvider).isAdmin(uid);
});
