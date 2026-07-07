import 'dart:io' as io;

import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'video_compression_service.dart';

// Du plus proche du 720p cible au plus compact, si la taille dépasse
// encore le plafond après une première passe.
const _qualityLadder = [
  VideoQuality.Res1280x720Quality,
  VideoQuality.MediumQuality,
  VideoQuality.LowQuality,
];

/// Implémentation mobile réelle : transcodage via video_compress.
Future<CompressedVideo> compressVideoImpl(
  XFile source, {
  void Function(double progress)? onProgress,
}) async {
  final originalFile = io.File(source.path);
  final originalSize = await originalFile.length();

  int? trimToSeconds;
  try {
    final sourceInfo = await VideoCompress.getMediaInfo(source.path);
    final durationMs = sourceInfo.duration;
    if (durationMs != null &&
        durationMs > VideoCompressionService.maxDurationSeconds * 1000) {
      trimToSeconds = VideoCompressionService.maxDurationSeconds;
    }
  } catch (_) {
    // Si la lecture des métadonnées échoue, on compresse sans découpage.
  }

  final subscription = onProgress == null
      ? null
      : VideoCompress.compressProgress$.subscribe((progress) {
          onProgress((progress / 100).clamp(0, 1).toDouble());
        });

  try {
    for (final quality in _qualityLadder) {
      final info = await VideoCompress.compressVideo(
        source.path,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
        startTime: trimToSeconds == null ? null : 0,
        duration: trimToSeconds,
      );

      final outputFile = info?.file;
      if (info == null || outputFile == null) {
        continue;
      }

      final compressedSize = info.filesize ?? await outputFile.length();
      if (compressedSize <= VideoCompressionService.maxOutputBytes) {
        return CompressedVideo(
          file: outputFile,
          originalSize: originalSize,
          compressedSize: compressedSize,
        );
      }
    }
  } finally {
    subscription?.unsubscribe();
  }

  throw const VideoCompressionException(
    'La vidéo reste trop lourde après compression (max 12 Mo). '
    'Réessaie avec une vidéo plus courte.',
  );
}
