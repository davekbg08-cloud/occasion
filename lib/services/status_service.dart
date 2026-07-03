import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/status.dart';
import 'image_compression_service.dart';

class StatusService {
  StatusService([this._firestore, this._storageOverride]);

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storageOverride;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _statuses {
    return _db.collection('statuses');
  }

  Stream<List<Status>> feed() {
    return _statuses
        .where('active', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Status.fromMap({...doc.data(), 'id': doc.id}))
              .toList(),
        );
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
    required File mediaFile,
    required StatusType type,
    String? caption,
    String? productId,
  }) async {
    if (type == StatusType.video &&
        await mediaFile.length() > 50 * 1024 * 1024) {
      throw Exception('La vidéo doit faire moins de 50 Mo.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = type == StatusType.video
        ? _storage.ref().child('annonces/$sellerId/statuses/$timestamp.mp4')
        : _storage.ref().child('annonces/$sellerId/statuses/$timestamp.jpg');
    if (type == StatusType.video) {
      await ref.putFile(mediaFile, SettableMetadata(contentType: 'video/mp4'));
    } else {
      final compressed = ImageCompressionService.compressBytes(
        await mediaFile.readAsBytes(),
      );
      if (compressed.compressedSize > 5 * 1024 * 1024) {
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
