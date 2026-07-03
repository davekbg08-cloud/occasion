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
              return _OrderCard(orderId: docs[index].id, data: docs[index].data());
            },
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({required this.orderId, required this.data});

  final String orderId;
  final Map<String, dynamic> data;

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool isProcessing = false;

  Future<void> _confirmReceived() async {
    setState(() => isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .set({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merci ! Le vendeur va être payé.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec de la confirmation. Réessaie.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _reportProblem() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signaler un problème'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText:
                "Décris le problème (article non reçu, différent de l'annonce...)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(reasonController.text.trim()),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;

    setState(() => isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .set({
            'status': 'disputed',
            'disputeReason': reason,
            'disputedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Signalement envoyé. Ton argent reste protégé le temps que ce '
            'soit examiné.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Échec du signalement. Réessaie.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final status = data['status'] as String? ?? 'pending_payment';
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
            if (status == 'paid') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Ton argent est en sécurité chez Occasion. Il ne sera "
                        "remis au vendeur qu'après ta confirmation (ou "
                        "automatiquement sous 3 jours si tout va bien).",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isProcessing ? null : _reportProblem,
                      child: const Text('Signaler un problème'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: isProcessing ? null : _confirmReceived,
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      child: isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Bien reçu'),
                    ),
                  ),
                ],
              ),
            ],
            if (status == 'disputed') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Ton signalement est en cours d'examen. Ton argent reste "
                  "protégé, il ne sera pas versé au vendeur tant que ce "
                  "n'est pas résolu.",
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
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
      'paid' => Colors.blue,
      'completed' || 'payout_sent' => Colors.green,
      'cancelled' || 'payment_failed' || 'disputed' => Colors.red,
      'awaiting_manual_verification' => Colors.amber,
      _ => Colors.orange,
    };
    final label = switch (status) {
      'paid' => 'Payée · en séquestre',
      'completed' => 'Reçue, en attente de reversement',
      'payout_sent' => 'Terminée',
      'cancelled' => 'Annulée',
      'payment_failed' => 'Paiement échoué',
      'disputed' => 'Litige en cours',
      'processing_payment' => 'Confirmation en cours',
      'awaiting_manual_verification' => 'Vérification Orange Money en cours',
      _ => 'En attente de paiement',
    };

    return Chip(
      avatar: Icon(Icons.circle, color: color, size: 10),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
