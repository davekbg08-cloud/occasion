import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/status.dart';
import 'image_compression_service.dart';
import 'seller_subscription_service.dart';

class StatusService {
  StatusService([this._firestore, this._storageOverride]);

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storageOverride;

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
      final videoBytes = await mediaFile.readAsBytes();
      // Contenu éphémère limité à 60s côté sélection (add_status_screen) :
      // un plafond plus bas que les 50 Mo d'origine réduit le coût de
      // stockage/bande passante. Une vraie transcodification (ffmpeg côté
      // serveur) réduirait davantage mais dépasse la portée de ce correctif.
      if (videoBytes.lengthInBytes > 20 * 1024 * 1024) {
        throw Exception('La vidéo doit faire moins de 20 Mo (60s max).');
      }
      await ref.putData(
        videoBytes,
        SettableMetadata(contentType: 'video/mp4'),
      );
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

  Future<void> toggleLike(String statusId, {required bool liked}) async {
    await _statuses.doc(statusId).update({
      'likesCount': FieldValue.increment(liked ? 1 : -1),
    });
  }

  Future<void> deleteStatus(String statusId) async {
    await _statuses.doc(statusId).delete();
  }
}
