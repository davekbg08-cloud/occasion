import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class LoyaltyService {
  LoyaltyService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
    : _functions = functions ?? FirebaseFunctions.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  /// Id déterministe pour une demande d'échange (même principe que
  /// `clientMessageId` côté chat, voir `ChatService.newClientMessageId`) —
  /// à générer une seule fois par intention d'échange et à réutiliser tel
  /// quel pour toute relance après échec, jamais régénéré à chaque appel.
  String newClientRequestId() =>
      _firestore.collection('giftRedemptions').doc().id;

  /// Demande l'échange de points contre un article du catalogue. Le débit
  /// des points est atomique côté serveur (voir `requestGiftRedemption`
  /// dans `functions/index.js`), qui utilise [clientRequestId] comme id de
  /// document déterministe : une relance après timeout/coupure réseau avec
  /// le MÊME [clientRequestId] retombe sur la demande déjà créée au lieu
  /// de débiter les points une seconde fois. Lève une
  /// `FirebaseFunctionsException` si le solde est insuffisant ou l'article
  /// indisponible.
  Future<void> requestGiftRedemption(
    String itemId, {
    required String clientRequestId,
  }) async {
    final callable = _functions.httpsCallable('requestGiftRedemption');
    await callable.call(<String, dynamic>{
      'itemId': itemId,
      'clientRequestId': clientRequestId,
    });
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
