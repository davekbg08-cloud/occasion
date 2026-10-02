import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/screens/delete_account_screen.dart';
import 'package:occasion/services/account_deletion_service.dart';

/// La suppression elle-même est testée côté serveur (émulateur :
/// functions/test/functions.test.js, `deleteUserData`/`deleteAccount`).
/// Ici : uniquement le comportement de l'écran.
void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Future<void> Function() callDeleteAccount,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DeleteAccountScreen(
            userId: 'u1',
            service: AccountDeletionService(
              callDeleteAccount: callDeleteAccount,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('le bouton reste désactivé tant que SUPPRIMER n’est pas saisi', (
    tester,
  ) async {
    var calls = 0;
    await pumpScreen(tester, () async => calls++);

    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(calls, 0);

    await tester.enterText(find.byType(TextField), 'supprimer');
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('un refus serveur (commande en cours) affiche le motif exact, '
      'sans déconnecter', (tester) async {
    await pumpScreen(
      tester,
      () => Future.error(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Tu as encore une commande en cours.',
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'SUPPRIMER');
    await tester.pump();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('Tu as encore une commande en cours.'), findsOneWidget);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
  });
}
