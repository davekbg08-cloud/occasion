import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccountDeletionService {
  AccountDeletionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<void> deleteAccount(String userId) async {
    final batch = _db.batch();
    final userRef = _db.collection('users').doc(userId);

    batch.set(userRef, {
      'name': 'Utilisateur supprime',
      'phone': '',
      'profileImageUrl': null,
      'fcmToken': FieldValue.delete(),
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final statuses = await _db
        .collection('statuses')
        .where('sellerId', isEqualTo: userId)
        .get();
    for (final doc in statuses.docs) {
      batch.delete(doc.reference);
    }

    final products = await _db
        .collection('products')
        .where('sellerId', isEqualTo: userId)
        .get();
    for (final doc in products.docs) {
      batch.delete(doc.reference);
    }

    final blocked = await userRef.collection('blockedUsers').get();
    for (final doc in blocked.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();

    try {
      final current = _auth.currentUser;
      if (current != null && current.uid == userId) {
        await current.delete();
      }
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') rethrow;
    }
  }
}
