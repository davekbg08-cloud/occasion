import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/payment_settlement_service.dart';

class AdminOrdersScreen extends StatelessWidget {
  const AdminOrdersScreen({super.key});

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
          title: const Text('Administration paiements'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'À vérifier'),
              Tab(text: 'À reverser'),
              Tab(text: 'Litiges'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PendingVerificationTab(),
            _ReadyForPayoutTab(),
            _DisputesTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Onglet 1 : paiements Orange Money manuels à vérifier.
// ---------------------------------------------------------------------
class _PendingVerificationTab extends StatefulWidget {
  const _PendingVerificationTab();

  @override
  State<_PendingVerificationTab> createState() =>
      _PendingVerificationTabState();
}

class _PendingVerificationTabState extends State<_PendingVerificationTab> {
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

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Accès refusé ou erreur.'));
        }
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('Aucun paiement à vérifier.'));
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
                            onPressed:
                                isBusy ? null : () => _reject(transactionId),
                            child: const Text('Rejeter'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                isBusy ? null : () => _confirm(transactionId),
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
                                : const Text('Confirmer'),
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
    );
  }

  DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

// ---------------------------------------------------------------------
// Onglet 2 : commandes "reçues par l'acheteur", en attente de
// reversement manuel au vendeur.
// ---------------------------------------------------------------------
class _ReadyForPayoutTab extends StatefulWidget {
  const _ReadyForPayoutTab();

  @override
  State<_ReadyForPayoutTab> createState() => _ReadyForPayoutTabState();
}

class _ReadyForPayoutTabState extends State<_ReadyForPayoutTab> {
  final Set<String> _processing = {};

  Future<void> _markPaidOut(String orderId) async {
    setState(() => _processing.add(orderId));
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
        'status': 'payout_sent',
        'payoutSentAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marqué comme reversé.'),
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
      if (mounted) setState(() => _processing.remove(orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('orders')
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: false)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Accès refusé ou erreur.'));
        }
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('Aucun reversement en attente.'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final orderId = docs[index].id;
            final isBusy = _processing.contains(orderId);
            final total = (data['total'] as num?)?.toDouble() ?? 0;
            final buyerName = data['buyerName'] as String? ?? 'Acheteur';
            final sellerIds =
                (data['sellerIds'] as List<dynamic>? ?? const []).join(', ');

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${total.toInt()} FC · acheteur $buyerName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vendeur(s) : $sellerIds',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isBusy ? null : () => _markPaidOut(orderId),
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
                            : const Text(
                                "J'ai envoyé l'argent au vendeur",
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Onglet 3 : litiges signalés par des acheteurs.
// ---------------------------------------------------------------------
class _DisputesTab extends StatefulWidget {
  const _DisputesTab();

  @override
  State<_DisputesTab> createState() => _DisputesTabState();
}

class _DisputesTabState extends State<_DisputesTab> {
  final Set<String> _processing = {};

  Future<void> _resolve(String orderId, String newStatus) async {
    setState(() => _processing.add(orderId));
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'completed'
                ? 'Litige résolu : reversement au vendeur autorisé.'
                : 'Litige résolu : commande annulée.',
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
      if (mounted) setState(() => _processing.remove(orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('orders')
        .where('status', isEqualTo: 'disputed')
        .orderBy('disputedAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Accès refusé ou erreur.'));
        }
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('Aucun litige en cours.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final orderId = docs[index].id;
            final isBusy = _processing.contains(orderId);
            final total = (data['total'] as num?)?.toDouble() ?? 0;
            final buyerName = data['buyerName'] as String? ?? 'Acheteur';
            final reason = data['disputeReason'] as String? ?? '';

            return Card(
              color: Colors.red.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${total.toInt()} FC · $buyerName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(reason),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isBusy
                                ? null
                                : () => _resolve(orderId, 'cancelled'),
                            child: const Text('Annuler / rembourser'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: isBusy
                                ? null
                                : () => _resolve(orderId, 'completed'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text('Reverser au vendeur'),
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
    );
  }
}
