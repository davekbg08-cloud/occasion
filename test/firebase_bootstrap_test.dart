import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/main.dart';
import 'package:occasion/widgets/occasion_logo.dart';

/// Verrouille la mécanique du bootstrap Firebase : chargement persistant,
/// réessai automatique indéfini en cas d'échec (jamais d'écran d'erreur
/// bloquant demandant une action), et l'indice "ça prend du temps" après un
/// délai prolongé.
///
/// Ne couvre PAS le comportement réel de `Firebase.initializeApp()` sur un
/// vrai appareil/réseau (hors de portée d'un test automatisé) — seulement
/// la structure du mécanisme autour.
void main() {
  testWidgets(
    "pendant l'initialisation : affiche le logo, jamais une seule erreur "
    'bloquante',
    (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          child: FirebaseBootstrap(bootstrap: () => completer.future),
        ),
      );

      expect(find.byType(OccasionLogo), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('régression : un échec est retenté automatiquement, sans jamais '
      "afficher d'écran d'erreur ni demander une action manuelle", (
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
    completers.last.completeError(Exception('échec simulé'));
    // Laisse le délai de 2s entre tentatives s'écouler, puis la
    // nouvelle tentative démarrer.
    await tester.pump(const Duration(seconds: 3));

    expect(
      callCount,
      2,
      reason: 'un échec doit déclencher une nouvelle tentative tout seul',
    );
    // Toujours aucun bouton, aucun message d'erreur : seulement le logo.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OccasionLogo), findsOneWidget);

    completers.last.completeError(Exception('échec simulé'));
    await tester.pump(const Duration(seconds: 3));
    expect(
      callCount,
      3,
      reason: 'la boucle doit continuer, pas une seule relance',
    );
  });

  testWidgets("après ~15s sans succès : affiche un indice 'ça prend du temps', "
      'toujours sans bouton ni blocage', (tester) async {
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
    expect(find.byType(OccasionLogo), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
