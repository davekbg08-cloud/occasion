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
    final userRef = _db.collection('users').doc(userId);

    // Six lectures indépendantes (aucune ne dépend du résultat d'une
    // autre) : lancées en parallèle plutôt qu'en série pour ne pas cumuler
    // leurs latences sur une action utilisateur (suppression de compte).
    final [
      statuses,
      annonces,
      blocked,
      devices,
      chatsAsBuyer,
      chatsAsSeller,
    ] = await Future.wait([
      _db.collection('statuses').where('sellerId', isEqualTo: userId).get(),
      _db.collection('annonces').where('vendeurId', isEqualTo: userId).get(),
      userRef.collection('blockedUsers').get(),
      userRef.collection('devices').get(),
      _db.collection('chats').where('buyerId', isEqualTo: userId).get(),
      _db.collection('chats').where('sellerId', isEqualTo: userId).get(),
    ]);

    // `statuses` ne peut plus être supprimé directement par le client
    // (firestore.rules : `allow delete: if false`, exclusivement via cette
    // Cloud Function qui nettoie aussi les likes et le fichier Storage) —
    // un `batch.delete()` direct ferait échouer TOUT le lot ci-dessous dès
    // que l'utilisateur a publié au moins un statut. Les appels sont
    // indépendants entre eux, jamais besoin de les attendre en série.
    await Future.wait(
      statuses.docs.map(
        (doc) =>
            _functions.httpsCallable('deleteStatus').call({'statusId': doc.id}),
      ),
    );

    final batch = _db.batch();

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
    for (final doc in annonces.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in blocked.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in devices.docs) {
      batch.delete(doc.reference);
    }

    // Le nom affiché dans les conversations existantes est dénormalisé sur
    // le document `chats` (buyerName/sellerName, voir Chat.otherUserName) —
    // jamais relu depuis `users/{uid}` en direct. Sans cette mise à jour,
    // le nom d'origine resterait affiché indéfiniment à l'autre
    // participant, malgré la promesse "votre nom apparaîtra comme
    // Utilisateur supprimé".
    for (final (snap, nameField) in [
      (chatsAsBuyer, 'buyerName'),
      (chatsAsSeller, 'sellerName'),
    ]) {
      for (final doc in snap.docs) {
        batch.update(doc.reference, {nameField: _deletedUserName});
      }
    }

    await batch.commit();

    final current = _auth.currentUser;
    if (current != null && current.uid == userId) {
      // Toute erreur ici (pas seulement `requires-recent-login`) doit
      // remonter à l'appelant : les données Firestore sont déjà anonymisées
      // à ce stade et ne peuvent pas être restaurées, donc masquer un échec
      // de suppression Auth laisserait croire à tort que le compte est
      // totalement supprimé alors que la session reste valide.
      await current.delete();
    }
  }
}
