import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/cart_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartNotifierProvider);
    final cartNotifier = ref.read(cartNotifierProvider.notifier);
    final total = cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);

    return Scaffold(
      appBar: AppBar(title: const Text('Mon Panier')),
      body: cartItems.isEmpty
          ? const Center(
              child: Text(
                'Votre panier est vide',
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: cartItems.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = cartItems[index];

                return ListTile(
                  title: Text(item.product.name),
                  subtitle: Text(
                    '${item.product.price.toInt()} FCFA × ${item.quantity}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: item.quantity == 1
                            ? null
                            : () => cartNotifier.updateQuantity(
                                item.product.id,
                                item.quantity - 1,
                              ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${item.quantity}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => cartNotifier.updateQuantity(
                          item.product.id,
                          item.quantity + 1,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            cartNotifier.removeFromCart(item.product.id),
                      ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: cartItems.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total :',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${total.toInt()} FCFA',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: () => context.push('/payment'),
                        child: const Text('Passer à la caisse'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
