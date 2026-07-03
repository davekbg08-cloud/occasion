import 'package:cloud_functions/cloud_functions.dart';

/// Appelle la Cloud Function `confirmCinetPayPayment`, qui revérifie le
/// paiement directement auprès de CinetPay (jamais confiance au seul
/// callback client) puis met à jour Firestore (orders / subscriptions /
/// transactions) si le paiement est réellement confirmé.
///
/// Retourne `true` si le paiement est confirmé "paid", `false` sinon.
/// Le webhook `cinetpayNotify` reste le filet de sécurité : si cet appel
/// échoue (réseau coupé juste après paiement, etc.), la confirmation
/// arrivera quand même via le webhook CinetPay en arrière-plan.
class PaymentSettlementService {
  PaymentSettlementService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<bool> confirmPayment(String transactionId) async {
    try {
      final callable = _functions.httpsCallable('confirmCinetPayPayment');
      final result = await callable.call(<String, dynamic>{
        'transactionId': transactionId,
      });
      final status = (result.data as Map?)?['status'] as String?;
      return status == 'paid';
    } catch (_) {
      // Le webhook CinetPay confirmera en arrière-plan si besoin.
      return false;
    }
  }
}
