import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/main.dart';
import 'package:occasion/widgets/occasion_logo.dart';

/// Verrouille la mécanique responsable de la régression 1.5.3+20 (timeout
/// Firebase trop court, voir le commentaire de `FirebaseBootstrap` dans
/// `lib/main.dart`) : l'écran de chargement pendant l'initialisation,
/// l'écran "Réessayer" fonctionnel en cas d'échec (jamais un blocage
/// indéfini), et une nouvelle tentative qui relance bien [bootstrap] sans
/// jamais rester bloquée sur l'ancien écran d'erreur.
///
/// Ne couvre PAS le comportement réel de `Firebase.initializeApp()` sur un
/// vrai appareil/réseau (hors de portée d'un test automatisé) — seulement
/// la structure du mécanisme autour.
void main() {
  testWidgets(
    "pendant l'initialisation : affiche le logo, jamais l'écran d'erreur",
    (tester) async {
      // Jamais résolu pendant ce test : le succès bascule vers OccasionApp,
      // qui a besoin d'une vraie initialisation Firebase (hors de portée
      // ici, voir la note en bas de fichier) — seul l'état "en attente"
      // nous intéresse.
      final completer = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          child: FirebaseBootstrap(bootstrap: () => completer.future),
        ),
      );

      expect(find.byType(OccasionLogo), findsOneWidget);
      expect(
        find.text(
          "Connexion impossible. Vérifie ta connexion internet puis réessaie.",
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    "un échec (ou timeout) affiche 'Connexion impossible' + Réessayer, "
    'jamais un blocage indéfini sur le logo',
    (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: FirebaseBootstrap(
            bootstrap: () async {
              callCount++;
              throw TimeoutException('simulé');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(callCount, 1);
      expect(
        find.text(
          "Connexion impossible. Vérifie ta connexion internet puis réessaie.",
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Réessayer'), findsOneWidget);
      expect(find.byType(OccasionLogo), findsNothing);
    },
  );

  testWidgets(
    "régression : 'Réessayer' relance bien une NOUVELLE tentative (jamais "
    "bloqué sur le premier échec, jamais besoin de redémarrer l'app)",
    (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: FirebaseBootstrap(
            bootstrap: () async {
              callCount++;
              throw Exception('échec simulé');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(callCount, 1);

      await tester.tap(find.widgetWithText(FilledButton, 'Réessayer'));
      await tester.pump();

      // La nouvelle tentative repasse bien par l'écran de chargement —
      // jamais figée sur l'ancien écran d'erreur en attendant.
      expect(find.byType(OccasionLogo), findsOneWidget);

      await tester.pumpAndSettle();
      expect(
        callCount,
        2,
        reason: 'Réessayer doit appeler bootstrap() une seconde fois',
      );
      expect(find.widgetWithText(FilledButton, 'Réessayer'), findsOneWidget);
    },
  );

  // Le chemin "succès" (bascule vers OccasionApp/_AuthGate) n'est pas testé
  // ici : il nécessiterait une vraie initialisation Firebase mockée
  // (setupFirebaseCoreMocks, absente de ce projet), hors de portée pour
  // verrouiller spécifiquement la mécanique de timeout/retry visée par ce
  // fichier.
}
