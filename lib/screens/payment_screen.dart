import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/payment_config.dart';
import '../services/phone_number_validator.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String phoneCountryIso = PhoneNumberValidator.defaultCountryIso;
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController referenceController = TextEditingController();
  bool isProcessing = false;

  @override
  void dispose() {
    phoneController.dispose();
    referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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

      await db.collection('paymentIntents').doc(transactionId).set({
        'type': 'order',
        'userId': currentUser.id,
        'orderId': orderRef.id,
        'amount': total,
        'currency': 'FC',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      final updatePayload = {
        'status': 'awaiting_manual_verification',
        'manualPaymentMethod': 'orange_money_manual',
        'manualPaymentReference': reference,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await orderRef.set(updatePayload, SetOptions(merge: true));
      await db
          .collection('paymentIntents')
          .doc(transactionId)
          .set(updatePayload, SetOptions(merge: true));

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
      appBar: AppBar(title: const Text('Paiement Orange Money')),
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
                    Text(
                      '1. Envoie ${totalAmount.toInt()} FC via Orange Money au '
                      'numéro ci-dessous.\n'
                      '2. Colle la référence de transaction reçue par SMS.\n'
                      '3. Ta commande sera confirmée après vérification '
                      '(généralement rapide, pas instantané).',
                      style: TextStyle(color: Colors.grey[400], height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Depuis l'étranger : utilise l'app Orange Money "
                      "internationale (ou un partenaire de transfert Orange "
                      "Money) pour envoyer directement sur ce numéro RDC.",
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
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
            const SizedBox(height: 24),
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
}
