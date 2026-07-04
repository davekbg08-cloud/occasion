import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

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

  /// Vrai si l'utilisateur connecté est un administrateur (collection
  /// `admins`, lisible uniquement par le propriétaire du document).
  Future<bool> isCurrentUserAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap = await _firestore.collection('admins').doc(uid).get();
      return snap.exists;
    } catch (error, stackTrace) {
      developer.log(
        'Vérification admin impossible',
        name: 'PaymentSettlementService.isCurrentUserAdmin',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

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
