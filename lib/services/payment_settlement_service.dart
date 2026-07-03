import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

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
  PaymentSettlementService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    firebase_auth.FirebaseAuth? auth,
  }) : _functions = functions ?? FirebaseFunctions.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? firebase_auth.FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final firebase_auth.FirebaseAuth _auth;

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

  /// Vrai si l'utilisateur connecté est un administrateur (collection
  /// `admins`, lisible uniquement par le propriétaire du document).
  Future<bool> isCurrentUserAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap = await _firestore.collection('admins').doc(uid).get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// Confirme un paiement Orange Money manuel après vérification humaine
  /// (admin uniquement, contrôlé côté serveur).
  Future<void> confirmManualPayment(String orderId) async {
    final callable = _functions.httpsCallable('confirmManualPayment');
    await callable.call(<String, dynamic>{'orderId': orderId});
  }

  /// Rejette un paiement Orange Money manuel (référence introuvable,
  /// montant incorrect...).
  Future<void> rejectManualPayment(String orderId) async {
    final callable = _functions.httpsCallable('rejectManualPayment');
    await callable.call(<String, dynamic>{'orderId': orderId});
  }
}
