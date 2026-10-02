import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show MethodChannelFirebase;
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/firebase_options.dart';
import 'package:occasion/services/firebase_init.dart';

/// Sur Android, le plugin Gradle google-services transforme
/// android/app/google-services.json en ressources, et le SDK natif crée
/// l'app Firebase [DEFAULT] AVANT tout code Dart. `Firebase.initializeApp()`
/// compare ensuite `DefaultFirebaseOptions.android` à cette app native et
/// lève `[core/duplicate-app]` si apiKey, databaseURL ou storageBucket
/// diffèrent. Ce test rejoue exactement cette comparaison (vrai code de
/// firebase_core, seule la couche native est simulée).
class _NativeDefaultAppFromGoogleServices implements TestFirebaseCoreHostApi {
  _NativeDefaultAppFromGoogleServices(this.nativeOptions);

  final CoreFirebaseOptions nativeOptions;

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => [
    CoreInitializeResponse(
      name: defaultFirebaseAppName,
      options: nativeOptions,
      pluginConstants: {},
    ),
  ];

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async => CoreInitializeResponse(
    name: appName,
    options: initializeAppRequest,
    pluginConstants: {},
  );

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async => nativeOptions;
}

/// Mêmes correspondances que le plugin Gradle google-services
/// (google_api_key, google_app_id, gcm_defaultSenderId, project_id,
/// google_storage_bucket, firebase_database_url).
CoreFirebaseOptions _nativeOptionsFromGoogleServicesJson(String packageName) {
  final json =
      jsonDecode(File('android/app/google-services.json').readAsStringSync())
          as Map<String, dynamic>;
  final projectInfo = json['project_info'] as Map<String, dynamic>;
  final client = (json['client'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere(
        (c) =>
            (c['client_info'] as Map)['android_client_info']['package_name'] ==
            packageName,
      );
  return CoreFirebaseOptions(
    apiKey: (client['api_key'] as List).first['current_key'] as String,
    appId: (client['client_info'] as Map)['mobilesdk_app_id'] as String,
    messagingSenderId: projectInfo['project_number'] as String,
    projectId: projectInfo['project_id'] as String,
    storageBucket: projectInfo['storage_bucket'] as String?,
    databaseURL: projectInfo['firebase_url'] as String?,
  );
}

class _UnavailableNative implements TestFirebaseCoreHostApi {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() =>
      throw Exception('services Google Play indisponibles');

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) => throw UnimplementedError();

  @override
  Future<CoreFirebaseOptions> optionsFromResource() =>
      throw UnimplementedError();
}

void _simulateNativeDefaultApp(CoreFirebaseOptions nativeOptions) {
  MethodChannelFirebase.appInstances.clear();
  MethodChannelFirebase.isCoreInitialized = false;
  TestFirebaseCoreHostApi.setUp(
    _NativeDefaultAppFromGoogleServices(nativeOptions),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('régression 1.4.0+16 → 1.5.4+21 : une app native incohérente '
      "(google-services.json sans firebase_url) n'empêche plus le démarrage, "
      "et l'incohérence est signalée", () async {
    final stale = _nativeOptionsFromGoogleServicesJson('com.occasion.app')
      ..databaseURL = null;
    _simulateNativeDefaultApp(stale);

    final result = await initializeFirebaseApp(
      options: DefaultFirebaseOptions.android,
    );

    expect(result.app.name, defaultFirebaseAppName);
    expect(result.configMismatch?.code, 'duplicate-app');
  });

  test(
    "toute autre erreur d'initialisation remonte toujours (jamais masquée)",
    () async {
      MethodChannelFirebase.appInstances.clear();
      MethodChannelFirebase.isCoreInitialized = false;
      TestFirebaseCoreHostApi.setUp(_UnavailableNative());

      await expectLater(
        initializeFirebaseApp(options: DefaultFirebaseOptions.android),
        throwsA(anything),
      );
    },
  );

  test(
    'Android : Firebase.initializeApp() accepte DefaultFirebaseOptions.android '
    "face à l'app native créée depuis google-services.json "
    '(com.occasion.app)',
    () async {
      _simulateNativeDefaultApp(
        _nativeOptionsFromGoogleServicesJson('com.occasion.app'),
      );

      final app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.android,
      );

      expect(app.name, defaultFirebaseAppName);
      expect(
        app.options.databaseURL,
        DefaultFirebaseOptions.android.databaseURL,
        reason:
            'la Realtime Database (europe-west1) doit être connue de l’app '
            'native, sinon FirebaseDatabase.instance vise la mauvaise base',
      );
    },
  );
}
