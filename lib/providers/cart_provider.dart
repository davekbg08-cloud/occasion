import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cart_item.dart';
import '../models/product_model.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super(const []);

  /// Retourne `false` (sans rien ajouter) si le panier contient déjà des
  /// articles dans une devise différente — on n'autorise qu'une seule devise
  /// par panier pour que le total affiché/payé ait un sens.
  bool addToCart(ProductModel product) {
    if (state.isNotEmpty && state.first.product.currency != product.currency) {
      return false;
    }

    final existingIndex = state.indexWhere(
      (item) => item.product.id == product.id,
    );

    if (existingIndex == -1) {
      state = [...state, CartItem(product: product)];
      return true;
    }

    final updatedItems = [...state];
    final existingItem = updatedItems[existingIndex];
    updatedItems[existingIndex] = existingItem.copyWith(
      quantity: existingItem.quantity + 1,
    );
    state = updatedItems;
    return true;
  }

  void removeFromCart(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void clearCart() {
    state = const [];
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity < 1) return;

    final index = state.indexWhere((item) => item.product.id == productId);
    if (index == -1) return;

    final updatedItems = [...state];
    updatedItems[index] = updatedItems[index].copyWith(quantity: quantity);
    state = updatedItems;
  }

  double get totalAmount {
    return state.fold(0, (sum, item) => sum + item.totalPrice);
  }

  int get itemCount {
    return state.fold(0, (sum, item) => sum + item.quantity);
  }
}

final cartNotifierProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>(
      (ref) => CartNotifier(),
    );
