import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/image_compression_service.dart';
import '../../services/seller_subscription_service.dart';
import '../../shared/models/annonce.dart';

abstract class AnnonceRepository {
  Future<Annonce> createAnnonce(Annonce annonce, List<XFile> images);
  Future<List<Annonce>> getAnnonces({String? search, String? category});
  Future<List<Annonce>> getSellerAnnonces(String sellerId);
  Future<Annonce> updateAnnonce(Annonce annonce, {List<XFile> newImages});
  Future<Annonce> updateAnnonceStatus(Annonce annonce, String status);
  Future<void> deleteAnnonce(String id);
  Future<void> incrementViews(String id);
  Future<Annonce?> getAnnonceById(String id);
}

class AnnonceRepositoryImpl implements AnnonceRepository {
  AnnonceRepositoryImpl({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    firebase_auth.FirebaseAuth? auth,
    SellerSubscriptionService? subscriptionService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? firebase_auth.FirebaseAuth.instance,
       _subscriptionService =
           subscriptionService ??
           SellerSubscriptionService(firestore: firestore);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final firebase_auth.FirebaseAuth _auth;
  final SellerSubscriptionService _subscriptionService;

  CollectionReference<Map<String, dynamic>> get _annoncesRef =>
      _firestore.collection('annonces');

  static const _freeMaxActiveAnnonces = 1;
  static const _freeMaxImages = 2;
  static const _sellerMaxImages = 5;

  @override
  Future<Annonce> createAnnonce(Annonce annonce, List<XFile> images) async {
    final currentUser = _auth.currentUser;
    final userId = currentUser?.uid ?? annonce.userId;

    if (userId.trim().isEmpty || userId == 'current_user') {
      throw Exception(
        'Utilisateur non connecté. Connecte-toi avant de publier.',
      );
    }

    if (images.isEmpty) {
      throw Exception('Ajoutez au moins une photo avant de publier.');
    }

    final hasSellerSubscription = await _subscriptionService
        .hasActiveSubscription(userId);
    final maxImages = hasSellerSubscription ? _sellerMaxImages : _freeMaxImages;
    if (images.length > maxImages) {
      throw Exception(
        hasSellerSubscription
            ? 'La formule vendeur permet jusqu’à 5 photos par annonce.'
            : 'La formule gratuite permet jusqu’à 2 photos par annonce.',
      );
    }

    final wantsPublished =
        _isPublishedStatus(annonce.status) || annonce.isActive;
    if (!hasSellerSubscription && wantsPublished) {
      final activeCount = await _activeAnnonceCount(userId);
      if (activeCount >= _freeMaxActiveAnnonces) {
        throw Exception(
          'La formule gratuite permet 1 annonce active maximum. Désactivez une annonce ou activez la formule vendeur.',
        );
      }
    }

    final docRef = _annoncesRef.doc();
    final imageUrls = await _uploadImages(
      sellerId: userId,
      annonceId: docRef.id,
      images: images,
      maxImages: maxImages,
    );
    final normalizedStatus = _normalizedStatus(
      annonce.status,
      annonce.isActive,
    );
    final isPublished = _isPublishedStatus(normalizedStatus);

    final prepared = annonce.copyWith(
      id: docRef.id,
      userId: userId,
      imageUrls: imageUrls,
      isActive: isPublished,
      status: normalizedStatus,
      views: 0,
      favoritesCount: 0,
    );
    prepared.validate();

    final data = prepared.toJson();

    data['dateCreation'] = FieldValue.serverTimestamp();
    data['dateModification'] = FieldValue.serverTimestamp();

    await docRef.set(data);

    final snapshot = await docRef.get();
    return _fromFirestore(snapshot);
  }

  @override
  Future<List<Annonce>> getAnnonces({String? search, String? category}) async {
    Query<Map<String, dynamic>> query = _annoncesRef
        .where('isPublished', isEqualTo: true)
        .orderBy('dateCreation', descending: true);

    if (category != null && category.trim().isNotEmpty) {
      query = query.where('categorie', isEqualTo: category.trim());
    }

    final snapshot = await query.get();
    var annonces = snapshot.docs
        .map(_fromFirestore)
        .where(
          (annonce) => annonce.isActive && _isPublishedStatus(annonce.status),
        )
        .toList();

    if (search != null && search.trim().isNotEmpty) {
      final keyword = search.trim().toLowerCase();
      annonces = annonces.where((annonce) {
        final location = annonce.location?.toLowerCase() ?? '';
        return annonce.title.toLowerCase().contains(keyword) ||
            annonce.description.toLowerCase().contains(keyword) ||
            annonce.category.toLowerCase().contains(keyword) ||
            location.contains(keyword);
      }).toList();
    }

    return annonces;
  }

  @override
  Future<List<Annonce>> getSellerAnnonces(String sellerId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != sellerId) {
      throw Exception('Connecte-toi avec ton compte vendeur.');
    }

    final snapshot = await _annoncesRef
        .where('vendeurId', isEqualTo: sellerId)
        .get();
    final annonces = snapshot.docs.map(_fromFirestore).toList();
    annonces.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return annonces;
  }

  @override
  Future<Annonce> updateAnnonce(
    Annonce annonce, {
    List<XFile> newImages = const [],
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != annonce.userId) {
      throw Exception('Tu ne peux modifier que tes propres annonces.');
    }

    var updated = annonce;
    if (newImages.isNotEmpty) {
      final hasSellerSubscription = await _subscriptionService
          .hasActiveSubscription(annonce.userId);
      final maxImages = hasSellerSubscription
          ? _sellerMaxImages
          : _freeMaxImages;
      if (newImages.length > maxImages) {
        throw Exception(
          hasSellerSubscription
              ? 'La formule vendeur permet jusqu’à 5 photos par annonce.'
              : 'La formule gratuite permet jusqu’à 2 photos par annonce.',
        );
      }
      final imageUrls = await _uploadImages(
        sellerId: annonce.userId,
        annonceId: annonce.id,
        images: newImages,
        maxImages: maxImages,
      );
      updated = annonce.copyWith(imageUrls: imageUrls);
    }

    final data = updated.toJson();
    data['dateModification'] = FieldValue.serverTimestamp();

    await _annoncesRef.doc(updated.id).update(data);
    final snapshot = await _annoncesRef.doc(updated.id).get();
    return _fromFirestore(snapshot);
  }

  @override
  Future<Annonce> updateAnnonceStatus(Annonce annonce, String status) {
    return updateAnnonce(
      annonce.copyWith(
        status: status,
        isActive:
            status == 'published' || status == 'active' || status == 'actif',
      ),
    );
  }

  @override
  Future<void> deleteAnnonce(String id) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Utilisateur non connecté.');
    }

    final snapshot = await _annoncesRef.doc(id).get();
    final annonce = _fromFirestore(snapshot);
    if (annonce.userId != currentUser.uid) {
      throw Exception('Tu ne peux supprimer que tes propres annonces.');
    }

    for (final url in annonce.imageUrls) {
      try {
        await _storage.refFromURL(url).delete();
      } catch (error) {
        developer.log(
          'Suppression photo Storage échouée pour $url: $error',
          name: 'AnnonceRepositoryImpl.deleteAnnonce',
        );
      }
    }

    await _annoncesRef.doc(id).delete();
  }

  @override
  Future<void> incrementViews(String id) {
    return _annoncesRef.doc(id).update({'vues': FieldValue.increment(1)});
  }

  @override
  Future<Annonce?> getAnnonceById(String id) async {
    final snapshot = await _annoncesRef.doc(id).get();
    if (!snapshot.exists) return null;
    return _fromFirestore(snapshot);
  }

  Future<List<String>> _uploadImages({
    required String sellerId,
    required String annonceId,
    required List<XFile> images,
    required int maxImages,
  }) async {
    if (images.length > maxImages) {
      throw Exception('Maximum $maxImages photos par annonce.');
    }

    final urls = <String>[];

    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      final compressed = await ImageCompressionService.compressXFile(
        image,
        maxWidth: ImageCompressionService.defaultMaxWidth,
        quality: ImageCompressionService.defaultQuality,
      );

      final fileName =
          'image_${index + 1}_${DateTime.now().millisecondsSinceEpoch}.${compressed.extension}';
      final ref = _storage.ref().child(
        'annonces/$sellerId/$annonceId/$fileName',
      );
      if (compressed.bytes.length > 5 * 1024 * 1024) {
        throw Exception(
          'Une photo reste trop lourde après compression. Choisissez une image plus légère.',
        );
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
      developer.log(
        'Image annonce compressee ${compressed.originalSize} -> ${compressed.compressedSize} octets',
        name: 'AnnonceRepositoryImpl._uploadImages',
      );
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  Annonce _fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) throw Exception('Annonce introuvable');
    return Annonce.fromJson({...data, 'id': snapshot.id});
  }

  Future<int> _activeAnnonceCount(String userId) async {
    final snapshot = await _annoncesRef
        .where('vendeurId', isEqualTo: userId)
        .where('isPublished', isEqualTo: true)
        .get();

    return snapshot.docs
        .map(_fromFirestore)
        .where(
          (annonce) => annonce.isActive && _isPublishedStatus(annonce.status),
        )
        .length;
  }

  String _normalizedStatus(String status, bool isActive) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'draft' || normalized == 'pending') return normalized;
    if (normalized == 'active' || normalized == 'actif') return 'published';
    if (normalized == 'published' || normalized == 'publie') return 'published';
    return isActive ? 'published' : 'draft';
  }

  bool _isPublishedStatus(String status) {
    return const {
      'published',
      'active',
      'actif',
      'publie',
    }.contains(status.trim().toLowerCase());
  }

}
