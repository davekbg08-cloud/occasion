import 'package:cloud_functions/cloud_functions.dart';

class PaymentSettlementService {
  PaymentSettlementService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Confirme un paiement Orange Money manuel après vérification humaine
  /// (admin uniquement, contrôlé côté serveur). Fonctionne pour une
  /// commande comme pour un abonnement vendeur.
  Future<void> confirmManualPayment(String transactionId) async {
    final callable = _functions.httpsCallable('confirmManualPayment');
    await callable.call(<String, dynamic>{'transactionId': transactionId});
  }

  /// Rejette un paiement Orange Money manuel (référence introuvable,
  /// montant incorrect...).
  Future<void> rejectManualPayment(String transactionId) async {
    final callable = _functions.httpsCallable('rejectManualPayment');
    await callable.call(<String, dynamic>{'transactionId': transactionId});
  }
}
