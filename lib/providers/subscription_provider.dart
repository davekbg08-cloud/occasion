import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subscription.dart';

class SubscriptionNotifier extends StateNotifier<Subscription?> {
  SubscriptionNotifier() : super(null);

  void activateSubscription(Subscription newSub) {
    state = newSub;
  }
}

final subscriptionNotifierProvider =
    StateNotifierProvider<SubscriptionNotifier, Subscription?>(
      (ref) => SubscriptionNotifier(),
    );
