import 'package:image_picker/image_picker.dart';

// Import conditionnel : sur le web on charge le stub (aucune dépendance
// native, aucun `dart:io`), sur mobile l'implémentation réelle basée sur
// video_compress. C'est ce qui permet à `flutter build web` de compiler.
import 'video_compression_service_stub.dart'
    if (dart.library.io) 'video_compression_service_io.dart';

/// Résultat d'une compression vidéo. Le champ `file` est volontairement
/// typé `dynamic` ici pour éviter d'exposer `dart:io` au web ; côté mobile
/// c'est un `io.File`, directement utilisable par `putFile`.
class CompressedVideo {
  const CompressedVideo({
    required this.file,
    required this.originalSize,
    required this.compressedSize,
  });

  final dynamic file;
  final int originalSize;
  final int compressedSize;
}

class VideoCompressionException implements Exception {
  const VideoCompressionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Compresse une vidéo de statut/feed en MP4 H.264 + AAC, 720p max,
/// 30s max, avec un objectif d'environ 5 Mo et un plafond strict de 12 Mo.
///
/// L'implémentation réelle vit dans `video_compression_service_io.dart`
/// (mobile) ; sur le web, le stub lève une exception car aucun transcodage
/// natif n'est disponible (le web applique seulement le plafond de taille).
class VideoCompressionService {
  static const maxDurationSeconds = 30;
  static const maxOutputBytes = 12 * 1024 * 1024;

  static Future<CompressedVideo> compress(
    XFile source, {
    void Function(double progress)? onProgress,
  }) {
    return compressVideoImpl(source, onProgress: onProgress);
  }
}
