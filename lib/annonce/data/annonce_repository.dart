import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/annonce.dart';

abstract class AnnonceRepository {
  Future<Annonce> createAnnonce(Annonce annonce, List<XFile> images);
  Future<List<Annonce>> getAnnonces({String? search, String? category});
  Future<Annonce> updateAnnonce(Annonce annonce);
  Future<void> deleteAnnonce(String id);
}

class AnnonceRepositoryImpl implements AnnonceRepository {
  AnnonceRepositoryImpl({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    firebase_auth.FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? firebase_auth.FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final firebase_auth.FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _annoncesRef =>
      _firestore.collection('annonces');

  @override
  Future<Annonce> createAnnonce(Annonce annonce, List<XFile> images) async {
    final currentUser = _auth.currentUser;
    final userId = currentUser?.uid ?? annonce.userId;

    if (userId.trim().isEmpty || userId == 'current_user') {
      throw Exception('Utilisateur non connecté. Connecte-toi avant de publier.');
    }

    final docRef = _annoncesRef.doc();
    final imageUrls = await _uploadImages(annonceId: docRef.id, images: images);

    final data = annonce
        .copyWith(
          id: docRef.id,
          userId: userId,
          imageUrls: imageUrls,
          isActive: true,
          views: 0,
          favoritesCount: 0,
        )
        .toJson();

    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();

    await docRef.set(data);

    final snapshot = await docRef.get();
    return _fromFirestore(snapshot);
  }

  @override
  Future<List<Annonce>> getAnnonces({String? search, String? category}) async {
    Query<Map<String, dynamic>> query = _annoncesRef
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true);

    if (category != null && category.trim().isNotEmpty) {
      query = query.where('category', isEqualTo: category.trim());
    }

    final snapshot = await query.get();
    var annonces = snapshot.docs.map(_fromFirestore).toList();

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
  Future<Annonce> updateAnnonce(Annonce annonce) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != annonce.userId) {
      throw Exception('Tu ne peux modifier que tes propres annonces.');
    }

    final data = annonce.toJson();
    data['updatedAt'] = FieldValue.serverTimestamp();

    await _annoncesRef.doc(annonce.id).update(data);
    final snapshot = await _annoncesRef.doc(annonce.id).get();
    return _fromFirestore(snapshot);
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

    await _annoncesRef.doc(id).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<String>> _uploadImages({
    required String annonceId,
    required List<XFile> images,
  }) async {
    final urls = <String>[];

    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      final extension = image.name.split('.').last.toLowerCase();
      final fileName = 'image_${index + 1}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final ref = _storage.ref().child('annonces/$annonceId/$fileName');
      final bytes = await image.readAsBytes();

      await ref.putData(
        bytes,
        SettableMetadata(contentType: _contentType(extension)),
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

  String _contentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
