import 'package:image_picker/image_picker.dart';

import 'video_compression_service.dart';

/// Implémentation web : aucun transcodage natif possible.
/// Le code appelant (status_service) ne doit jamais appeler ceci sur le web
/// (il passe par readAsBytes + putData), mais on fournit un stub sûr au cas où.
Future<CompressedVideo> compressVideoImpl(
  XFile source, {
  void Function(double progress)? onProgress,
}) async {
  throw const VideoCompressionException(
    'La compression vidéo n\'est pas disponible sur le web.',
  );
}
