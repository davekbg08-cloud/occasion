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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  void activateSubscription(Subscription newSub) {
    state = newSub;
  }

  /// Écoute en temps réel l'abonnement de l'utilisateur connecté : dès
  /// qu'un admin confirme un paiement manuel (Cloud Function
  /// confirmManualPayment), le statut "Actif" apparaît immédiatement côté
  /// vendeur, sans avoir à redémarrer l'app ni à rafraîchir manuellement.
  Future<void> loadForUser(String? userId) async {
    await _subscription?.cancel();
    _subscription = null;

    if (userId == null || userId.trim().isEmpty) {
      state = null;
      return;
    }

    _subscription = _firestore
        .collection('subscriptions')
        .doc(userId)
        .snapshots()
        .listen(
          (snapshot) {
            state = snapshot.exists
                ? Subscription.fromMap({
                    ...?snapshot.data(),
                    'id': snapshot.id,
                  })
                : null;
          },
          onError: (_) => state = null,
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Soumet une demande de paiement d'abonnement vendeur via Orange Money
  /// manuel : crée l'intention de paiement puis la marque immédiatement
  /// "en attente de vérification". L'abonnement n'est activé qu'après
  /// confirmation par un admin (Cloud Function `confirmManualPayment`).
  Future<String> submitManualSubscriptionPayment({
    required String planId,
    required String planName,
    required double price,
    required String manualPaymentReference,
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

    await intentRef.set({
      'status': 'awaiting_manual_verification',
      'manualPaymentMethod': 'orange_money_manual',
      'manualPaymentReference': manualPaymentReference,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

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
