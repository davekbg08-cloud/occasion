import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../models/status.dart';
import 'image_compression_service.dart';
import 'seller_subscription_service.dart';
import 'video_compression_service.dart';

enum StatusUploadPhase { compressing, uploading }

class StatusUploadProgress {
  const StatusUploadProgress(this.phase, this.progress);

  final StatusUploadPhase phase;
  final double progress;
}

class StatusService {
  StatusService([
    this._firestore,
    this._storageOverride,
    this._functionsOverride,
  ]);

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storageOverride;
  // Résolu paresseusement (pas dans l'initializer list) pour ne jamais
  // toucher FirebaseFunctions.instance tant que toggleLike/deleteStatus ne
  // sont pas réellement appelés — évite de casser les tests qui
  // construisent ce service sans avoir initialisé Firebase.
  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  SellerSubscriptionService get _subscriptionService =>
      SellerSubscriptionService(firestore: _db);

  CollectionReference<Map<String, dynamic>> get _statuses {
    return _db.collection('statuses');
  }

  static const feedPageSize = 20;

  /// Première page du feed, en temps réel (les nouveaux statuts et les
  /// likes apparaissent immédiatement). Les pages suivantes sont chargées
  /// via [fetchMoreFeed], qui paginé avec un curseur Firestore plutôt que
  /// de tout charger d'un coup.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> feed({
    int pageSize = feedPageSize,
  }) {
    return _statuses
        .where('active', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map((snap) => snap.docs);
  }

  /// Page suivante du feed après le dernier document chargé. Ponctuelle
  /// (pas de flux temps réel) : suffisant pour du contenu déjà consulté.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchMoreFeed({
    required DocumentSnapshot<Map<String, dynamic>> after,
    int pageSize = feedPageSize,
  }) async {
    final snap = await _statuses
        .where('active', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(after)
        .limit(pageSize)
        .get();
    return snap.docs;
  }

  Stream<List<Status>> sellerStatuses(String sellerId) {
    return _statuses
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Status.fromMap({...doc.data(), 'id': doc.id}))
              .toList(),
        );
  }

  Future<void> createStatus({
    required String sellerId,
    required String sellerName,
    String? sellerProfileImageUrl,
    required XFile mediaFile,
    required StatusType type,
    String? caption,
    String? productId,
    void Function(StatusUploadProgress progress)? onProgress,
  }) async {
    final hasActiveSubscription = await _subscriptionService
        .hasActiveSubscription(sellerId);
    if (!hasActiveSubscription) {
      throw Exception(
        'Un abonnement vendeur actif est nécessaire pour publier un statut. '
        'Active ou renouvelle ton abonnement.',
      );
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = type == StatusType.video
        ? _storage.ref().child('annonces/$sellerId/statuses/$timestamp.mp4')
        : _storage.ref().child('annonces/$sellerId/statuses/$timestamp.jpg');

    if (type == StatusType.video) {
      if (kIsWeb) {
        // Pas de transcodage natif disponible sur le web : on applique
        // uniquement le plafond de taille, sans recompression.
        final videoBytes = await mediaFile.readAsBytes();
        if (videoBytes.lengthInBytes > VideoCompressionService.maxOutputBytes) {
          throw Exception('La vidéo doit faire moins de 12 Mo (30s max).');
        }
        final uploadTask = ref.putData(
          videoBytes,
          SettableMetadata(contentType: 'video/mp4'),
        );
        uploadTask.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes <= 0) return;
          onProgress?.call(
            StatusUploadProgress(
              StatusUploadPhase.uploading,
              snapshot.bytesTransferred / snapshot.totalBytes,
            ),
          );
        });
        await uploadTask;
      } else {
        final compressed = await VideoCompressionService.compress(
          mediaFile,
          onProgress: (progress) => onProgress?.call(
            StatusUploadProgress(StatusUploadPhase.compressing, progress),
          ),
        );
        final uploadTask = ref.putFile(
          compressed.file,
          SettableMetadata(
            contentType: 'video/mp4',
            customMetadata: {
              'originalSize': compressed.originalSize.toString(),
              'compressedSize': compressed.compressedSize.toString(),
            },
          ),
        );
        uploadTask.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes <= 0) return;
          onProgress?.call(
            StatusUploadProgress(
              StatusUploadPhase.uploading,
              snapshot.bytesTransferred / snapshot.totalBytes,
            ),
          );
        });
        await uploadTask;
      }
    } else {
      final compressed = await ImageCompressionService.compressXFile(
        mediaFile,
        maxWidth: 1080,
        quality: 75,
      );
      if (compressed.compressedSize > 2 * 1024 * 1024) {
        throw Exception("L'image reste trop lourde après compression.");
      }
      await ref.putData(
        compressed.bytes,
        SettableMetadata(
          contentType: compressed.contentType,
          customMetadata: {
            'originalSize': compressed.originalSize.toString(),
            'compressedSize': compressed.compressedSize.toString(),
            'width': compressed.width.toString(),
            'height': compressed.height.toString(),
          },
        ),
      );
    }
    final mediaUrl = await ref.getDownloadURL();

    final docRef = _statuses.doc();
    final status = Status(
      id: docRef.id,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerProfileImageUrl: sellerProfileImageUrl,
      mediaUrl: mediaUrl,
      type: type,
      caption: caption,
      productId: productId,
      status: 'published',
      active: true,
      createdAt: DateTime.now(),
    );

    await docRef.set(status.toMap());
  }

  /// Bascule le like côté serveur (transaction anti-double-like, voir
  /// `functions/index.js::toggleStatusLike`) — `likesCount` n'est plus
  /// modifiable directement par le client (`firestore.rules`).
  Future<bool> toggleLike(String statusId) async {
    final result = await _functions.httpsCallable('toggleStatusLike').call({
      'statusId': statusId,
    });
    return (result.data as Map)['liked'] as bool;
  }

  /// Identifiants des statuts déjà likés par [userId] (lecture ponctuelle,
  /// utilisée pour restaurer l'état "j'ai déjà aimé" après reconnexion —
  /// jamais persisté seulement en mémoire côté client).
  Future<Set<String>> likedStatusIds(String userId) async {
    final snap = await _db
        .collection('statusLikes')
        .where('userId', isEqualTo: userId)
        .get();
    return snap.docs
        .map((doc) => doc.data()['statusId'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Suppression côté serveur (voir `functions/index.js::deleteStatus`) :
  /// nettoie aussi le fichier Storage et les `statusLikes` associés, ce
  /// qu'une suppression Firestore directe ne ferait pas.
  Future<void> deleteStatus(String statusId) async {
    await _functions.httpsCallable('deleteStatus').call({'statusId': statusId});
  }
}
