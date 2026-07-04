import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class CompressedImage {
  const CompressedImage({
    required this.bytes,
    required this.extension,
    required this.contentType,
    required this.originalSize,
    required this.compressedSize,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
  final int originalSize;
  final int compressedSize;
  final int width;
  final int height;
}

class ImageCompressionException implements Exception {
  const ImageCompressionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImageCompressionService {
  static const defaultMaxWidth = 1600;
  static const defaultQuality = 82;

  static Future<CompressedImage> compressXFile(
    XFile file, {
    int maxWidth = defaultMaxWidth,
    int quality = defaultQuality,
  }) async {
    final originalBytes = await file.readAsBytes();
    return compressBytes(originalBytes, maxWidth: maxWidth, quality: quality);
  }

  static CompressedImage compressBytes(
    Uint8List originalBytes, {
    int maxWidth = defaultMaxWidth,
    int quality = defaultQuality,
  }) {
    if (originalBytes.isEmpty) {
      throw const ImageCompressionException('Image vide.');
    }

    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      throw const ImageCompressionException('Format image non pris en charge.');
    }

    var normalized = img.bakeOrientation(decoded);
    if (normalized.width > maxWidth) {
      normalized = img.copyResize(
        normalized,
        width: maxWidth,
        interpolation: img.Interpolation.average,
      );
    }

    final encoded = Uint8List.fromList(
      img.encodeJpg(normalized, quality: quality.clamp(60, 85).toInt()),
    );

    return CompressedImage(
      bytes: encoded,
      extension: 'jpg',
      contentType: 'image/jpeg',
      originalSize: originalBytes.length,
      compressedSize: encoded.length,
      width: normalized.width,
      height: normalized.height,
    );
  }
}
