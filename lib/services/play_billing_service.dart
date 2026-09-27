import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Identifiant du produit d'abonnement vendeur dans Google Play Console
/// (correspond au `planId`/`productId` `seller_monthly` déjà utilisé côté
/// serveur pour le paiement manuel Orange Money — même formule, juste un
/// second moyen de paiement).
const String kPlayMonthlySubscriptionId = 'seller_monthly';

enum PlayPurchaseOutcome { pending, success, cancelled, error }

class PlayPurchaseUpdate {
  const PlayPurchaseUpdate(this.outcome, {this.message});
  final PlayPurchaseOutcome outcome;
  final String? message;
}

/// Achat intégré Google Play pour l'abonnement vendeur.
///
/// Le jeton d'achat (`purchaseToken`) renvoyé par la boutique Play n'est
/// JAMAIS traité comme une preuve de paiement en lui-même : il est toujours
/// revérifié côté serveur (Cloud Function `confirmPlayPurchase`, qui
/// interroge directement l'API Play Developer) avant d'activer quoi que ce
/// soit — ce service ne fait qu'orchestrer l'achat côté Play et relayer le
/// jeton au serveur, jamais activer l'abonnement lui-même.
///
/// `completePurchase` (qui acquitte l'achat auprès de la BillingClient
/// Android, condition pour éviter un remboursement automatique sous 3
/// jours) n'est appelé qu'APRÈS confirmation réussie côté serveur : en cas
/// d'échec de vérification (réseau, serveur indisponible...), l'achat reste
/// "en attente" et sera redélivré par `purchaseStream` au prochain
/// démarrage de l'app / appel à `restorePurchases()`, donnant une nouvelle
/// chance de vérification sans nouveau paiement.
class PlayBillingService {
  /// `confirmPurchase`/`completePurchase` permettent d'injecter des doubles
  /// de test pour exercer l'état-machine d'achat ([handlePurchasesForTest])
  /// sans jamais toucher à un vrai canal de plateforme (Cloud Functions,
  /// BillingClient Android) — par défaut, les vrais appels serveur/Play.
  PlayBillingService({
    FirebaseFunctions? functions,
    InAppPurchase? inAppPurchase,
    Future<void> Function(PurchaseDetails purchase)? confirmPurchase,
    Future<void> Function(PurchaseDetails purchase)? completePurchase,
  }) : _functionsOverride = functions,
       _iapOverride = inAppPurchase,
       _confirmPurchaseOverride = confirmPurchase,
       _completePurchaseOverride = completePurchase;

  final FirebaseFunctions? _functionsOverride;
  final InAppPurchase? _iapOverride;
  final Future<void> Function(PurchaseDetails purchase)?
  _confirmPurchaseOverride;
  final Future<void> Function(PurchaseDetails purchase)?
  _completePurchaseOverride;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Évalués paresseusement (jamais dans le constructeur) : dans les tests
  // qui fournissent `confirmPurchase`/`completePurchase`, ni Firebase ni le
  // canal de plateforme Play ne sont jamais initialisés/touchés.
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;
  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;

  /// Google Play Billing n'existe que sur Android natif (ni sur le web, ni
  /// sur les autres plateformes où l'app n'est de toute façon pas publiée).
  /// `kIsWeb` en premier court-circuite avant tout accès à `Platform`
  /// (indisponible sur le web) — même garde que `notification_service.dart`.
  static bool get isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  /// Écoute les mises à jour d'achat pour tout le cycle de vie du service.
  /// `uid` sert à ne relayer au serveur que des achats initiés/restaurés
  /// pour l'utilisateur actuellement connecté.
  void listen(String uid, void Function(PlayPurchaseUpdate update) onUpdate) {
    if (!isSupportedPlatform) return;
    unawaited(_subscription?.cancel());
    _subscription = _iap.purchaseStream.listen(
      (purchases) => unawaited(_handlePurchases(purchases, onUpdate)),
      onError: (Object error) {
        onUpdate(
          PlayPurchaseUpdate(
            PlayPurchaseOutcome.error,
            message: error.toString(),
          ),
        );
      },
    );
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  /// Charge la formule vendeur mensuelle depuis le catalogue Play, ou
  /// `null` si Play Billing n'est pas disponible (web, indisponible sur
  /// l'appareil, produit non trouvé/non actif côté Play Console).
  Future<ProductDetails?> loadSellerMonthlyProduct() async {
    if (!isSupportedPlatform) return null;
    if (!await _iap.isAvailable()) return null;

    final response = await _iap.queryProductDetails({
      kPlayMonthlySubscriptionId,
    });
    if (response.error != null || response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  /// Déclenche l'achat. Ne renvoie que si la demande a bien été transmise à
  /// Play — le résultat réel (succès/erreur/annulation) arrive via
  /// `purchaseStream`, relayé par [listen].
  Future<bool> buy(ProductDetails product, String uid) {
    final purchaseParam = product is GooglePlayProductDetails
        ? GooglePlayPurchaseParam(
            productDetails: product,
            applicationUserName: uid,
            offerToken: product.offerToken,
          )
        : PurchaseParam(productDetails: product, applicationUserName: uid);
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Redemande à Play la liste des achats actifs de l'utilisateur : c'est
  /// ce qui permet de refléter un renouvellement automatique côté app
  /// (l'abonnement Occasion `subscriptions/{uid}` est prolongé lors de la
  /// revérification serveur qui suit, avec la date d'expiration à jour
  /// auprès de Google) faute de notification serveur Play en place.
  Future<void> restore(String uid) {
    if (!isSupportedPlatform) return Future.value();
    return _iap.restorePurchases(applicationUserName: uid);
  }

  /// Exposé uniquement pour les tests : exerce l'état-machine d'achat
  /// ([_handlePurchases]) directement, sans passer par le vrai
  /// `purchaseStream` de Play (jamais disponible en test unitaire pur).
  @visibleForTesting
  Future<void> handlePurchasesForTest(
    List<PurchaseDetails> purchases,
    void Function(PlayPurchaseUpdate update) onUpdate,
  ) => _handlePurchases(purchases, onUpdate);

  Future<void> _handlePurchases(
    List<PurchaseDetails> purchases,
    void Function(PlayPurchaseUpdate update) onUpdate,
  ) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          onUpdate(const PlayPurchaseUpdate(PlayPurchaseOutcome.pending));
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await _completePurchase(purchase);
          }
          onUpdate(const PlayPurchaseUpdate(PlayPurchaseOutcome.cancelled));
        case PurchaseStatus.error:
          if (purchase.pendingCompletePurchase) {
            await _completePurchase(purchase);
          }
          onUpdate(
            PlayPurchaseUpdate(
              PlayPurchaseOutcome.error,
              message: purchase.error?.message,
            ),
          );
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            await _confirmOnServer(purchase);
            if (purchase.pendingCompletePurchase) {
              await _completePurchase(purchase);
            }
            onUpdate(const PlayPurchaseUpdate(PlayPurchaseOutcome.success));
          } catch (error) {
            // Volontairement PAS de completePurchase ici : voir la
            // documentation de la classe. L'achat reste en attente côté
            // Play et sera redélivré (nouvelle tentative de vérification
            // sans nouveau paiement).
            onUpdate(
              PlayPurchaseUpdate(
                PlayPurchaseOutcome.error,
                message: _friendlyServerError(error),
              ),
            );
          }
      }
    }
  }

  Future<void> _confirmOnServer(PurchaseDetails purchase) {
    if (_confirmPurchaseOverride != null) {
      return _confirmPurchaseOverride(purchase);
    }
    final callable = _functions.httpsCallable('confirmPlayPurchase');
    return callable.call<Object?>({
      'productId': purchase.productID,
      'purchaseToken': purchase.verificationData.serverVerificationData,
    });
  }

  Future<void> _completePurchase(PurchaseDetails purchase) {
    if (_completePurchaseOverride != null) {
      return _completePurchaseOverride(purchase);
    }
    return _iap.completePurchase(purchase);
  }

  String _friendlyServerError(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ??
          'Vérification du paiement Google Play impossible.';
    }
    return 'Vérification du paiement Google Play impossible.';
  }
}
