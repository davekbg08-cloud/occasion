import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/providers/app_update_provider.dart';
import 'package:occasion/services/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _FakeAppUpdateService implements AppUpdateService {
  final _controller = StreamController<int?>.broadcast();

  void emit(int? value) => _controller.add(value);

  @override
  Stream<int?> minAndroidVersionCode() => _controller.stream;
}

void main() {
  Future<void> mockInstalledBuildNumber(String buildNumber) async {
    PackageInfo.setMockInitialValues(
      appName: 'Occasion',
      packageName: 'com.occasion.app',
      version: '1.5.0',
      buildNumber: buildNumber,
      buildSignature: '',
    );
  }

  group('forceUpdateRequiredProvider', () {
    test(
      'ni seuil ni version installée encore résolus : jamais bloquant',
      () async {
        await mockInstalledBuildNumber('17');
        final fake = _FakeAppUpdateService();
        final container = ProviderContainer(
          overrides: [appUpdateServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        expect(container.read(forceUpdateRequiredProvider), isFalse);
      },
    );

    test('version installée strictement sous le seuil : bloque', () async {
      await mockInstalledBuildNumber('16');
      final fake = _FakeAppUpdateService();
      final container = ProviderContainer(
        overrides: [appUpdateServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      // Force la résolution des deux providers avant de lire la décision.
      await container.read(installedVersionCodeProvider.future);
      container.listen(minAndroidVersionCodeProvider, (_, _) {});
      fake.emit(17);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(container.read(forceUpdateRequiredProvider), isTrue);
    });

    test(
      'version installée égale ou au-dessus du seuil : jamais bloquant',
      () async {
        await mockInstalledBuildNumber('17');
        final fake = _FakeAppUpdateService();
        final container = ProviderContainer(
          overrides: [appUpdateServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        await container.read(installedVersionCodeProvider.future);
        container.listen(minAndroidVersionCodeProvider, (_, _) {});
        fake.emit(17);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(container.read(forceUpdateRequiredProvider), isFalse);

        fake.emit(16);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        expect(container.read(forceUpdateRequiredProvider), isFalse);
      },
    );

    test(
      'régression : un buildNumber non numérique retombe sur 0, jamais une exception',
      () async {
        await mockInstalledBuildNumber('not-a-number');
        final fake = _FakeAppUpdateService();
        final container = ProviderContainer(
          overrides: [appUpdateServiceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        final installed = await container.read(
          installedVersionCodeProvider.future,
        );
        expect(installed, 0);
      },
    );
  });
}
