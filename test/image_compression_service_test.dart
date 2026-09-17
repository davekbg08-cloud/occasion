import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:occasion/services/image_compression_service.dart';

/// Image synthétique avec assez de détail (dégradé + bruit) pour que la
/// qualité JPEG choisie influence réellement la taille du fichier — une
/// image unie compresserait pareil à toute qualité et ne détecterait pas
/// une régression du plafond de qualité.
Uint8List _noisyTestImageBytes() {
  final image = img.Image(width: 200, height: 200);
  var seed = 42;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final r = (x * 255 ~/ image.width) ^ (seed & 0xff);
      final g = (y * 255 ~/ image.height) ^ ((seed >> 8) & 0xff);
      final b = (seed >> 16) & 0xff;
      image.setPixelRgb(x, y, r & 0xff, g & 0xff, b);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('ImageCompressionService', () {
    late Uint8List source;

    setUp(() {
      source = _noisyTestImageBytes();
    });

    test('régression : une qualité demandée de 90 n\'est plus silencieusement '
        'ramenée à 85 (plafond relevé à 92) — produit un fichier au moins '
        'aussi lourd qu\'à qualité 70, jamais identique', () {
      final low = ImageCompressionService.compressBytes(source, quality: 70);
      final high = ImageCompressionService.compressBytes(source, quality: 90);

      expect(high.compressedSize, greaterThan(low.compressedSize));
    });

    test('la qualité par défaut est désormais 90 (pas 82)', () {
      expect(ImageCompressionService.defaultQuality, 90);
    });

    test('une qualité extrême (99) reste plafonnée à 92, jamais au-delà', () {
      final capped = ImageCompressionService.compressBytes(source, quality: 99);
      final atCap = ImageCompressionService.compressBytes(source, quality: 92);

      expect(capped.compressedSize, atCap.compressedSize);
    });
  });
}
