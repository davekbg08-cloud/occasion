import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:occasion/services/play_billing_service.dart';

PurchaseDetails _purchase({
  required PurchaseStatus status,
  String productID = kPlayMonthlySubscriptionId,
  String token = 'tok1',
  bool pendingComplete = true,
  String? errorMessage,
}) {
  final purchase = PurchaseDetails(
    productID: productID,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: token,
      source: 'google_play',
    ),
    transactionDate: null,
    status: status,
  )..pendingCompletePurchase = pendingComplete;
  if (errorMessage != null) {
    purchase.error = IAPError(
      source: 'google_play',
      code: 'error',
      message: errorMessage,
    );
  }
  return purchase;
}

void main() {
  group('PlayBillingService._handlePurchases (état-machine d\'achat)', () {
    test('un achat "purchased" confirmé avec succès côté serveur est complété '
        'auprès de Play, puis signalé comme un succès', () async {
      final confirmed = <String>[];
      final completed = <String>[];
      final service = PlayBillingService(
        confirmPurchase: (p) async => confirmed.add(p.productID),
        completePurchase: (p) async =>
            completed.add(p.verificationData.serverVerificationData),
      );
      final updates = <PlayPurchaseUpdate>[];

      await service.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ], updates.add);

      expect(confirmed, [kPlayMonthlySubscriptionId]);
      expect(completed, ['tok1']);
      expect(updates, hasLength(1));
      expect(updates.single.outcome, PlayPurchaseOutcome.success);
    });

    test('un achat "restored" (redélivrance/restorePurchases) suit exactement '
        'le même chemin qu\'un achat "purchased"', () async {
      final completed = <String>[];
      final service = PlayBillingService(
        confirmPurchase: (_) async {},
        completePurchase: (p) async =>
            completed.add(p.verificationData.serverVerificationData),
      );
      final updates = <PlayPurchaseUpdate>[];

      await service.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.restored, token: 'tok-restored'),
      ], updates.add);

      expect(completed, ['tok-restored']);
      expect(updates.single.outcome, PlayPurchaseOutcome.success);
    });

    test('quand la vérification serveur échoue, l\'achat n\'est PAS complété '
        'auprès de Play (reste en attente, redélivré plus tard) et l\'erreur '
        'est remontée', () async {
      final completed = <String>[];
      final service = PlayBillingService(
        confirmPurchase: (_) async =>
            throw Exception('Achat Google Play introuvable ou non actif.'),
        completePurchase: (p) async =>
            completed.add(p.verificationData.serverVerificationData),
      );
      final updates = <PlayPurchaseUpdate>[];

      await service.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased),
      ], updates.add);

      expect(completed, isEmpty);
      expect(updates.single.outcome, PlayPurchaseOutcome.error);
    });

    test('un achat "pending" est signalé sans jamais appeler le serveur ni '
        'compléter l\'achat', () async {
      var confirmCalls = 0;
      var completeCalls = 0;
      final service = PlayBillingService(
        confirmPurchase: (_) async => confirmCalls++,
        completePurchase: (_) async => completeCalls++,
      );
      final updates = <PlayPurchaseUpdate>[];

      await service.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.pending),
      ], updates.add);

      expect(confirmCalls, 0);
      expect(completeCalls, 0);
      expect(updates.single.outcome, PlayPurchaseOutcome.pending);
    });

    test('un achat "canceled" est complété (si en attente) mais jamais envoyé '
        'au serveur de vérification', () async {
      var confirmCalls = 0;
      final completed = <String>[];
      final service = PlayBillingService(
        confirmPurchase: (_) async => confirmCalls++,
        completePurchase: (p) async =>
            completed.add(p.verificationData.serverVerificationData),
      );
      final updates = <PlayPurchaseUpdate>[];

      await service.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.canceled),
      ], updates.add);

      expect(confirmCalls, 0);
      expect(completed, ['tok1']);
      expect(updates.single.outcome, PlayPurchaseOutcome.cancelled);
    });

    test('un achat "error" relaie le message d\'erreur Play et complète '
        'l\'achat si nécessaire, sans jamais appeler le serveur', () async {
      var confirmCalls = 0;
      final completed = <String>[];
      final service = PlayBillingService(
        confirmPurchase: (_) async => confirmCalls++,
        completePurchase: (p) async =>
            completed.add(p.verificationData.serverVerificationData),
      );
      final updates = <PlayPurchaseUpdate>[];

      await service.handlePurchasesForTest([
        _purchase(
          status: PurchaseStatus.error,
          errorMessage: 'Paiement refusé par la banque.',
        ),
      ], updates.add);

      expect(confirmCalls, 0);
      expect(completed, ['tok1']);
      expect(updates.single.outcome, PlayPurchaseOutcome.error);
      expect(updates.single.message, 'Paiement refusé par la banque.');
    });

    test('ne complète jamais un achat dont pendingCompletePurchase est déjà '
        'false (déjà acquitté)', () async {
      var completeCalls = 0;
      final service = PlayBillingService(
        confirmPurchase: (_) async {},
        completePurchase: (_) async => completeCalls++,
      );

      await service.handlePurchasesForTest([
        _purchase(status: PurchaseStatus.purchased, pendingComplete: false),
      ], (_) {});

      expect(completeCalls, 0);
    });
  });
}
