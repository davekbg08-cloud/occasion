import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/payment_settlement_service.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final _settlement = PaymentSettlementService();
  final Set<String> _processing = {};

  Future<void> _confirm(String transactionId) async {
    setState(() => _processing.add(transactionId));
    try {
      await _settlement.confirmManualPayment(transactionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paiement confirmé.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec de la confirmation.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing.remove(transactionId));
    }
  }

  Future<void> _reject(String transactionId) async {
    setState(() => _processing.add(transactionId));
    try {
      await _settlement.rejectManualPayment(transactionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paiement rejeté.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec du rejet.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing.remove(transactionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('paymentIntents')
        .where('status', isEqualTo: 'awaiting_manual_verification')
        .orderBy('updatedAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/profile'),
        ),
        title: const Text('Paiements Orange Money à vérifier'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('Accès refusé ou erreur de chargement.'),
            );
          }
          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('Aucun paiement en attente de vérification.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final transactionId = docs[index].id;
              final isBusy = _processing.contains(transactionId);
              final type = data['type'] as String? ?? 'order';
              final amount = (data['amount'] as num?)?.toDouble() ?? 0;
              final reference = data['manualPaymentReference'] as String?;
              final planName = data['planName'] as String?;
              final date = _toDate(data['updatedAt']);

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            type == 'subscription'
                                ? Icons.storefront_outlined
                                : Icons.shopping_bag_outlined,
                            size: 18,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            type == 'subscription'
                                ? 'Abonnement vendeur${planName != null ? " · $planName" : ""}'
                                : 'Commande',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${amount.toInt()} FC'),
                      const SizedBox(height: 4),
                      Text('Référence : ${reference ?? "non fournie"}'),
                      if (date != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(date),
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isBusy
                                  ? null
                                  : () => _reject(transactionId),
                              child: const Text('Rejeter'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: isBusy
                                  ? null
                                  : () => _confirm(transactionId),
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
                                  : const Text('Confirmer le paiement'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
