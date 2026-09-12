import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/search_alert.dart';

class SearchAlertService {
  SearchAlertService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection('searchAlerts');

  Future<void> create({
    required String userId,
    String keyword = '',
    String city = '',
    String category = '',
  }) async {
    if (userId.trim().isEmpty) {
      throw Exception('Utilisateur non connecté.');
    }
    final docRef = _ref.doc();
    final alert = SearchAlert(
      id: docRef.id,
      userId: userId,
      keyword: keyword,
      city: city,
      category: category,
    );
    await docRef.set({
      ...alert.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String alertId) => _ref.doc(alertId).delete();

  Stream<List<SearchAlert>> watchForUser(String userId) {
    if (userId.trim().isEmpty) return Stream.value(const []);
    return _ref
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SearchAlert.fromJson({...doc.data(), 'id': doc.id}))
              .toList(),
        );
  }
}
