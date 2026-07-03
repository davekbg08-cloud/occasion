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

  Future<Subscription> simulateSellerPayment({
    required String planId,
    required String planName,
    required double price,
    required String paymentMethod,
    required bool shouldSucceed,
    int durationDays = 30,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Connecte-toi avant de payer un abonnement.');
    }

    final transactionRef = _firestore.collection('transactions').doc();
    final now = DateTime.now();

    await transactionRef.set({
      'id': transactionRef.id,
      'type': 'subscription',
      'userId': user.uid,
      'planId': planId,
      'amount': price,
      'currency': 'FC',
      'paymentMethod': paymentMethod,
      'status': shouldSucceed ? 'paid' : 'failed',
      'simulation': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!shouldSucceed) {
      throw StateError('Paiement refusé en mode simulation.');
    }

    final subscription = Subscription(
      id: user.uid,
      userId: user.uid,
      planId: planId,
      planName: planName,
      price: price,
      startDate: now,
      expiryDate: now.add(Duration(days: durationDays)),
      isActive: true,
      paymentMethod: paymentMethod,
      transactionId: transactionRef.id,
    );

    await _firestore.collection('subscriptions').doc(user.uid).set({
      ...subscription.toMap(),
      'startDate': Timestamp.fromDate(subscription.startDate),
      'expiryDate': Timestamp.fromDate(subscription.expiryDate),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection('users').doc(user.uid).set({
      'sellerSubscriptionActive': true,
      'sellerSubscriptionExpiresAt': Timestamp.fromDate(
        subscription.expiryDate,
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    state = subscription;
    return subscription;
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
