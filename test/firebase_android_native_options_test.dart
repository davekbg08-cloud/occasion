import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/firebase_options.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android : Firebase.initializeApp() accepte DefaultFirebaseOptions.android '
    "face à l'app native créée depuis google-services.json "
    '(com.occasion.app)',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      TestFirebaseCoreHostApi.setUp(
        _NativeDefaultAppFromGoogleServices(
          _nativeOptionsFromGoogleServicesJson('com.occasion.app'),
        ),
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
