import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/widgets/fullscreen_image_viewer.dart';

/// Avance un nombre fixe de frames au lieu de `pumpAndSettle()` : le
/// placeholder de chargement d'image anime indéfiniment en test (pas de
/// vrai réseau), donc `pumpAndSettle()` ne se termine jamais.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final urls = List.generate(5, (i) => 'https://example.com/photo$i.jpg');

  testWidgets(
    'balaie entre 5 photos et met à jour le compteur sans exception au dispose',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: FullscreenImageViewer(imageUrls: urls)),
      );
      await tester.pump();

      expect(find.text('1/5'), findsOneWidget);

      // Balaie vers la photo suivante (drag horizontal vers la gauche).
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await _settle(tester);
      expect(find.text('2/5'), findsOneWidget);

      // Balaie encore deux fois pour vérifier que la position suit bien.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await _settle(tester);
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await _settle(tester);
      expect(find.text('4/5'), findsOneWidget);

      // Le dispose (retrait du widget) ne doit lever aucune exception —
      // régression testée : le PageController était recréé à chaque
      // build() sans jamais être disposé.
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ouvre directement sur initialIndex', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenImageViewer(imageUrls: urls, initialIndex: 2),
      ),
    );
    await tester.pump();

    expect(find.text('3/5'), findsOneWidget);
  });
}
