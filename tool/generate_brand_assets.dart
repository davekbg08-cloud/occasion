import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final sourcePath = args.isNotEmpty
      ? args.first
      : r'C:\Users\davek\Downloads\05D1823F-EE9D-4D04-94CB-ADED578CEE63.png';
  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    throw StateError('Logo introuvable: $sourcePath');
  }

  final source = img.decodeImage(sourceFile.readAsBytesSync());
  if (source == null) {
    throw StateError('Image logo non lisible: $sourcePath');
  }

  _writePng('assets/branding/occasion_logo.png', source, 1024);
  _writePng('assets/play_store/occasion_icon_512.png', source, 512);
  _writePng('assets/play_store/occasion_logo_1024.png', source, 1024);

  _writePng('web/favicon.png', source, 32);
  _writePng('web/icons/Icon-192.png', source, 192);
  _writePng('web/icons/Icon-512.png', source, 512);
  _writePng('web/icons/Icon-maskable-192.png', source, 192);
  _writePng('web/icons/Icon-maskable-512.png', source, 512);

  final androidIcons = <String, int>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    'android/app/src/main/res/mipmap-mdpi/launch_image.png': 96,
    'android/app/src/main/res/mipmap-hdpi/launch_image.png': 144,
    'android/app/src/main/res/mipmap-xhdpi/launch_image.png': 192,
    'android/app/src/main/res/mipmap-xxhdpi/launch_image.png': 288,
    'android/app/src/main/res/mipmap-xxxhdpi/launch_image.png': 384,
  };
  androidIcons.forEach((path, size) => _writePng(path, source, size));

  final iosIcons = <String, int>{
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': 20,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png': 60,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png': 29,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png': 58,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png': 87,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png': 40,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png': 80,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png': 120,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png': 180,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png': 76,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png': 152,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png':
        167,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
        1024,
  };
  iosIcons.forEach((path, size) => _writePng(path, source, size));

  final iosLaunchImages = <String, int>{
    'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png': 168,
    'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png': 336,
    'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png': 504,
  };
  iosLaunchImages.forEach((path, size) => _writePng(path, source, size));

  final macIcons = <String, int>{
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png': 16,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png': 32,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png': 64,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png': 128,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png': 256,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png': 512,
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png': 1024,
  };
  macIcons.forEach((path, size) => _writePng(path, source, size));

  _writeIco('windows/runner/resources/app_icon.ico', [
    16,
    24,
    32,
    48,
    64,
    128,
    256,
  ], source);
}

void _writePng(String path, img.Image source, int size) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  final resized = img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
  file.writeAsBytesSync(img.encodePng(resized, level: 6));
}

void _writeIco(String path, List<int> sizes, img.Image source) {
  final entries = <_IcoEntry>[];
  for (final size in sizes) {
    final resized = img.copyResize(
      source,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    entries.add(_IcoEntry(size, Uint8List.fromList(img.encodePng(resized))));
  }

  final bytes = BytesBuilder();
  bytes.add(_uint16(0));
  bytes.add(_uint16(1));
  bytes.add(_uint16(entries.length));

  var offset = 6 + entries.length * 16;
  for (final entry in entries) {
    bytes.addByte(entry.size == 256 ? 0 : entry.size);
    bytes.addByte(entry.size == 256 ? 0 : entry.size);
    bytes.addByte(0);
    bytes.addByte(0);
    bytes.add(_uint16(1));
    bytes.add(_uint16(32));
    bytes.add(_uint32(entry.png.length));
    bytes.add(_uint32(offset));
    offset += entry.png.length;
  }
  for (final entry in entries) {
    bytes.add(entry.png);
  }

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes.toBytes());
}

Uint8List _uint16(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

Uint8List _uint32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

class _IcoEntry {
  const _IcoEntry(this.size, this.png);

  final int size;
  final Uint8List png;
}
