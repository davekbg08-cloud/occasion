import 'dart:developer' as developer;

import 'package:injectable/injectable.dart';

@injectable
class MobileMoneyService {
  Future<bool> payWithMobileMoney({
    required String operator,
    required String phoneNumber,
    required double amount,
    String description = '',
  }) async {
    if (operator.trim().isEmpty) {
      throw ArgumentError('Opérateur invalide');
    }

    if (phoneNumber.trim().isEmpty) {
      throw ArgumentError('Numéro de téléphone invalide');
    }

    if (amount <= 0) {
      throw ArgumentError('Montant invalide');
    }

    await Future<void>.delayed(const Duration(seconds: 3));

    developer.log('Paiement Mobile Money initié :');
    developer.log('Opérateur: $operator');
    developer.log('Numéro: $phoneNumber');
    developer.log('Montant: $amount FCFA');
    if (description.isNotEmpty) {
      developer.log('Description: $description');
    }

    return true;
  }
}
