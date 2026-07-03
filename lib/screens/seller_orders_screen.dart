import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';

class SellerOrdersScreen extends ConsumerWidget {
  const SellerOrdersScreen({super.key});

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
        .where('sellerIds', arrayContains: user.id)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Commandes reçues')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Occasion garde le paiement de l'acheteur en sécurité "
                    "et te le reverse dès que l'acheteur confirme avoir "
                    "reçu l'article (ou automatiquement sous 3 jours). Tu "
                    "es protégé : l'argent est déjà là, il ne peut pas se "
                    "rétracter après paiement confirmé.",
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ordersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Impossible de charger les commandes.'),
                  );
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Aucune commande reçue pour le moment.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final status = data['status'] as String? ?? '';
                    final total = (data['total'] as num?)?.toDouble() ?? 0;
                    final buyerName = data['buyerName'] as String? ?? 'Acheteur';
                    final date = _toDate(data['createdAt']);

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
                                    buyerName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _statusBadge(status),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${total.toInt()} FC'),
                            if (date != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('dd/MM/yyyy HH:mm').format(date),
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = switch (status) {
      'paid' => Colors.blue,
      'completed' => Colors.amber,
      'payout_sent' => Colors.green,
      'disputed' => Colors.red,
      _ => Colors.grey,
    };
    final label = switch (status) {
      'paid' => "Payée · à livrer",
      'completed' => 'Livrée · reversement en attente',
      'payout_sent' => 'Reversée',
      'disputed' => 'Litige',
      _ => status,
    };
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
    );
  }

  DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
