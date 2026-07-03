import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subscription.dart';
import 'auth_provider.dart';

class SubscriptionNotifier extends StateNotifier<Subscription?> {
  SubscriptionNotifier({
    FirebaseFirestore? firestore,
    firebase_auth.FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? firebase_auth.FirebaseAuth.instance,
       super(null);

  final FirebaseFirestore _firestore;
  final firebase_auth.FirebaseAuth _auth;

  void activateSubscription(Subscription newSub) {
    state = newSub;
  }

  Future<void> loadForUser(String? userId) async {
    if (userId == null || userId.trim().isEmpty) {
      state = null;
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('subscriptions')
          .doc(userId)
          .get();
      if (!snapshot.exists) {
        state = null;
        return;
      }

      state = Subscription.fromMap({...?snapshot.data(), 'id': snapshot.id});
    } catch (_) {
      state = null;
    }
  }

  /// Crée l'intention de paiement pour un abonnement vendeur. Le
  /// paiement réel se fait ensuite via CinetPay (UI), et l'abonnement
  /// n'est activé dans Firestore qu'après vérification serveur du
  /// paiement (Cloud Function `confirmCinetPayPayment` / `cinetpayNotify`).
  /// Retourne le transactionId à transmettre à CinetPay.
  Future<String> createSubscriptionPaymentIntent({
    required String planId,
    required String planName,
    required double price,
    int durationDays = 30,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connecte-toi avant de payer un abonnement.');
    }

    final intentRef = _firestore.collection('paymentIntents').doc();
    await intentRef.set({
      'type': 'subscription',
      'userId': user.uid,
      'planId': planId,
      'planName': planName,
      'amount': price,
      'currency': 'FC',
      'durationDays': durationDays,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return intentRef.id;
  }
}

final subscriptionNotifierProvider =
    StateNotifierProvider<SubscriptionNotifier, Subscription?>((ref) {
      final notifier = SubscriptionNotifier();
      ref.listen<String?>(
        authNotifierProvider.select((state) => state.currentUser?.id),
        (_, userId) => unawaited(notifier.loadForUser(userId)),
      );
      unawaited(
        notifier.loadForUser(ref.read(authNotifierProvider).currentUser?.id),
      );
      return notifier;
    });
