import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:occasion/services/status_service.dart';

void main() {
  group('StatusService.putToPresignedUrl (envoi vers Cloudflare R2)', () {
    test('PUT avec exactement le type signé par le serveur et le fichier '
        'intact, progression jusqu\'à 100 %', () async {
      final bytes = Uint8List.fromList(
        List<int>.generate(200 * 1024, (i) => i % 251),
      );
      late http.Request received;
      final client = MockClient((request) async {
        received = request;
        return http.Response('', 200);
      });
      final service = StatusService(
        FakeFirebaseFirestore(),
        null,
        null,
        client,
      );
      final progress = <double>[];

      final ok = await service.putToPresignedUrl(
        'https://acct.r2.cloudflarestorage.com/occasion-videos/statuses/u1/v.mp4?X-Amz-Signature=abc',
        bytes,
        onProgress: progress.add,
      );

      expect(ok, isTrue);
      expect(received.method, 'PUT');
      expect(received.headers['content-type'], 'video/mp4');
      expect(received.bodyBytes, bytes);
      expect(received.url.queryParameters['X-Amz-Signature'], 'abc');
      expect(progress.first, 0);
      expect(progress.last, 1);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    });

    test('un refus de R2 (signature expirée, taille différente…) renvoie '
        'false pour déclencher le repli Firebase Storage', () async {
      final client = MockClient((_) async => http.Response('denied', 403));
      final service = StatusService(
        FakeFirebaseFirestore(),
        null,
        null,
        client,
      );

      final ok = await service.putToPresignedUrl(
        'https://acct.r2.cloudflarestorage.com/occasion-videos/x.mp4',
        Uint8List(10),
      );

      expect(ok, isFalse);
    });

    test('une coupure réseau renvoie false, jamais une exception', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('réseau'),
      );
      final service = StatusService(
        FakeFirebaseFirestore(),
        null,
        null,
        client,
      );

      final ok = await service.putToPresignedUrl(
        'https://acct.r2.cloudflarestorage.com/occasion-videos/x.mp4',
        Uint8List(10),
      );

      expect(ok, isFalse);
    });

    test('avec le vrai client HTTP : Content-Length exact, jamais d\'envoi '
        '"chunked" (R2 rejetterait la signature)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bytes = Uint8List.fromList(List<int>.filled(300 * 1024, 7));
      final seen = <String, Object?>{};
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        seen['length'] = request.headers.contentLength;
        seen['chunked'] = request.headers.chunkedTransferEncoding;
        seen['type'] = request.headers.value('content-type');
        seen['bodyLength'] = body.length;
        request.response.statusCode = 200;
        await request.response.close();
      });

      final ok = await StatusService(FakeFirebaseFirestore()).putToPresignedUrl(
        'http://127.0.0.1:${server.port}/occasion-videos/v.mp4',
        bytes,
      );

      expect(ok, isTrue);
      expect(seen['length'], bytes.length);
      expect(seen['chunked'], isFalse);
      expect(seen['type'], 'video/mp4');
      expect(seen['bodyLength'], bytes.length);
    });
  });
}
