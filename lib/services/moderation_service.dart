import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/report.dart';

class ModerationService {
  ModerationService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _reportsRef =>
      _db.collection('reports');

  CollectionReference<Map<String, dynamic>> _blockedRef(String userId) {
    return _db.collection('users').doc(userId).collection('blockedUsers');
  }

  Future<void> submitReport({
    required String reporterId,
    required String targetId,
    required ReportTargetType targetType,
    required ReportReason reason,
    String? details,
  }) async {
    await _reportsRef.add({
      'reporterId': reporterId,
      'targetId': targetId,
      'targetType': targetType.name,
      'reason': reason.name,
      'details': details,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> blockUser({
    required String currentUserId,
    required String blockedUserId,
    required String blockedUserName,
  }) async {
    await _blockedRef(currentUserId).doc(blockedUserId).set({
      'userId': blockedUserId,
      'userName': blockedUserName,
      'blockedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockUser({
    required String currentUserId,
    required String blockedUserId,
  }) async {
    await _blockedRef(currentUserId).doc(blockedUserId).delete();
  }

  Stream<Set<String>> blockedUserIds(String currentUserId) {
    return _blockedRef(
      currentUserId,
    ).snapshots().map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  Stream<List<Map<String, dynamic>>> blockedUsersDetailed(
    String currentUserId,
  ) {
    return _blockedRef(currentUserId)
        .orderBy('blockedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }
}
