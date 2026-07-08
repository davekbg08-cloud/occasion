import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/report.dart';
import '../providers/moderation_provider.dart';

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/profile'),
          ),
          title: const Text('Signalements'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'À traiter'),
              Tab(text: 'Résolus'),
              Tab(text: 'Rejetés'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ReportsTab(status: 'pending'),
            _ReportsTab(status: 'resolved'),
            _ReportsTab(status: 'dismissed'),
          ],
        ),
      ),
    );
  }
}

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab({required this.status});

  final String status;

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  final Set<String> _processing = {};

  Future<void> _updateStatus(String reportId, String newStatus) async {
    setState(() => _processing.add(reportId));
    try {
      await ref
          .read(moderationServiceProvider)
          .updateReportStatus(
            reportId: reportId,
            status: newStatus,
            reviewedBy: FirebaseAuth.instance.currentUser?.uid,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'resolved' ? 'Signalement résolu.' : 'Signalement rejeté.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec. Réessaie.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing.remove(reportId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ref
          .read(moderationServiceProvider)
          .reportsStream(status: widget.status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Accès refusé ou erreur.'));
        }
        final docs = snapshot.data ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('Aucun signalement ici.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index];
            final reportId = data['id'] as String;
            final isBusy = _processing.contains(reportId);
            final targetType = data['targetType'] as String? ?? 'user';
            final reasonKey = data['reason'] as String?;
            final reason = ReportReason.values
                .firstWhere(
                  (item) => item.name == reasonKey,
                  orElse: () => ReportReason.other,
                );
            final details = data['details'] as String?;
            final date = _toDate(data['createdAt']);

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.flag_outlined,
                          size: 18,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Cible : $targetType',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(reportReasonLabels[reason] ?? 'Autre'),
                    if (details != null && details.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(details, style: TextStyle(color: Colors.grey[400])),
                    ],
                    if (date != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(date),
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                    if (widget.status == 'pending') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isBusy
                                  ? null
                                  : () => _updateStatus(reportId, 'dismissed'),
                              child: const Text('Rejeter'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: isBusy
                                  ? null
                                  : () => _updateStatus(reportId, 'resolved'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              child: isBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Résoudre'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  DateTime? _toDate(Object? value) {
    try {
      final dynamic dynamicValue = value;
      final converted = dynamicValue?.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Ignore, laisse la date vide.
    }
    return null;
  }
}
