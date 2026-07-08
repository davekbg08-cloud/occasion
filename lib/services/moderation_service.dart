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

  /// ID déterministe : un même utilisateur ne peut signaler une même cible
  /// qu'une fois (retenter est rejeté par les règles Firestore, qui
  /// interdisent la mise à jour d'un rapport existant par un non-admin).
  Future<void> submitReport({
    required String reporterId,
    required String targetId,
    required ReportTargetType targetType,
    required ReportReason reason,
    String? details,
  }) async {
    final id = '${reporterId}_${targetType.name}_$targetId';
    await _reportsRef.doc(id).set({
      'reporterId': reporterId,
      'targetId': targetId,
      'targetType': targetType.name,
      'reason': reason.name,
      'details': details,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Réservé aux admins (voir firestore.rules) : liste des signalements,
  /// filtrés par statut si précisé.
  Stream<List<Map<String, dynamic>>> reportsStream({String? status}) {
    Query<Map<String, dynamic>> query = _reportsRef.orderBy(
      'createdAt',
      descending: true,
    );
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList(),
    );
  }

  Future<void> updateReportStatus({
    required String reportId,
    required String status,
    String? reviewedBy,
  }) {
    return _reportsRef.doc(reportId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (reviewedBy != null) 'reviewedBy': reviewedBy,
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
