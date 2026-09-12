import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/search_alert.dart';
import '../services/search_alert_service.dart';

final searchAlertServiceProvider = Provider<SearchAlertService>(
  (ref) => SearchAlertService(),
);

final searchAlertsProvider = StreamProvider.autoDispose
    .family<List<SearchAlert>, String>((ref, userId) {
      return ref.watch(searchAlertServiceProvider).watchForUser(userId);
    });
