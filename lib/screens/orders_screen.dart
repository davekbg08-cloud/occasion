import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Connecte-toi pour voir tes commandes.')),
      );
    }

    final ordersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('buyerId', isEqualTo: user.id)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Mes commandes')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ordersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Impossible de charger les commandes pour le moment.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(child: Text('Aucune commande pour le moment.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _OrderCard(data: docs[index].data());
            },
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final total = (data['total'] as num?)?.toDouble() ?? 0;
    final date = _toDate(data['createdAt']);
    final items = data['items'] as List<dynamic>? ?? const [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Commande ${data['id'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              date == null
                  ? '${total.toInt()} FC'
                  : '${total.toInt()} FC - ${DateFormat('dd/MM/yyyy HH:mm').format(date)}',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 10),
            ...items.map((item) {
              final map = item as Map<String, dynamic>? ?? const {};
              final quantity = map['quantity'] as int? ?? 1;
              final name = map['name'] as String? ?? 'Article';
              final lineTotal = (map['totalPrice'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('$name x$quantity')),
                    Text('${lineTotal.toInt()} FC'),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  DateTime? _toDate(Object? value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    return null;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'paid' => Colors.green,
      'cancelled' || 'payment_failed' => Colors.red,
      _ => Colors.orange,
    };
    final label = switch (status) {
      'paid' => 'Payée',
      'cancelled' => 'Annulée',
      'payment_failed' => 'Paiement échoué',
      'processing_payment' => 'Confirmation en cours',
      _ => 'En attente de paiement',
    };

    return Chip(
      avatar: Icon(Icons.circle, color: color, size: 10),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
