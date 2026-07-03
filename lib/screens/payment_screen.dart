import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/phone_number_validator.dart';

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
  bool simulateSuccess = true;

  final List<Map<String, Object>> operators = const [
    {'name': 'Orange Money', 'code': 'orange', 'color': Colors.orange},
    {'name': 'MTN Mobile Money', 'code': 'mtn', 'color': Colors.amber},
    {'name': 'Airtel Money', 'code': 'airtel', 'color': Colors.red},
    {'name': 'M-Pesa', 'code': 'mpesa', 'color': Colors.green},
    {'name': 'Wave', 'code': 'wave', 'color': Colors.blue},
    {'name': 'Moov Money', 'code': 'moov', 'color': Colors.lightGreen},
    {'name': 'CinetPay', 'code': 'cinetpay', 'color': Colors.blueGrey},
  ];

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
    final operator = operators.firstWhere(
      (item) => item['code'] == selectedOperator,
    );

    if (total <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Votre panier est vide')));
      return;
    }

    setState(() => isProcessing = true);

    try {
      final result = await _createSimulatedOrder(
        buyerId: currentUser.id,
        buyerName: currentUser.name,
        buyerPhone: phoneValidation.normalized,
        provider: operator['name'] as String,
        providerCode: selectedOperator!,
        items: cartItems,
        total: total,
        shouldSucceed: simulateSuccess,
      );

      if (!mounted) return;
      if (result == 'paid') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paiement confirmé avec succès !'),
            backgroundColor: Colors.green,
          ),
        );

        cart.clearCart();
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/orders');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paiement simulé refusé. Commande annulée.'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  Future<String> _createSimulatedOrder({
    required String buyerId,
    required String buyerName,
    required String buyerPhone,
    required String provider,
    required String providerCode,
    required List<dynamic> items,
    required double total,
    required bool shouldSucceed,
  }) async {
    final db = FirebaseFirestore.instance;
    final orderRef = db.collection('orders').doc();
    final transactionRef = db.collection('transactions').doc();
    final normalizedItems = items.map((item) {
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
    final sellerIds = items
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
      'status': 'pending',
      'paymentProvider': provider,
      'paymentProviderCode': providerCode,
      'simulation': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await Future<void>.delayed(const Duration(milliseconds: 450));

    final status = shouldSucceed ? 'paid' : 'failed';
    await transactionRef.set({
      'id': transactionRef.id,
      'type': 'order',
      'orderId': orderRef.id,
      'userId': buyerId,
      'amount': total,
      'currency': 'FC',
      'paymentMethod': provider,
      'paymentMethodCode': providerCode,
      'status': status,
      'simulation': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final orderStatus = shouldSucceed ? 'paid' : 'cancelled';
    await orderRef.set({
      'status': orderStatus,
      'transactionId': transactionRef.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return orderStatus;
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
            const SizedBox(height: 24),
            const Text(
              'Mode simulation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
                  : (values) => setState(() => simulateSuccess = values.first),
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
                        'SIMULER LE PAIEMENT',
                        style: TextStyle(fontSize: 18),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Par défaut, Occasion privilégie les opérateurs mobiles. CinetPay restera une passerelle optionnelle.',
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
