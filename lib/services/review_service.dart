import 'package:cloud_functions/cloud_functions.dart';

/// Dépose un avis après une commande complétée via la Cloud Function
/// `submitReview` — jamais d'écriture directe (voir `firestore.rules`,
/// `reviews/{reviewId}` est `allow write: if false`).
class ReviewService {
  ReviewService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Retourne `true` si l'avis vient d'être créé, `false` s'il existait
  /// déjà (rejeu, double-tap) — jamais une erreur dans ce cas.
  Future<bool> submitReview({
    required String orderId,
    required String sellerId,
    required int rating,
    String comment = '',
  }) async {
    final result = await _functions.httpsCallable('submitReview').call({
      'orderId': orderId,
      'sellerId': sellerId,
      'rating': rating,
      'comment': comment,
    });
    final data = result.data;
    final alreadyExisted = data is Map && data['alreadyExisted'] == true;
    return !alreadyExisted;
  }
}
