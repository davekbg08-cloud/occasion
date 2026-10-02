import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/theme/app_theme.dart';

void main() {
  group(
    'AppTheme.dark — barre de statut edge-to-edge (régression Android 15)',
    () {
      test(
        'appBarTheme.systemOverlayStyle force un statusBarColor transparent '
        '(sinon Android dessine son propre bandeau de contraste par-dessus)',
        () {
          final overlayStyle = AppTheme.dark().appBarTheme.systemOverlayStyle;
          expect(overlayStyle, isNotNull);
          expect(overlayStyle!.statusBarColor, Colors.transparent);
          expect(overlayStyle.statusBarIconBrightness, Brightness.light);
        },
      );
    },
  );
}
