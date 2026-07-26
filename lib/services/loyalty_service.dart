import 'package:cloud_functions/cloud_functions.dart';

class LoyaltyService {
  LoyaltyService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Demande l'échange de points contre un article du catalogue. Le débit
  /// des points est atomique côté serveur (voir `requestGiftRedemption`
  /// dans `functions/index.js`) : lève une `FirebaseFunctionsException` si
  /// le solde est insuffisant ou l'article indisponible.
  Future<void> requestGiftRedemption(String itemId) async {
    final callable = _functions.httpsCallable('requestGiftRedemption');
    await callable.call(<String, dynamic>{'itemId': itemId});
  }

  /// Le vendeur propriétaire du catalogue (ou un admin) valide ou rejette
  /// une demande d'échange reçue.
  Future<void> respondToGiftRedemption({
    required String redemptionId,
    required bool approve,
  }) async {
    final callable = _functions.httpsCallable('respondToGiftRedemption');
    await callable.call(<String, dynamic>{
      'redemptionId': redemptionId,
      'decision': approve ? 'fulfilled' : 'rejected',
    });
  }

  /// Remise à zéro exceptionnelle du solde de points d'un acheteur chez un
  /// vendeur donné (admin uniquement, motif obligatoire, trace d'audit
  /// côté serveur).
  Future<void> adminResetLoyaltyPoints({
    required String buyerId,
    required String sellerId,
    required String reason,
  }) async {
    final callable = _functions.httpsCallable('adminResetLoyaltyPoints');
    await callable.call(<String, dynamic>{
      'buyerId': buyerId,
      'sellerId': sellerId,
      'reason': reason,
    });
  }
}
