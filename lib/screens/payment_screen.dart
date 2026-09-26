import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/cart_item.dart';
import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/payment_config.dart';
import '../services/payment_settlement_service.dart';
import '../services/phone_number_validator.dart';
import '../theme/app_theme.dart';
import '../utils/currencies.dart';

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

  /// Paiement Mobile Money automatique (pawaPay) : activé par
  /// `appConfig/payments.pawapayMode` (« live » pour tous, « sandbox »
  /// pour les administrateurs uniquement pendant les tests).
  bool _mobileMoneyAvailable = false;
  bool _useMobileMoney = false;
  String? _provider;
  String? _pendingTransactionId;
  String? _statusMessage;

  static const _providers = <String, String>{
    'VODACOM_MPESA_COD': 'M-Pesa',
    'AIRTEL_COD': 'Airtel Money',
    'ORANGE_COD': 'Orange Money',
  };

  @override
  void initState() {
    super.initState();
    _loadMobileMoneyAvailability();
  }

  Future<void> _loadMobileMoneyAvailability() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('payments')
          .get();
      final mode = snap.data()?['pawapayMode'];
      var available = mode == 'live';
      if (mode == 'sandbox') {
        available = await PaymentSettlementService().isCurrentUserAdmin();
      }
      if (!mounted) return;
      setState(() {
        _mobileMoneyAvailable = available;
        _useMobileMoney = available;
      });
    } catch (_) {
      // Configuration illisible : on garde le paiement manuel.
    }
  }

  /// Crée la commande et son intention de paiement (statut « pending »).
  Future<String> _createOrderAndIntent({
    required String buyerId,
    required String buyerName,
    required String buyerPhone,
    required List<CartItem> cartItems,
    required double total,
    required String currency,
  }) async {
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
      'buyerId': buyerId,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'items': normalizedItems,
      'sellerIds': sellerIds,
      'total': total,
      'currency': currency,
      'status': 'pending_payment',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await db.collection('paymentIntents').doc(transactionId).set({
      'type': 'order',
      'userId': buyerId,
      'orderId': orderRef.id,
      'amount': total,
      'currency': currency,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return transactionId;
  }

  Future<void> _submitMobileMoney() async {
    final currentUser = ref.read(authNotifierProvider).currentUser;
    final cart = ref.read(cartNotifierProvider.notifier);
    final cartItems = ref.read(cartNotifierProvider);
    final total = cart.totalAmount;
    final cartCurrency = cartItems.isEmpty
        ? 'FC'
        : cartItems.first.product.currency;
    final messenger = ScaffoldMessenger.of(context);

    if (currentUser == null) {
      context.go('/auth');
      return;
    }
    if (total <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Votre panier est vide')),
      );
      return;
    }
    final provider = _provider;
    if (provider == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Choisis ton opérateur Mobile Money.')),
      );
      return;
    }
    final phoneValidation = PhoneNumberValidator.validate(
      phoneController.text,
      countryIso: 'CD',
    );
    if (!phoneValidation.isValid) {
      messenger.showSnackBar(
        SnackBar(content: Text(phoneValidation.message)),
      );
      return;
    }

    setState(() {
      isProcessing = true;
      _statusMessage = 'Envoi de la demande de paiement…';
    });
    try {
      final transactionId =
          _pendingTransactionId ??
          await _createOrderAndIntent(
            buyerId: currentUser.id,
            buyerName: currentUser.name,
            buyerPhone: phoneValidation.normalized,
            cartItems: cartItems,
            total: total,
            currency: cartCurrency,
          );
      _pendingTransactionId = transactionId;

      await FirebaseFunctions.instance
          .httpsCallable('startPawapayPayment')
          .call<Map<String, dynamic>>({
            'transactionId': transactionId,
            'phoneNumber': phoneValidation.normalized,
            'provider': provider,
          });
      if (!mounted) return;
      setState(
        () => _statusMessage =
            'Confirme le paiement sur ton téléphone avec ton code PIN '
            '${_providers[provider]}…',
      );

      final result = await _waitForMobileMoneyResult(transactionId);
      if (!mounted) return;
      if (result.status == 'paid') {
        cart.clearCart();
        _pendingTransactionId = null;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Paiement reçu ! Ta commande est confirmée.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/orders');
      } else if (result.status == 'failed') {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.message ?? 'Paiement refusé ou annulé. Réessaie.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Pas encore de confirmation. Si tu as validé sur ton '
              'téléphone, ta commande sera confirmée automatiquement.',
            ),
          ),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Paiement impossible. Réessaie.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(_friendlyPaymentError(error)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
          _statusMessage = null;
        });
      }
    }
  }

  /// Interroge le serveur toutes les 5 s pendant 3 minutes au plus.
  Future<({String status, String? message})> _waitForMobileMoneyResult(
    String transactionId,
  ) async {
    final check = FirebaseFunctions.instance.httpsCallable(
      'checkPawapayPayment',
    );
    for (var attempt = 0; attempt < 36; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) break;
      try {
        final response = await check.call<Map<String, dynamic>>({
          'transactionId': transactionId,
        });
        final status = response.data['status'] as String? ?? 'pending';
        if (status == 'paid' || status == 'failed') {
          return (
            status: status,
            message: response.data['message'] as String?,
          );
        }
      } catch (_) {
        // Réseau instable : on réessaie au tour suivant.
      }
    }
    return (status: 'pending', message: null);
  }

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
    // Le panier ne peut contenir qu'une seule devise (voir cart_provider.addToCart).
    final cartCurrency = cartItems.isEmpty
        ? 'FC'
        : cartItems.first.product.currency;

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
        'currency': cartCurrency,
        'status': 'pending_payment',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await db.collection('paymentIntents').doc(transactionId).set({
        'type': 'order',
        'userId': currentUser.id,
        'orderId': orderRef.id,
        'amount': total,
        'currency': cartCurrency,
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
    final cartCurrency = cartItems.isEmpty
        ? 'FC'
        : cartItems.first.product.currency;

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
                      formatPrice(totalAmount, cartCurrency),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.price,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Paiement protégé : Occasion garde ton argent en "
                      "sécurité et ne le reverse au vendeur qu'après ta "
                      "confirmation de réception. Tu peux signaler un "
                      "problème à tout moment avant de confirmer.",
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            if (_mobileMoneyAvailable) ...[
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.bolt),
                    label: Text('Mobile Money'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.receipt_long_outlined),
                    label: Text('Orange Money manuel'),
                  ),
                ],
                selected: {_useMobileMoney},
                onSelectionChanged: isProcessing
                    ? null
                    : (value) => setState(() => _useMobileMoney = value.first),
              ),
            ],
            if (_useMobileMoney)
              _buildMobileMoneySection(totalAmount, cartCurrency)
            else
              ..._buildManualSection(totalAmount, cartCurrency),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMoneySection(double totalAmount, String cartCurrency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Ton opérateur',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _providers.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _provider == entry.key,
                onSelected: isProcessing
                    ? null
                    : (_) => setState(() => _provider = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: phoneController,
          enabled: !isProcessing,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Numéro Mobile Money',
            hintText: '+243 8xx xxx xxx',
            prefixIcon: Icon(Icons.phone_android),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tu recevras une demande de paiement sur ton téléphone : valide-la '
          'avec ton code PIN. La commande est confirmée automatiquement.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_statusMessage!)),
            ],
          ),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: isProcessing ? null : _submitMobileMoney,
            child: isProcessing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(
                    'PAYER ${formatPrice(totalAmount, cartCurrency)}',
                    style: const TextStyle(fontSize: 18),
                  ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildManualSection(double totalAmount, String cartCurrency) {
    return [
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Envoie ${totalAmount.toInt()} $cartCurrency via Orange Money au '
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
              items: PhoneNumberValidator.mobileMoneyCountries
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
    ];
  }
}
