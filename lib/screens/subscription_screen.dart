import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/subscription.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/cinetpay_service.dart';
import '../services/service_locator.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? selectedPlan = 'seller_monthly';
  String? selectedOperator;
  bool isProcessing = false;

  final String subscriptionPhone = '0856373707';

  final List<Map<String, Object>> plans = const [
    {
      'id': 'seller_monthly',
      'name': 'Vendeur Mensuel',
      'price': 20000,
      'duration': '1 mois',
      'benefit': 'Publication des annonces',
    },
  ];

  final List<Map<String, Object>> operators = const [
    {'name': 'Orange Money', 'code': 'orange', 'color': Colors.orange},
    {'name': 'MTN Mobile Money', 'code': 'mtn', 'color': Colors.amber},
    {'name': 'Wave', 'code': 'wave', 'color': Colors.blue},
  ];

  Future<void> _subscribe() async {
    if (selectedPlan == null || selectedOperator == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez choisir un opérateur de paiement'),
        ),
      );
      return;
    }

    final plan = plans.firstWhere((item) => item['id'] == selectedPlan);
    final amount = plan['price'] as int;

    setState(() => isProcessing = true);

    try {
      final success = await getIt<CinetPayService>().initiatePayment(
        context: context,
        amount: amount.toDouble(),
        transactionId: 'sub_${DateTime.now().millisecondsSinceEpoch}',
        description: 'Abonnement vendeur mensuel',
        customerPhone: subscriptionPhone,
      );

      if (!mounted) return;

      if (success) {
        final startDate = DateTime.now();
        ref
            .read(subscriptionNotifierProvider.notifier)
            .activateSubscription(
              Subscription(
                id: 'sub_${startDate.millisecondsSinceEpoch}',
                planName: plan['name'] as String,
                price: amount.toDouble(),
                startDate: startDate,
                expiryDate: startDate.add(_subscriptionDuration),
                isActive: true,
                paymentMethod: selectedOperator!,
              ),
            );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Abonnement vendeur activé avec succès !"),
            backgroundColor: Colors.green,
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paiement refusé ou annulé'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Duration get _subscriptionDuration => const Duration(days: 30);

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    if (currentUser?.isBuyer == true) {
      return _buildBuyerFreeScaffold(context);
    }

    final subscription = ref.watch(subscriptionNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Abonnement vendeur')),
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
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: isProcessing ? null : _subscribe,
                  icon: const Icon(Icons.autorenew),
                  label: Text(
                    isProcessing
                        ? 'Paiement en cours...'
                        : 'Payer le renouvellement (${subscription.price.toInt()} FC)',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Formule vendeur',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const Text(
                'Abonnement vendeur',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Pour publier vos annonces sur Occasion, un abonnement vendeur est nécessaire.',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 16),
            ],
            ...plans.map(_buildPlanCard),
            const SizedBox(height: 24),
            const Text(
              'Paiement Mobile Money',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...operators.map(_buildOperatorCard),
            const SizedBox(height: 20),
            Card(
              color: Colors.grey[900],
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: Column(
                    children: [
                      Text('Numéro de paiement'),
                      Text(
                        '0856373707',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '(pré-rempli)',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: isProcessing ? null : _subscribe,
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
                        'PAYER 20000 FC',
                        style: TextStyle(fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildOperatorCard(Map<String, Object> operator) {
    final operatorCode = operator['code'] as String;
    final isSelected = selectedOperator == operatorCode;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        enabled: !isProcessing,
        leading: Icon(
          isSelected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          color: operator['color'] as Color,
        ),
        title: Text(operator['name'] as String),
        onTap: isProcessing
            ? null
            : () => setState(() => selectedOperator = operatorCode),
      ),
    );
  }
}
