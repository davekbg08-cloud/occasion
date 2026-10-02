import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/main.dart';
import 'package:occasion/widgets/occasion_logo.dart';

/// Verrouille la mécanique du bootstrap Firebase, après la régression
/// 1.5.3+20/1.5.4+21 (réessais automatiques qui rappelaient
/// `Firebase.initializeApp()` par-dessus une tentative encore en cours,
/// voir le commentaire de `_realBootstrap` dans `lib/main.dart`) : UN SEUL
/// appel à la fois (jamais deux en vol simultanément, même après un
/// "Réessayer" manuel), un visuel de chargement persistant pendant
/// l'attente, et l'indice "ça prend du temps" après ~15s.
///
/// Ne couvre PAS le comportement réel de `Firebase.initializeApp()` sur un
/// vrai appareil/réseau (hors de portée d'un test automatisé).
void main() {
  testWidgets(
    "pendant l'initialisation : logo + indicateur de progression visibles "
    "dès le début, jamais d'écran d'erreur",
    (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          child: FirebaseBootstrap(bootstrap: () => completer.future),
        ),
      );

      expect(find.byType(OccasionLogo), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  testWidgets("après ~15s sans succès : affiche un indice 'ça prend du temps', "
      'toujours sans bouton', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        child: FirebaseBootstrap(bootstrap: () => completer.future),
      ),
    );

    expect(
      find.textContaining('Ça prend plus de temps que prévu'),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 16));

    expect(
      find.textContaining('Ça prend plus de temps que prévu'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('régression : un échec affiche "Réessayer", et retaper ne lance '
      'JAMAIS un second appel tant que le précédent est encore en vol', (
    tester,
  ) async {
    var callCount = 0;
    final completers = <Completer<void>>[];
    await tester.pumpWidget(
      ProviderScope(
        child: FirebaseBootstrap(
          bootstrap: () {
            callCount++;
            final completer = Completer<void>();
            completers.add(completer);
            return completer.future;
          },
        ),
      ),
    );
    expect(callCount, 1);

    completers.first.completeError(Exception('échec simulé'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Réessayer'), findsOneWidget);
    expect(
      callCount,
      1,
      reason:
          "un échec ne doit JAMAIS déclencher de nouvel appel tout seul "
          '— uniquement "Réessayer", sur action explicite',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Réessayer'));
    await tester.pump();

    expect(
      callCount,
      2,
      reason: 'Réessayer doit bien déclencher une NOUVELLE tentative',
    );
    expect(find.byType(OccasionLogo), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
