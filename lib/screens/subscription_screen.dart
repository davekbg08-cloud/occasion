import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/subscription.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? selectedPlan = 'seller_monthly';
  String? selectedOperator = 'orange';
  bool simulateSuccess = true;
  bool isProcessing = false;

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
    {'name': 'Airtel Money', 'code': 'airtel', 'color': Colors.red},
    {'name': 'M-Pesa', 'code': 'mpesa', 'color': Colors.green},
    {'name': 'Wave', 'code': 'wave', 'color': Colors.blue},
    {'name': 'CinetPay', 'code': 'cinetpay', 'color': Colors.blueGrey},
  ];

  Future<void> _subscribe() async {
    if (selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez une formule vendeur.')),
      );
      return;
    }
    if (selectedOperator == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un prestataire de paiement.')),
      );
      return;
    }

    final plan = plans.firstWhere((item) => item['id'] == selectedPlan);
    final operator = operators.firstWhere(
      (item) => item['code'] == selectedOperator,
    );

    setState(() => isProcessing = true);

    try {
      final subscription = await ref
          .read(subscriptionNotifierProvider.notifier)
          .simulateSellerPayment(
            planId: plan['id'] as String,
            planName: plan['name'] as String,
            price: (plan['price'] as num).toDouble(),
            paymentMethod: operator['name'] as String,
            shouldSucceed: simulateSuccess,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Paiement simulé confirmé. Abonnement actif jusqu'au ${subscription.expiryDate.toString().split(' ').first}.",
          ),
          backgroundColor: Colors.green,
        ),
      );
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
                        ? 'Mode test...'
                        : 'Tester le renouvellement (${subscription.price.toInt()} FC)',
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
                "Vous pouvez publier quelques annonces selon la configuration gratuite. L'abonnement vendeur servira aux volumes plus élevés et aux options avancées.",
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 16),
            ],
            _buildExplanationCard(),
            const SizedBox(height: 16),
            ...plans.map(_buildPlanCard),
            const SizedBox(height: 24),
            const Text(
              'Opérateur de paiement',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...operators.map(_buildOperatorCard),
            const SizedBox(height: 20),
            Card(
              color: Colors.grey[900],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Text('Mode simulation'),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.check_circle_outline),
                          label: Text('Réussi'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.cancel_outlined),
                          label: Text('Échoué'),
                        ),
                      ],
                      selected: {simulateSuccess},
                      onSelectionChanged: isProcessing
                          ? null
                          : (values) =>
                                setState(() => simulateSuccess = values.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Aucun débit réel n'est lancé tant qu'un prestataire n'est pas connecté.",
                      style: TextStyle(color: Colors.grey[400]),
                      textAlign: TextAlign.center,
                    ),
                  ],
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
                        'LANCER LA SIMULATION',
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
    return 'Paiement simulé impossible. Réessayez.';
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

  Widget _buildExplanationCard() {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Comment fonctionne l'abonnement vendeur ?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "La publication de base peut rester gratuite selon la configuration. L'abonnement vendeur servira à publier davantage d'annonces ou à activer des options avancées. Le paiement réel sera branché en priorité avec les opérateurs mobiles, avec CinetPay seulement comme passerelle optionnelle.",
              style: TextStyle(color: Colors.grey[400], height: 1.35),
            ),
            const SizedBox(height: 10),
            const Chip(
              avatar: Icon(Icons.science_outlined, size: 18),
              label: Text('Mobile Money par défaut - Mode test'),
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
        subtitle: Text(
          operatorCode == 'cinetpay'
              ? 'Passerelle optionnelle'
              : 'Opérateur mobile prioritaire',
        ),
        onTap: isProcessing
            ? null
            : () => setState(() => selectedOperator = operatorCode),
      ),
    );
  }
}
