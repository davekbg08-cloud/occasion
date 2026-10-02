import 'package:cloud_functions/cloud_functions.dart';

/// Suppression complète du compte, exécutée côté serveur (Cloud Function
/// `deleteAccount`, Admin SDK) : Firestore, fichiers Storage (photos, pièces
/// d'identité), médias de statuts, présence et compte Auth. Côté client,
/// elle ne pouvait jamais être complète (règles, fichiers des autres
/// dossiers) et échouait souvent sur `requires-recent-login` APRÈS avoir
/// déjà vidé le profil.
class AccountDeletionService {
  AccountDeletionService({this.callDeleteAccount});

  /// Remplaçable en test uniquement.
  final Future<void> Function()? callDeleteAccount;

  Future<void> deleteAccount() async {
    final call = callDeleteAccount;
    if (call != null) return call();
    await FirebaseFunctions.instance
        .httpsCallable(
          'deleteAccount',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call<void>();
  }
}
