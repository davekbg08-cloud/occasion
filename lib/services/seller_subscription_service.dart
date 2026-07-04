import 'package:cloud_firestore/cloud_firestore.dart';

/// Vérifie si un vendeur a un abonnement actif et non expiré (collection
/// `subscriptions`, activée par les Cloud Functions après confirmation d'un
/// paiement manuel par un admin). Centralise la logique utilisée à la fois
/// pour les limites de publication d'annonces et pour le feed (statuts) :
/// un abonnement à terme doit être traité comme "pas d'abonnement".
class SellerSubscriptionService {
  SellerSubscriptionService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<bool> hasActiveSubscription(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('subscriptions')
          .doc(userId)
          .get();
      final data = snapshot.data();
      if (data == null || data['isActive'] != true) return false;
      final expiryDate = _toDateTime(data['expiryDate']);
      return expiryDate != null && expiryDate.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  DateTime? _toDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
