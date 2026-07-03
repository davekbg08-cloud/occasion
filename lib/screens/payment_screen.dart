import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/cinetpay_service.dart';
import '../services/payment_config.dart';
import '../services/payment_settlement_service.dart';
import '../services/phone_number_validator.dart';
import '../services/service_locator.dart';

enum _PaymentMode { orangeManual, card }

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  _PaymentMode mode = _PaymentMode.orangeManual;
  String phoneCountryIso = PhoneNumberValidator.defaultCountryIso;
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController referenceController = TextEditingController();
  bool isProcessing = false;

  final _settlement = PaymentSettlementService();

  @override
  void dispose() {
    phoneController.dispose();
    referenceController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Création de la commande (commune aux deux modes de paiement).
  // ---------------------------------------------------------------------
  Future<DocumentReference<Map<String, dynamic>>?> _createPendingOrder({
    required String buyerId,
    required String buyerName,
    required String buyerPhone,
    required double total,
    required List<dynamic> cartItems,
  }) async {
    final db = FirebaseFirestore.instance;
    final orderRef = db.collection('orders').doc();

    final normalizedItems = cartItems.map((item) {
      final product = item.product;
      return {
        'productId': product.id,
        'name': product.name,
        'quantity': item.quantity,
        'unitPrice': product.price,
        'totalPrice': item.totalPrice,
        if (product is ProductModel) 'sellerId': product.sellerId,
      };
    }).toList();
    final sellerIds = cartItems
        .map((item) => item.product)
        .whereType<ProductModel>()
        .map((product) => product.sellerId)
        .whereType<String>()
        .where((sellerId) => sellerId.isNotEmpty)
        .toSet()
        .toList();

    await orderRef.set({
      'id': orderRef.id,
      'buyerId': buyerId,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'items': normalizedItems,
      'sellerIds': sellerIds,
      'total': total,
      'currency': 'FC',
      'status': 'pending_payment',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return orderRef;
  }

  // ---------------------------------------------------------------------
  // Mode 1 : Orange Money envoi direct + vérification manuelle admin.
  // ---------------------------------------------------------------------
  Future<void> _submitManualOrangeMoney() async {
    final currentUser = ref.read(authNotifierProvider).currentUser;
    final cart = ref.read(cartNotifierProvider.notifier);
    final cartItems = ref.read(cartNotifierProvider);
    final total = cart.totalAmount;

    if (currentUser == null) {
      context.go('/auth');
      return;
    }
    if (total <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Votre panier est vide')));
      return;
    }
    if (!PaymentConfig.isManualOrangeMoneyConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numéro Orange Money non configuré côté app.'),
          backgroundColor: Colors.red,
        ),
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
    final phoneValidation = PhoneNumberValidator.validate(
      phoneController.text,
      countryIso: phoneCountryIso,
    );
    if (!phoneValidation.isValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(phoneValidation.message)));
      return;
    }

    setState(() => isProcessing = true);
    try {
      final orderRef = await _createPendingOrder(
        buyerId: currentUser.id,
        buyerName: currentUser.name,
        buyerPhone: phoneValidation.normalized,
        total: total,
        cartItems: cartItems,
      );
      if (orderRef == null) return;

      await orderRef.set({
        'status': 'awaiting_manual_verification',
        'manualPaymentMethod': 'orange_money_manual',
        'manualPaymentReference': reference,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      cart.clearCart();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Merci ! Ta commande est enregistrée et sera confirmée dès '
            'vérification du paiement (généralement rapide).',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      context.go('/orders');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyPaymentError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  // ---------------------------------------------------------------------
  // Mode 2 : Carte bancaire via CinetPay (acheteurs à l'étranger).
  // ---------------------------------------------------------------------
  Future<void> _payByCard() async {
    final currentUser = ref.read(authNotifierProvider).currentUser;
    final cart = ref.read(cartNotifierProvider.notifier);
    final cartItems = ref.read(cartNotifierProvider);
    final total = cart.totalAmount;

    if (currentUser == null) {
      context.go('/auth');
      return;
    }
    if (total <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Votre panier est vide')));
      return;
    }
    if (!PaymentConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Paiement par carte indisponible : configuration CinetPay manquante.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final phoneValidation = PhoneNumberValidator.validate(
      phoneController.text,
      countryIso: phoneCountryIso,
    );
    if (!phoneValidation.isValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(phoneValidation.message)));
      return;
    }

    setState(() => isProcessing = true);
    try {
      final orderRef = await _createPendingOrder(
        buyerId: currentUser.id,
        buyerName: currentUser.name,
        buyerPhone: phoneValidation.normalized,
        total: total,
        cartItems: cartItems,
      );
      if (orderRef == null) return;
      final transactionId = orderRef.id;

      await FirebaseFirestore.instance
          .collection('paymentIntents')
          .doc(transactionId)
          .set({
            'type': 'order',
            'userId': currentUser.id,
            'orderId': orderRef.id,
            'amount': total,
            'currency': 'FC',
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      await getIt<CinetPayService>().initiatePayment(
        context: context,
        amount: total,
        transactionId: transactionId,
        description: 'Commande Occasion',
        customerPhone: phoneValidation.normalized,
        customerName: currentUser.name,
        channels: 'CREDIT_CARD',
        onSuccess: (_) async {
          await orderRef.set({
            'status': 'processing_payment',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          final confirmedPaid = await _settlement.confirmPayment(
            transactionId,
          );

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                confirmedPaid
                    ? 'Paiement confirmé avec succès !'
                    : 'Paiement reçu, confirmation en cours...',
              ),
              backgroundColor: confirmedPaid ? Colors.green : Colors.orange,
            ),
          );

          cart.clearCart();
          if (mounted) context.go('/orders');
        },
        onError: (_) async {
          await orderRef.set({
            'status': 'cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Paiement refusé ou annulé.'),
              backgroundColor: Colors.red,
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyPaymentError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  String _friendlyPaymentError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.contains('permission-denied')) {
      return 'Paiement impossible avec votre session actuelle.';
    }
    if (message.isNotEmpty) return message;
    return 'Paiement impossible. Réessayez.';
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartNotifierProvider);
    final totalAmount = cartItems.fold(
      0.0,
      (runningTotal, item) => runningTotal + item.totalPrice,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Montant total', style: TextStyle(fontSize: 18)),
                    Text(
                      '${totalAmount.toInt()} FC',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SegmentedButton<_PaymentMode>(
              segments: const [
                ButtonSegment(
                  value: _PaymentMode.orangeManual,
                  icon: Icon(Icons.phone_iphone),
                  label: Text('Orange Money'),
                ),
                ButtonSegment(
                  value: _PaymentMode.card,
                  icon: Icon(Icons.credit_card),
                  label: Text('Carte bancaire'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: isProcessing
                  ? null
                  : (values) => setState(() => mode = values.first),
            ),
            const SizedBox(height: 20),
            const Text(
              'Numéro de téléphone',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: phoneCountryIso,
              decoration: const InputDecoration(
                labelText: 'Pays du numéro',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.public_outlined),
              ),
              items: PhoneNumberValidator.countries
                  .map(
                    (country) => DropdownMenuItem(
                      value: country.isoCode,
                      child: Text('${country.name} (${country.dialCode})'),
                    ),
                  )
                  .toList(),
              onChanged: isProcessing
                  ? null
                  : (value) => setState(
                      () => phoneCountryIso =
                          value ?? PhoneNumberValidator.defaultCountryIso,
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              enabled: !isProcessing,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '+243 8xx xxx xxx',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 24),
            if (mode == _PaymentMode.orangeManual)
              _OrangeManualSection(
                referenceController: referenceController,
                totalAmount: totalAmount,
                isProcessing: isProcessing,
              )
            else
              const _CardSection(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: isProcessing
                    ? null
                    : (mode == _PaymentMode.orangeManual
                          ? _submitManualOrangeMoney
                          : _payByCard),
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
                        mode == _PaymentMode.orangeManual
                            ? "J'AI ENVOYÉ L'ARGENT"
                            : 'PAYER PAR CARTE',
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrangeManualSection extends StatelessWidget {
  const _OrangeManualSection({
    required this.referenceController,
    required this.totalAmount,
    required this.isProcessing,
  });

  final TextEditingController referenceController;
  final double totalAmount;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final configured = PaymentConfig.isManualOrangeMoneyConfigured;
    return Card(
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
            Text(
              '1. Envoie ${totalAmount.toInt()} FC via Orange Money au numéro '
              'ci-dessous.\n'
              '2. Colle la référence de transaction reçue par SMS.\n'
              '3. Ta commande sera confirmée après vérification (généralement '
              'rapide, pas instantané).',
              style: TextStyle(color: Colors.grey[400], height: 1.4),
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
                    configured
                        ? PaymentConfig.manualOrangeMoneyNumber
                        : 'Numéro non configuré (contacte le support)',
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
          ],
        ),
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  const _CardSection();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paiement par carte bancaire',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Idéal pour les acheteurs hors RDC. Paiement sécurisé via '
              'CinetPay (Visa, Mastercard).',
              style: TextStyle(color: Colors.grey[400], height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
