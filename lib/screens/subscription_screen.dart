import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/subscription.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/payment_config.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? selectedPlan = 'seller_monthly';
  bool isProcessing = false;
  final TextEditingController referenceController = TextEditingController();

  final List<Map<String, Object>> plans = const [
    {
      'id': 'seller_monthly',
      'name': 'Vendeur Mensuel',
      'price': 20000,
      'duration': '1 mois',
      'benefit': 'Publication des annonces',
    },
  ];

  @override
  void dispose() {
    referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez une formule vendeur.')),
      );
      return;
    }
    final reference = referenceController.text.trim();
    if (reference.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Colle la référence de transaction reçue par SMS Orange Money.',
          ),
        ),
      );
      return;
    }

    final plan = plans.firstWhere((item) => item['id'] == selectedPlan);

    setState(() => isProcessing = true);
    try {
      await ref
          .read(subscriptionNotifierProvider.notifier)
          .submitManualSubscriptionPayment(
            planId: plan['id'] as String,
            planName: plan['name'] as String,
            price: (plan['price'] as num).toDouble(),
            manualPaymentReference: reference,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Merci ! Ton abonnement sera activé dès vérification du '
            'paiement (généralement rapide).',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      referenceController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyPaymentError(error)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    if (currentUser?.isBuyer == true) {
      return _buildBuyerFreeScaffold(context);
    }

    final subscription = ref.watch(subscriptionNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Abonnement vendeur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Vérifier mon abonnement',
            onPressed: () {
              ref
                  .read(subscriptionNotifierProvider.notifier)
                  .loadForUser(currentUser?.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Abonnement mis à jour automatiquement dès qu'un admin "
                    'confirme ton paiement.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subscription != null) ...[
              _buildCurrentSubscriptionCard(subscription),
              const SizedBox(height: 20),
              const Text(
                'Renouvellement vendeur',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const Text(
                'Abonnement vendeur',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Vous pouvez publier quelques annonces selon la configuration gratuite. L'abonnement vendeur servira aux volumes plus élevés et aux options avancées.",
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 16),
            ],
            ...plans.map(_buildPlanCard),
            const SizedBox(height: 20),
            Card(
              color: Colors.grey[900],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Comment payer',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Envoie le montant via Orange Money au numéro '
                      'ci-dessous.\n'
                      '2. Colle la référence de transaction reçue par SMS.\n'
                      "3. Ton abonnement s'active après vérification "
                      '(généralement rapide, pas instantané).',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            PaymentConfig.manualOrangeMoneyNumber,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          Text(
                            PaymentConfig.manualOrangeMoneyHolderName,
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: referenceController,
              enabled: !isProcessing,
              decoration: const InputDecoration(
                labelText: 'Référence de transaction (SMS Orange Money)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: isProcessing ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: isProcessing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        "J'AI ENVOYÉ L'ARGENT",
                        style: TextStyle(fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyPaymentError(Object error) {
    if (error is StateError) return error.message;
    if (error is ArgumentError) return error.message.toString();
    return 'Paiement impossible. Réessayez.';
  }

  Widget _buildBuyerFreeScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compte acheteur')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified_user,
                    color: Colors.green,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aucun abonnement pour les acheteurs',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Votre compte acheteur est gratuit. Vous ne payez pas d'abonnement mensuel.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text("Retour à l'accueil"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentSubscriptionCard(Subscription subscription) {
    final isActive = subscription.isActive && !subscription.isExpired;
    final statusColor = isActive ? Colors.green : Colors.red;

    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive ? Icons.verified : Icons.error_outline,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Abonnement ${subscription.planName}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Expire le : ${subscription.expiryDate.toString().split(' ').first}",
            ),
            const SizedBox(height: 8),
            Text(
              isActive ? 'Actif' : 'Expiré',
              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, Object> plan) {
    final planId = plan['id'] as String;
    final isSelected = selectedPlan == planId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        enabled: !isProcessing,
        leading: Icon(
          isSelected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          color: isSelected ? Colors.green : null,
        ),
        title: Text(
          plan['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text("${plan['duration']} - ${plan['benefit']}"),
        trailing: Text(
          "${plan['price']} FC",
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        onTap: isProcessing
            ? null
            : () => setState(() => selectedPlan = planId),
      ),
    );
  }
}
