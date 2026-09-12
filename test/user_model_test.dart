import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/user.dart';

void main() {
  group('UserModel — champs de parrainage', () {
    test('fromMap : valeurs par défaut si champs absents (compte legacy)', () {
      final user = UserModel.fromMap({
        'id': 'buyer1',
        'name': 'Alice',
        'phone': '+243812345678',
        'role': 'buyer',
        'createdAt': 0,
      });

      expect(user.referralCode, isNull);
      expect(user.referredBy, isNull);
      expect(user.referralCount, 0);
      expect(user.referralRewardPoints, 0);
    });

    test('fromMap : lit tous les champs écrits par les Cloud Functions', () {
      final user = UserModel.fromMap({
        'id': 'buyer1',
        'name': 'Alice',
        'phone': '+243812345678',
        'role': 'buyer',
        'createdAt': 0,
        'referralCode': 'AB12CD',
        'referredBy': 'seller1',
        'referralCount': 3,
        'referralRewardPoints': 15,
      });

      expect(user.referralCode, 'AB12CD');
      expect(user.referredBy, 'seller1');
      expect(user.referralCount, 3);
      expect(user.referralRewardPoints, 15);
    });

    test('toMap() n\'inclut jamais les champs de parrainage : une mise à jour '
        'de profil (merge) ne peut donc jamais les écraser côté client', () {
      final user = UserModel(
        id: 'buyer1',
        name: 'Alice',
        phone: '+243812345678',
        role: UserRole.buyer,
        createdAt: DateTime(2026, 1, 1),
        referralCode: 'AB12CD',
        referralCount: 3,
        referralRewardPoints: 15,
      );

      final map = user.toMap();

      expect(map.containsKey('referralCode'), isFalse);
      expect(map.containsKey('referredBy'), isFalse);
      expect(map.containsKey('referralCount'), isFalse);
      expect(map.containsKey('referralRewardPoints'), isFalse);
    });

    test('copyWith préserve les champs de parrainage par défaut', () {
      final user = UserModel(
        id: 'buyer1',
        name: 'Alice',
        phone: '+243812345678',
        role: UserRole.buyer,
        createdAt: DateTime(2026, 1, 1),
        referralCode: 'AB12CD',
        referralCount: 3,
        referralRewardPoints: 15,
      );

      final updated = user.copyWith(name: 'Alice B.');

      expect(updated.referralCode, 'AB12CD');
      expect(updated.referralCount, 3);
      expect(updated.referralRewardPoints, 15);
    });
  });

  group('UserModel — note moyenne et ventes (publicProfiles)', () {
    test('fromMap : valeurs par défaut si champs absents', () {
      final user = UserModel.fromMap({
        'id': 'seller1',
        'name': 'Bob',
        'phone': '+243812345678',
        'role': 'seller',
        'createdAt': 0,
      });

      expect(user.ratingSum, 0);
      expect(user.ratingCount, 0);
      expect(user.averageRating, 0);
      expect(user.totalSales, 0);
    });

    test(
      'fromMap : lit tous les champs écrits par submitReview/notifySettlement',
      () {
        final user = UserModel.fromMap({
          'id': 'seller1',
          'name': 'Bob',
          'phone': '+243812345678',
          'role': 'seller',
          'createdAt': 0,
          'ratingSum': 12,
          'ratingCount': 3,
          'averageRating': 4.0,
          'totalSales': 7,
        });

        expect(user.ratingSum, 12);
        expect(user.ratingCount, 3);
        expect(user.averageRating, 4.0);
        expect(user.totalSales, 7);
      },
    );

    test('toMap() n\'inclut jamais ces champs : jamais écrasables par une '
        'mise à jour de profil côté client', () {
      final user = UserModel(
        id: 'seller1',
        name: 'Bob',
        phone: '+243812345678',
        role: UserRole.seller,
        createdAt: DateTime(2026, 1, 1),
        ratingSum: 12,
        ratingCount: 3,
        averageRating: 4.0,
        totalSales: 7,
      );

      final map = user.toMap();

      expect(map.containsKey('ratingSum'), isFalse);
      expect(map.containsKey('ratingCount'), isFalse);
      expect(map.containsKey('averageRating'), isFalse);
      expect(map.containsKey('totalSales'), isFalse);
    });

    test('copyWith préserve ces champs par défaut', () {
      final user = UserModel(
        id: 'seller1',
        name: 'Bob',
        phone: '+243812345678',
        role: UserRole.seller,
        createdAt: DateTime(2026, 1, 1),
        ratingSum: 12,
        ratingCount: 3,
        averageRating: 4.0,
        totalSales: 7,
      );

      final updated = user.copyWith(name: 'Bob B.');

      expect(updated.ratingSum, 12);
      expect(updated.ratingCount, 3);
      expect(updated.averageRating, 4.0);
      expect(updated.totalSales, 7);
    });
  });
}
