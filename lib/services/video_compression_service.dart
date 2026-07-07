import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

class CompressedVideo {
  const CompressedVideo({
    required this.file,
    required this.originalSize,
    required this.compressedSize,
  });

  final io.File file;
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
class VideoCompressionService {
  static const maxDurationSeconds = 30;
  static const maxOutputBytes = 12 * 1024 * 1024;

  // Du plus proche du 720p cible au plus compact, si la taille dépasse
  // encore le plafond après une première passe.
  static const _qualityLadder = [
    VideoQuality.Res1280x720Quality,
    VideoQuality.MediumQuality,
    VideoQuality.LowQuality,
  ];

  static Future<CompressedVideo> compress(
    XFile source, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw const VideoCompressionException(
        'La compression vidéo n’est pas disponible sur le web.',
      );
    }

    final originalFile = io.File(source.path);
    final originalSize = await originalFile.length();

    int? trimToSeconds;
    try {
      final sourceInfo = await VideoCompress.getMediaInfo(source.path);
      final durationMs = sourceInfo.duration;
      if (durationMs != null && durationMs > maxDurationSeconds * 1000) {
        trimToSeconds = maxDurationSeconds;
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
        if (compressedSize <= maxOutputBytes) {
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
}
