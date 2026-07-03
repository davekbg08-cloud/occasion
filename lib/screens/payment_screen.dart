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

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String? selectedOperator = 'orange';
  String phoneCountryIso = PhoneNumberValidator.defaultCountryIso;
  final TextEditingController phoneController = TextEditingController();
  bool isProcessing = false;

  final List<Map<String, Object>> operators = const [
    {'name': 'Orange Money', 'code': 'orange', 'color': Colors.orange},
    {'name': 'MTN Mobile Money', 'code': 'mtn', 'color': Colors.amber},
    {'name': 'Airtel Money', 'code': 'airtel', 'color': Colors.red},
    {'name': 'M-Pesa', 'code': 'mpesa', 'color': Colors.green},
    {'name': 'Wave', 'code': 'wave', 'color': Colors.blue},
    {'name': 'Moov Money', 'code': 'moov', 'color': Colors.lightGreen},
    {'name': 'CinetPay', 'code': 'cinetpay', 'color': Colors.blueGrey},
  ];

  final _settlement = PaymentSettlementService();

  Future<void> _processPayment() async {
    final currentUser = ref.read(authNotifierProvider).currentUser;
    final phoneValidation = PhoneNumberValidator.validate(
      phoneController.text,
      countryIso: phoneCountryIso,
    );
    final cart = ref.read(cartNotifierProvider.notifier);
    final cartItems = ref.read(cartNotifierProvider);
    final total = cart.totalAmount;

    if (currentUser == null) {
      context.go('/auth');
      return;
    }

    if (selectedOperator == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un opérateur.')),
      );
      return;
    }
    if (!phoneValidation.isValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(phoneValidation.message)));
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
            'Paiement indisponible : configuration CinetPay manquante côté app.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isProcessing = true);

    try {
      final db = FirebaseFirestore.instance;
      final orderRef = db.collection('orders').doc();
      final transactionId = orderRef.id;

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

      // 1. On enregistre l'intention de paiement (source de vérité pour
      //    la Cloud Function) puis la commande en attente de paiement.
      await db.collection('paymentIntents').doc(transactionId).set({
        'type': 'order',
        'userId': currentUser.id,
        'orderId': orderRef.id,
        'amount': total,
        'currency': 'FC',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await orderRef.set({
        'id': orderRef.id,
        'buyerId': currentUser.id,
        'buyerName': currentUser.name,
        'buyerPhone': phoneValidation.normalized,
        'items': normalizedItems,
        'sellerIds': sellerIds,
        'total': total,
        'currency': 'FC',
        'status': 'pending_payment',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Ouverture du vrai paiement Mobile Money via CinetPay.
      if (!mounted) return;
      await getIt<CinetPayService>().initiatePayment(
        context: context,
        amount: total,
        transactionId: transactionId,
        description: 'Commande Occasion',
        customerPhone: phoneValidation.normalized,
        customerName: currentUser.name,
        onSuccess: (_) async {
          await orderRef.set({
            'status': 'processing_payment',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          // Confirmation immédiate côté serveur (le webhook CinetPay
          // confirmera aussi en arrière-plan si celle-ci échoue).
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
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartNotifierProvider);
    final totalAmount = cartItems.fold(
      0.0,
      (runningTotal, item) => runningTotal + item.totalPrice,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement Mobile Money')),
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
                      '${totalAmount.toInt()} FCFA',
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
            const Text(
              'Choisissez votre opérateur',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...operators.map(
              (operator) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  enabled: !isProcessing,
                  leading: Icon(
                    selectedOperator == operator['code']
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: operator['color'] as Color,
                  ),
                  title: Text(operator['name'] as String),
                  subtitle: Text(
                    operator['code'] == 'cinetpay'
                        ? 'Passerelle optionnelle'
                        : 'Opérateur mobile prioritaire',
                  ),
                  onTap: isProcessing
                      ? null
                      : () => setState(
                          () => selectedOperator = operator['code'] as String,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Numéro de téléphone',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                hintText: '+225 07 77 88 99',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: isProcessing ? null : _processPayment,
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
                        'PAYER MAINTENANT',
                        style: TextStyle(fontSize: 18),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Paiement Mobile Money sécurisé via CinetPay. Vous recevrez une '
                'demande de confirmation sur votre téléphone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
