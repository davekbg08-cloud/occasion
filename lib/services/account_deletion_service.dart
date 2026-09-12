import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

const _deletedUserName = 'Utilisateur supprimé';

class AccountDeletionService {
  AccountDeletionService({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = firebaseAuth ?? FirebaseAuth.instance,
       _functionsOverride = functions;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  // Résolution paresseuse : `FirebaseFunctions.instance` échouerait dans les
  // tests qui construisent ce service sans avoir initialisé Firebase (même
  // principe que AnnonceRepositoryImpl).
  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

  Future<void> deleteAccount(String userId) async {
    // `statuses` ne peut plus être supprimé directement par le client
    // (firestore.rules : `allow delete: if false`, exclusivement via cette
    // Cloud Function qui nettoie aussi les likes et le fichier Storage) —
    // un `batch.delete()` direct ferait échouer TOUT le lot ci-dessous dès
    // que l'utilisateur a publié au moins un statut.
    final statuses = await _db
        .collection('statuses')
        .where('sellerId', isEqualTo: userId)
        .get();
    for (final doc in statuses.docs) {
      await _functions.httpsCallable('deleteStatus').call({'statusId': doc.id});
    }

    final batch = _db.batch();
    final userRef = _db.collection('users').doc(userId);

    batch.set(userRef, {
      'name': _deletedUserName,
      'phone': '',
      'profileImageUrl': null,
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Les annonces vivent dans `annonces` (voir AnnonceRepositoryImpl),
    // jamais dans `products` — une ancienne collection jamais utilisée par
    // le reste de l'app, qui laissait les annonces publiées intactes après
    // suppression du compte malgré la promesse affichée à l'écran.
    final annonces = await _db
        .collection('annonces')
        .where('vendeurId', isEqualTo: userId)
        .get();
    for (final doc in annonces.docs) {
      batch.delete(doc.reference);
    }

    final blocked = await userRef.collection('blockedUsers').get();
    for (final doc in blocked.docs) {
      batch.delete(doc.reference);
    }

    final devices = await userRef.collection('devices').get();
    for (final doc in devices.docs) {
      batch.delete(doc.reference);
    }

    // Le nom affiché dans les conversations existantes est dénormalisé sur
    // le document `chats` (buyerName/sellerName, voir Chat.otherUserName) —
    // jamais relu depuis `users/{uid}` en direct. Sans cette mise à jour,
    // le nom d'origine resterait affiché indéfiniment à l'autre
    // participant, malgré la promesse "votre nom apparaîtra comme
    // Utilisateur supprimé".
    final chatsAsBuyer = await _db
        .collection('chats')
        .where('buyerId', isEqualTo: userId)
        .get();
    for (final doc in chatsAsBuyer.docs) {
      batch.update(doc.reference, {'buyerName': _deletedUserName});
    }
    final chatsAsSeller = await _db
        .collection('chats')
        .where('sellerId', isEqualTo: userId)
        .get();
    for (final doc in chatsAsSeller.docs) {
      batch.update(doc.reference, {'sellerName': _deletedUserName});
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
