import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/seller_statistics.dart';

final sellerStatisticsProvider = StreamProvider.autoDispose
    .family<SellerStatistics, String>((ref, sellerId) {
      if (sellerId.isEmpty) {
        return Stream<SellerStatistics>.value(const SellerStatistics());
      }
      return FirebaseFirestore.instance
          .collection('sellerStatistics')
          .doc(sellerId)
          .snapshots()
          .map(SellerStatistics.fromFirestore);
    });
