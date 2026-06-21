import 'package:cloud_firestore/cloud_firestore.dart';

enum ReportTargetType { user, product, status, message }

enum ReportReason {
  spam,
  scam,
  inappropriateContent,
  offensiveBehavior,
  fakeProduct,
  other,
}

const Map<ReportReason, String> reportReasonLabels = {
  ReportReason.spam: 'Spam ou publicite',
  ReportReason.scam: 'Arnaque ou fraude',
  ReportReason.inappropriateContent: 'Contenu inapproprie',
  ReportReason.offensiveBehavior: 'Comportement offensant',
  ReportReason.fakeProduct: 'Faux produit / annonce trompeuse',
  ReportReason.other: 'Autre',
};

class Report {
  Report({
    required this.id,
    required this.reporterId,
    required this.targetId,
    required this.targetType,
    required this.reason,
    this.details,
    this.status = 'pending',
    required this.createdAt,
  });

  final String id;
  final String reporterId;
  final String targetId;
  final ReportTargetType targetType;
  final ReportReason reason;
  final String? details;
  final String status;
  final DateTime createdAt;

  factory Report.fromMap(Map<String, dynamic> map) {
    return Report(
      id: map['id'] as String? ?? '',
      reporterId: map['reporterId'] as String? ?? '',
      targetId: map['targetId'] as String? ?? '',
      targetType: ReportTargetType.values.firstWhere(
        (item) => item.name == map['targetType'],
        orElse: () => ReportTargetType.user,
      ),
      reason: ReportReason.values.firstWhere(
        (item) => item.name == map['reason'],
        orElse: () => ReportReason.other,
      ),
      details: map['details'] as String?,
      status: map['status'] as String? ?? 'pending',
      createdAt: _dateFromFirestore(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'reporterId': reporterId,
    'targetId': targetId,
    'targetType': targetType.name,
    'reason': reason.name,
    'details': details,
    'status': status,
  };
}

DateTime _dateFromFirestore(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  return DateTime.fromMillisecondsSinceEpoch(0);
}
