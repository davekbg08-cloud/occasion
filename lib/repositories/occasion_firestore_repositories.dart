import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/annonce.dart';
import '../models/favori.dart';
import '../models/firestore/occasion_models.dart';

class OccasionFirestoreException implements Exception {
  const OccasionFirestoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'OccasionFirestoreException: $message';
}

class OccasionCollectionRepository<T> {
  OccasionCollectionRepository({
    required this.firestore,
    required this.collectionName,
    required this.fromSnapshot,
    required this.toFirestore,
    required this.validate,
  });

  final FirebaseFirestore firestore;
  final String collectionName;
  final T Function(DocumentSnapshot<Map<String, dynamic>> snapshot)
  fromSnapshot;
  final Map<String, dynamic> Function(T model) toFirestore;
  final void Function(T model) validate;

  CollectionReference<Map<String, dynamic>> get collection =>
      firestore.collection(collectionName);

  Future<String> create(T model, {String? documentId}) async {
    try {
      validate(model);
      final ref = documentId == null
          ? collection.doc()
          : collection.doc(documentId);
      final data = Map<String, dynamic>.from(toFirestore(model));
      data.putIfAbsent('id', () => ref.id);
      await ref.set(data);
      return ref.id;
    } catch (error) {
      throw OccasionFirestoreException(
        'Creation impossible dans $collectionName',
        error,
      );
    }
  }

  Future<void> set(String documentId, T model, {bool merge = true}) async {
    try {
      validate(model);
      final data = Map<String, dynamic>.from(toFirestore(model));
      data.putIfAbsent('id', () => documentId);
      await collection.doc(documentId).set(data, SetOptions(merge: merge));
    } catch (error) {
      throw OccasionFirestoreException(
        'Ecriture impossible dans $collectionName/$documentId',
        error,
      );
    }
  }

  Future<T?> get(String documentId) async {
    try {
      final snapshot = await collection.doc(documentId).get();
      if (!snapshot.exists) return null;
      return fromSnapshot(snapshot);
    } catch (error) {
      throw OccasionFirestoreException(
        'Lecture impossible dans $collectionName/$documentId',
        error,
      );
    }
  }

  Stream<T?> watch(String documentId) {
    return collection.doc(documentId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return fromSnapshot(snapshot);
    });
  }

  Future<void> updateFields(
    String documentId,
    Map<String, dynamic> fields,
  ) async {
    try {
      await collection.doc(documentId).update(fields);
    } catch (error) {
      throw OccasionFirestoreException(
        'Mise a jour impossible dans $collectionName/$documentId',
        error,
      );
    }
  }

  Future<void> delete(String documentId) async {
    try {
      await collection.doc(documentId).delete();
    } catch (error) {
      throw OccasionFirestoreException(
        'Suppression impossible dans $collectionName/$documentId',
        error,
      );
    }
  }
}

class AnnoncesCrudRepository extends OccasionCollectionRepository<Annonce> {
  AnnoncesCrudRepository(FirebaseFirestore firestore)
    : super(
        firestore: firestore,
        collectionName: 'annonces',
        fromSnapshot: (snapshot) =>
            Annonce.fromJson({...?snapshot.data(), 'id': snapshot.id}),
        toFirestore: (model) {
          final data = model.toJson();
          data['dateCreation'] = model.createdAt == null
              ? FieldValue.serverTimestamp()
              : Timestamp.fromDate(model.createdAt!);
          data['dateModification'] = FieldValue.serverTimestamp();
          return data;
        },
        validate: (model) => model.validate(),
      );

  Stream<List<Annonce>> activeByDate({String? categorie, int limit = 50}) {
    Query<Map<String, dynamic>> query = collection
        .where('status', isEqualTo: 'published')
        .orderBy('dateCreation', descending: true)
        .limit(limit);
    if (categorie != null && categorie.trim().isNotEmpty) {
      query = collection
          .where('status', isEqualTo: 'published')
          .where('categorie', isEqualTo: categorie.trim())
          .orderBy('dateCreation', descending: true)
          .limit(limit);
    }
    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => Annonce.fromJson({...doc.data(), 'id': doc.id}))
          .toList(),
    );
  }

  Future<void> incrementViews(String annonceId) {
    return updateFields(annonceId, {
      'vues': FieldValue.increment(1),
      'dateModification': FieldValue.serverTimestamp(),
    });
  }
}

class FavorisCrudRepository extends OccasionCollectionRepository<Favori> {
  FavorisCrudRepository(FirebaseFirestore firestore)
    : super(
        firestore: firestore,
        collectionName: 'favoris',
        fromSnapshot: (snapshot) =>
            Favori.fromJson({...?snapshot.data(), 'id': snapshot.id}),
        toFirestore: (model) => {
          ...model.toJson(),
          'dateAjout': FieldValue.serverTimestamp(),
        },
        validate: (model) => model.validate(),
      );

  Stream<List<Favori>> byUser(String utilisateurId, {int limit = 100}) {
    return collection
        .where('utilisateurId', isEqualTo: utilisateurId)
        .orderBy('dateAjout', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Favori.fromJson({...doc.data(), 'id': doc.id}))
              .toList(),
        );
  }
}

class UtilisateursOccasionRepository
    extends OccasionCollectionRepository<UtilisateurOccasion> {
  UtilisateursOccasionRepository(FirebaseFirestore firestore)
    : super(
        firestore: firestore,
        collectionName: 'utilisateurs',
        fromSnapshot: UtilisateurOccasion.fromSnapshot,
        toFirestore: (model) => model.toFirestore(serverTimestamps: true),
        validate: (model) => model.validate(),
      );
}

class MessagesOccasionRepository
    extends OccasionCollectionRepository<MessageOccasion> {
  MessagesOccasionRepository(FirebaseFirestore firestore)
    : super(
        firestore: firestore,
        collectionName: 'messages',
        fromSnapshot: MessageOccasion.fromSnapshot,
        toFirestore: (model) => model.toFirestore(serverTimestamp: true),
        validate: (model) => model.validate(),
      );

  Stream<List<MessageOccasion>> byConversation(
    String conversationId, {
    int limit = 100,
  }) {
    return collection
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('dateEnvoi', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(MessageOccasion.fromSnapshot).toList(),
        );
  }

  Future<void> markAsRead(String messageId) {
    return updateFields(messageId, {'lu': true});
  }
}

class ConversationsOccasionRepository
    extends OccasionCollectionRepository<ConversationOccasion> {
  ConversationsOccasionRepository(FirebaseFirestore firestore)
    : super(
        firestore: firestore,
        collectionName: 'conversations',
        fromSnapshot: ConversationOccasion.fromSnapshot,
        toFirestore: (model) => model.toFirestore(),
        validate: (model) => model.validate(),
      );

  Stream<List<ConversationOccasion>> byParticipant(
    String utilisateurId, {
    int limit = 50,
  }) {
    return collection
        .where('participants', arrayContains: utilisateurId)
        .orderBy('dateDernierMessage', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(ConversationOccasion.fromSnapshot).toList(),
        );
  }
}

class SignalementsOccasionRepository
    extends OccasionCollectionRepository<SignalementOccasion> {
  SignalementsOccasionRepository(FirebaseFirestore firestore)
    : super(
        firestore: firestore,
        collectionName: 'signalements',
        fromSnapshot: SignalementOccasion.fromSnapshot,
        toFirestore: (model) => model.toFirestore(serverTimestamp: true),
        validate: (model) => model.validate(),
      );

  Stream<List<SignalementOccasion>> byStatus(String statut, {int limit = 100}) {
    return collection
        .where('statut', isEqualTo: statut)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(SignalementOccasion.fromSnapshot).toList(),
        );
  }
}

class CategoriesOccasionRepository
    extends OccasionCollectionRepository<CategorieOccasion> {
  CategoriesOccasionRepository(FirebaseFirestore firestore)
    : super(
        firestore: firestore,
        collectionName: 'categories',
        fromSnapshot: CategorieOccasion.fromSnapshot,
        toFirestore: (model) => model.toFirestore(),
        validate: (model) => model.validate(),
      );

  Stream<List<CategorieOccasion>> ordered() {
    return collection
        .orderBy('ordre')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(CategorieOccasion.fromSnapshot).toList(),
        );
  }
}

class NotificationsOccasionRepository
    extends OccasionCollectionRepository<NotificationOccasion> {
  NotificationsOccasionRepository(FirebaseFirestore firestore)
    : super(
        firestore: firestore,
        collectionName: 'notifications',
        fromSnapshot: NotificationOccasion.fromSnapshot,
        toFirestore: (model) => model.toFirestore(serverTimestamp: true),
        validate: (model) => model.validate(),
      );

  Stream<List<NotificationOccasion>> byUser(
    String utilisateurId, {
    bool? unreadOnly,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = collection
        .where('utilisateurId', isEqualTo: utilisateurId)
        .orderBy('date', descending: true)
        .limit(limit);
    if (unreadOnly == true) {
      query = collection
          .where('utilisateurId', isEqualTo: utilisateurId)
          .where('lu', isEqualTo: false)
          .orderBy('date', descending: true)
          .limit(limit);
    }
    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map(NotificationOccasion.fromSnapshot).toList(),
    );
  }
}
