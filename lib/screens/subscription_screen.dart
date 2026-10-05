import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../l10n/app_language.dart';
import '../models/subscription.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/payment_config.dart';
import '../services/play_billing_service.dart';
import '../utils/currencies.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  String? selectedPlan = 'seller_monthly';
  bool isProcessing = false;
  final TextEditingController referenceController = TextEditingController();
  final TextEditingController payerPhoneController = TextEditingController();
  final TextEditingController payerNameController = TextEditingController();

  // Achat intégré Google Play (moyen de paiement principal quand
  // disponible) : Orange Money manuel reste utilisable en secours, en
  // particulier là où Google Play Billing n'est pas pertinent (Afrique
  // centrale, où Play a peu de moyens de paiement locaux enregistrés).
  final _playBilling = PlayBillingService();
  ProductDetails? _playProduct;
  bool _playLoading = true;
  bool _playProcessing = false;
  String? _playStatusMessage;

  @override
  void initState() {
    super.initState();
    if (PlayBillingService.isSupportedPlatform) {
      _initPlayBilling();
    } else {
      _playLoading = false;
    }
  }

  Future<void> _initPlayBilling() async {
    final uid = ref.read(authNotifierProvider).currentUser?.id;
    if (uid != null) {
      _playBilling.listen(uid, _onPlayPurchaseUpdate);
      // Reflète un renouvellement automatique éventuel (aucune notification
      // serveur Play en place) : redonne une occasion au serveur de
      // rafraîchir la date d'expiration à chaque ouverture de l'écran.
      unawaited(_playBilling.restore(uid));
    }
    final product = await _playBilling.loadSellerMonthlyProduct();
    if (!mounted) return;
    setState(() {
      _playProduct = product;
      _playLoading = false;
    });
  }

  void _onPlayPurchaseUpdate(PlayPurchaseUpdate update) {
    if (!mounted) return;
    switch (update.outcome) {
      case PlayPurchaseOutcome.pending:
        setState(() {
          _playProcessing = true;
          _playStatusMessage = null;
        });
      case PlayPurchaseOutcome.success:
        setState(() {
          _playProcessing = false;
          _playStatusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abonnement activé via Google Play !'),
            backgroundColor: Colors.green,
          ),
        );
      case PlayPurchaseOutcome.cancelled:
        setState(() {
          _playProcessing = false;
          _playStatusMessage = null;
        });
      case PlayPurchaseOutcome.error:
        setState(() {
          _playProcessing = false;
          _playStatusMessage =
              update.message ?? 'Paiement Google Play impossible.';
        });
    }
  }

  Future<void> _buyViaPlay() async {
    final uid = ref.read(authNotifierProvider).currentUser?.id;
    final product = _playProduct;
    if (uid == null || product == null) return;
    setState(() {
      _playProcessing = true;
      _playStatusMessage = null;
    });
    final started = await _playBilling.buy(product, uid);
    if (!started && mounted) {
      setState(() {
        _playProcessing = false;
        _playStatusMessage = "Impossible de démarrer l'achat Google Play.";
      });
    }
  }

  final List<Map<String, Object>> plans = const [
    {
      'id': 'seller_monthly',
      'name': 'Vendeur Mensuel',
      'price': 7,
      'currency': 'USD',
      'duration': '1 mois',
      'benefit': 'Publication des annonces',
    },
    {
      'id': 'seller_monthly_fc',
      'name': 'Vendeur Mensuel',
      'price': 15000,
      'currency': 'FC',
      'duration': '1 mois',
      'benefit': 'Publication des annonces',
    },
  ];

  @override
  void dispose() {
    referenceController.dispose();
    payerPhoneController.dispose();
    payerNameController.dispose();
    _playBilling.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Choisissez une formule vendeur.'))),
      );
      return;
    }
    final payerPhone = payerPhoneController.text.replaceAll(
      RegExp(r'[^0-9+]'),
      '',
    );
    final payerName = payerNameController.text.trim();
    final reference = referenceController.text.trim();
    final problem = payerPhone.replaceAll('+', '').length < 9
        ? tr('Indique le numéro Orange Money qui a envoyé l’argent.')
        : payerName.length < 2
        ? tr('Indique le nom du titulaire de ce numéro Orange Money.')
        : !_looksLikeReference(reference)
        ? tr(
            'Colle la référence de transaction exacte reçue par SMS Orange '
            'Money (au moins 6 caractères, avec des chiffres).',
          )
        : null;
    if (problem != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
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
            currency: plan['currency'] as String? ?? 'USD',
            manualPaymentReference: reference,
            payerPhone: payerPhone,
            payerName: payerName,
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
      payerPhoneController.clear();
      payerNameController.clear();
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

  /// Une vraie référence Orange Money : assez longue et avec des chiffres
  /// (« xxxx » ou « ok » ne permettent aucune vérification).
  static bool _looksLikeReference(String value) =>
      value.length >= 6 && RegExp(r'[0-9]').hasMatch(value);

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    if (currentUser?.isBuyer == true) {
      return _buildBuyerFreeScaffold(context);
    }

    final subscription = ref.watch(subscriptionNotifierProvider);
    final hasPendingRequest = ref
        .watch(pendingSubscriptionRequestProvider(currentUser?.id ?? ''))
        .maybeWhen(data: (value) => value, orElse: () => false);
    final formDisabled = isProcessing || hasPendingRequest;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Abonnement vendeur')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: tr('Vérifier mon abonnement'),
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
              Text(
                tr('Renouvellement vendeur'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                tr('Abonnement vendeur'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  "Vous pouvez publier quelques annonces selon la configuration gratuite. L'abonnement vendeur servira aux volumes plus élevés et aux options avancées.",
                ),
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 16),
            ],
            if (hasPendingRequest) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_top, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Votre demande a été envoyée à l'administrateur. "
                        "Votre abonnement sera activé après vérification "
                        'du paiement.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (PlayBillingService.isSupportedPlatform) ...[
              _buildPlayBillingSection(),
              const SizedBox(height: 20),
            ],
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                // Sur Android, Google Play Billing est le moyen de paiement
                // mis en avant ci-dessus : Orange Money reste disponible
                // mais replié par défaut, pour les vendeurs d'Afrique
                // centrale qui n'ont pas de moyen de paiement enregistré
                // sur leur compte Play. Ailleurs (web, Play indisponible),
                // c'est le seul moyen de paiement : déplié d'emblée.
                initiallyExpanded: !PlayBillingService.isSupportedPlatform,
                tilePadding: EdgeInsets.zero,
                title: Text(
                  PlayBillingService.isSupportedPlatform
                      ? tr('Ou payer via Orange Money (Afrique centrale)')
                      : tr('Payer via Orange Money'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                children: [
                  ...plans.map((plan) => _buildPlanCard(plan, formDisabled)),
                  const SizedBox(height: 4),
                  Card(
                    color: Colors.grey[900],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Comment payer'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '1. Envoie le montant via Orange Money au numéro '
                            'ci-dessous.\n'
                            '2. Colle la référence de transaction reçue par SMS.\n'
                            "3. Ton abonnement s'active après vérification "
                            '(généralement rapide, pas instantané).',
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.4,
                            ),
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
                    controller: payerPhoneController,
                    enabled: !formDisabled,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: tr('Numéro Orange Money qui a payé'),
                      hintText: '+243 8x xxx xxxx',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: payerNameController,
                    enabled: !formDisabled,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: tr('Nom du titulaire de ce numéro'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: referenceController,
                    enabled: !formDisabled,
                    decoration: InputDecoration(
                      labelText: tr(
                        'Référence de transaction (SMS Orange Money)',
                      ),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: formDisabled ? null : _submit,
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
                          : Text(
                              tr("J'AI ENVOYÉ L'ARGENT"),
                              style: TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayBillingSection() {
    if (_playLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final product = _playProduct;
    if (product == null) {
      // Produit introuvable/inactif côté Play Console, ou Play Billing
      // indisponible sur cet appareil : Orange Money (déplié) reste le
      // seul chemin, pas d'erreur bloquante affichée.
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.green),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shop, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Payer avec Google Play'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                "${product.price} / mois — carte bancaire, opérateur ou solde Google Play déjà enregistré sur ton compte. Activation immédiate.",
              ),
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            if (_playStatusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _playStatusMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _playProcessing ? null : _buyViaPlay,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _playProcessing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        tr("S'ABONNER AVEC GOOGLE PLAY"),
                        style: const TextStyle(fontSize: 16),
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
      appBar: AppBar(title: Text(tr('Compte acheteur'))),
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
                  Text(
                    tr('Aucun abonnement pour les acheteurs'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      "Votre compte acheteur est gratuit. Vous ne payez pas d'abonnement mensuel.",
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.home_outlined),
                    label: Text(tr("Retour à l'accueil")),
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

  Widget _buildPlanCard(Map<String, Object> plan, bool disabled) {
    final planId = plan['id'] as String;
    final isSelected = selectedPlan == planId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        enabled: !disabled,
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
          formatPrice(
            plan['price'] as num,
            plan['currency'] as String? ?? 'USD',
          ),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        onTap: disabled ? null : () => setState(() => selectedPlan = planId),
      ),
    );
  }
}
