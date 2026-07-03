import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/subscription.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/cinetpay_service.dart';
import '../services/payment_config.dart';
import '../services/payment_settlement_service.dart';
import '../services/service_locator.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? selectedPlan = 'seller_monthly';
  bool isProcessing = false;

  final _settlement = PaymentSettlementService();

  final List<Map<String, Object>> plans = const [
    {
      'id': 'seller_monthly',
      'name': 'Vendeur Mensuel',
      'price': 20000,
      'duration': '1 mois',
      'benefit': 'Publication des annonces',
    },
  ];

  Future<void> _subscribe() async {
    if (selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez une formule vendeur.')),
      );
      return;
    }

    if (!PaymentConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Paiement indisponible : configuration CinetPay manquante côté app.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final plan = plans.firstWhere((item) => item['id'] == selectedPlan);
    final currentUser = ref.read(authNotifierProvider).currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connecte-toi avant de payer un abonnement.')),
      );
      return;
    }

    setState(() => isProcessing = true);

    try {
      final price = (plan['price'] as num).toDouble();
      final transactionId = await ref
          .read(subscriptionNotifierProvider.notifier)
          .createSubscriptionPaymentIntent(
            planId: plan['id'] as String,
            planName: plan['name'] as String,
            price: price,
          );

      if (!mounted) return;
      await getIt<CinetPayService>().initiatePayment(
        context: context,
        amount: price,
        transactionId: transactionId,
        description: 'Abonnement vendeur ${plan['name']}',
        customerPhone: currentUser.phone,
        customerName: currentUser.name,
        onSuccess: (_) async {
          final confirmedPaid = await _settlement.confirmPayment(
            transactionId,
          );

          if (confirmedPaid) {
            await ref
                .read(subscriptionNotifierProvider.notifier)
                .loadForUser(currentUser.id);
          }

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                confirmedPaid
                    ? 'Paiement confirmé. Abonnement activé.'
                    : 'Paiement reçu, activation en cours...',
              ),
              backgroundColor: confirmedPaid ? Colors.green : Colors.orange,
            ),
          );
        },
        onError: (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Paiement refusé ou annulé.'),
              backgroundColor: Colors.red,
            ),
          );
        },
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
                        ? 'Paiement en cours...'
                        : 'Renouveler (${subscription.price.toInt()} FC)',
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
                        'PAYER ET ACTIVER',
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
              "La publication de base peut rester gratuite selon la configuration. L'abonnement vendeur sert à publier davantage d'annonces et à activer des options avancées. Le paiement se fait par Mobile Money via CinetPay (Orange, MTN, Airtel, M-Pesa selon disponibilité).",
              style: TextStyle(color: Colors.grey[400], height: 1.35),
            ),
            const SizedBox(height: 10),
            const Chip(
              avatar: Icon(Icons.verified_outlined, size: 18),
              label: Text('Paiement réel via CinetPay'),
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
