import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/cart_provider.dart';
import '../services/cinetpay_service.dart';
import '../services/service_locator.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String? selectedOperator;
  final TextEditingController phoneController = TextEditingController();
  bool isProcessing = false;

  final List<Map<String, Object>> operators = const [
    {'name': 'Orange Money', 'code': 'orange', 'color': Colors.orange},
    {'name': 'MTN Mobile Money', 'code': 'mtn', 'color': Colors.amber},
    {'name': 'Wave', 'code': 'wave', 'color': Colors.blue},
    {'name': 'Moov Money', 'code': 'moov', 'color': Colors.green},
  ];

  Future<void> _processPayment() async {
    final phoneNumber = phoneController.text.trim();
    final cart = ref.read(cartNotifierProvider.notifier);
    final total = cart.totalAmount;

    if (selectedOperator == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veuillez sélectionner un opérateur et entrer un numéro',
          ),
        ),
      );
      return;
    }

    if (total <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Votre panier est vide')));
      return;
    }

    setState(() => isProcessing = true);

    try {
      final success = await getIt<CinetPayService>().initiatePayment(
        context: context,
        amount: total,
        transactionId: 'cart_${DateTime.now().millisecondsSinceEpoch}',
        description: 'Achat de produits',
        customerPhone: phoneNumber,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paiement confirmé avec succès !'),
            backgroundColor: Colors.green,
          ),
        );

        cart.clearCart();
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/');
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
      (sum, item) => sum + item.totalPrice,
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
                  subtitle: const Text('Paiement instantané'),
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
                'Vous allez recevoir une demande de paiement sur votre téléphone.',
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
