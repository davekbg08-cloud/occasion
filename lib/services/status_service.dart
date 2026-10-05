import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/status.dart';
import 'image_compression_service.dart';
import 'seller_subscription_service.dart';
import 'video_compression_service.dart';

enum StatusUploadPhase { compressing, uploading }

class StatusUploadProgress {
  const StatusUploadProgress(this.phase, this.progress);

  final StatusUploadPhase phase;
  final double progress;
}

class StatusService {
  StatusService([
    this._firestore,
    this._storageOverride,
    this._functionsOverride,
    this._httpClientOverride,
  ]);

  final http.Client? _httpClientOverride;

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storageOverride;
  // Résolu paresseusement (pas dans l'initializer list) pour ne jamais
  // toucher FirebaseFunctions.instance tant que toggleLike/deleteStatus ne
  // sont pas réellement appelés — évite de casser les tests qui
  // construisent ce service sans avoir initialisé Firebase.
  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  SellerSubscriptionService get _subscriptionService =>
      SellerSubscriptionService(firestore: _db);

  CollectionReference<Map<String, dynamic>> get _statuses {
    return _db.collection('statuses');
  }

  static const feedPageSize = 20;

  /// Statuts vidéo publiables par vendeur et par jour — doit rester
  /// synchronisé avec `MAX_VIDEO_STATUSES_PER_DAY` (functions/index.js),
  /// seul juge réel : ce contrôle côté app évite juste de compresser et
  /// d'envoyer une vidéo que le serveur retirerait aussitôt.
  static const maxVideoStatusesPerDay = 10;

  /// Même découpage que `statusDayKey` côté serveur : jour calendaire à
  /// l'heure de Kinshasa (UTC+1, sans heure d'été), format AAAA-MM-JJ.
  static String videoQuotaDayKey(DateTime now) {
    final kinshasa = now.toUtc().add(const Duration(hours: 1));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${kinshasa.year}-${two(kinshasa.month)}-${two(kinshasa.day)}';
  }

  /// Nombre de statuts vidéo déjà publiés aujourd'hui par [sellerId]
  /// (compteur tenu par le serveur). 0 si illisible : le serveur reste
  /// l'autorité, un échec de lecture ne doit jamais bloquer une publication.
  Future<int> videoStatusesPublishedToday(String sellerId) async {
    try {
      final snap = await _db
          .collection('statusDailyCounters')
          .doc('${sellerId}_${videoQuotaDayKey(DateTime.now())}')
          .get();
      final ids = snap.data()?['videoStatusIds'];
      return ids is List ? ids.length : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Durée de vie d'un statut dans le fil public (façon « stories »
  /// WhatsApp/Instagram) — au-delà, il n'apparaît plus dans [feed]/
  /// [fetchMoreFeed] ni dans les bulles de l'accueil, même si le document
  /// reste en base (aucune suppression : le vendeur le retrouve toujours
  /// dans son propre historique via [sellerStatuses]). Évite que le fil
  /// s'encombre indéfiniment de contenu ancien, indiscernable du récent.
  static const feedTtl = Duration(hours: 72);

  /// `createdAt` est stocké en millisecondes depuis l'epoch (voir
  /// `Status.toMap`/`fromMap`), jamais un `Timestamp` Firestore — le filtre
  /// doit comparer avec le même type, sinon la requête ne renvoie rien.
  static int _feedCutoffMillis() =>
      DateTime.now().subtract(feedTtl).millisecondsSinceEpoch;

  /// Première page du feed, en temps réel (les nouveaux statuts et les
  /// likes apparaissent immédiatement). Les pages suivantes sont chargées
  /// via [fetchMoreFeed], qui paginé avec un curseur Firestore plutôt que
  /// de tout charger d'un coup.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> feed({
    int pageSize = feedPageSize,
  }) {
    return _statuses
        .where('active', isEqualTo: true)
        .where('createdAt', isGreaterThan: _feedCutoffMillis())
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map((snap) => snap.docs);
  }

  /// Page suivante du feed après le dernier document chargé. Ponctuelle
  /// (pas de flux temps réel) : suffisant pour du contenu déjà consulté.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchMoreFeed({
    required DocumentSnapshot<Map<String, dynamic>> after,
    int pageSize = feedPageSize,
  }) async {
    final snap = await _statuses
        .where('active', isEqualTo: true)
        .where('createdAt', isGreaterThan: _feedCutoffMillis())
        .orderBy('createdAt', descending: true)
        .startAfterDocument(after)
        .limit(pageSize)
        .get();
    return snap.docs;
  }

  Stream<List<Status>> sellerStatuses(String sellerId) {
    return _statuses
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Status.fromMap({...doc.data(), 'id': doc.id}))
              .toList(),
        );
  }

  /// Codes renvoyés par `createStatusVideoUpload` pour un refus "métier"
  /// (quota, abonnement, taille…) : message déjà rédigé pour l'utilisateur,
  /// jamais contourné par le repli Firebase Storage.
  static const _r2RefusalCodes = {
    'resource-exhausted',
    'failed-precondition',
    'permission-denied',
    'invalid-argument',
    'unauthenticated',
  };

  /// Envoie une vidéo de statut sur Cloudflare R2 (bande passante gratuite,
  /// contrairement à Firebase Storage) via une adresse présignée délivrée
  /// par le serveur. Retourne l'URL publique, ou `null` si R2 est
  /// indisponible — l'appelant retombe alors sur Firebase Storage.
  Future<String?> _uploadVideoToR2(
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    final String uploadUrl;
    final String publicUrl;
    try {
      final result = await _functions
          .httpsCallable('createStatusVideoUpload')
          .call({'size': bytes.lengthInBytes});
      final data = Map<String, dynamic>.from(result.data as Map);
      uploadUrl = data['uploadUrl'] as String;
      publicUrl = data['publicUrl'] as String;
    } on FirebaseFunctionsException catch (error) {
      if (_r2RefusalCodes.contains(error.code)) {
        throw Exception(error.message ?? 'Publication refusée.');
      }
      return null;
    } catch (_) {
      return null;
    }

    return await putToPresignedUrl(uploadUrl, bytes, onProgress: onProgress)
        ? publicUrl
        : null;
  }

  /// PUT d'une vidéo vers une adresse présignée R2. Le type et la taille
  /// envoyés doivent correspondre EXACTEMENT à ceux signés par le serveur
  /// (`video/mp4`, taille du fichier), sinon R2 refuse l'envoi.
  @visibleForTesting
  Future<bool> putToPresignedUrl(
    String uploadUrl,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    final client = _httpClientOverride ?? http.Client();
    try {
      onProgress?.call(0);
      final response = await client
          .send(
            _ProgressPutRequest(
              Uri.parse(uploadUrl),
              bytes,
              contentType: 'video/mp4',
              onProgress: onProgress,
            ),
          )
          .timeout(const Duration(minutes: 3));
      await response.stream.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      onProgress?.call(1);
      return true;
    } catch (_) {
      return false;
    } finally {
      // Client créé pour cet envoi uniquement : jamais laissé ouvert.
      if (_httpClientOverride == null) client.close();
    }
  }

  Future<void> createStatus({
    required String sellerId,
    required String sellerName,
    String? sellerProfileImageUrl,
    required XFile mediaFile,
    required StatusType type,
    String? caption,
    String? productId,
    void Function(StatusUploadProgress progress)? onProgress,
  }) async {
    final hasActiveSubscription = await _subscriptionService
        .hasActiveSubscription(sellerId);
    if (!hasActiveSubscription) {
      throw Exception(
        'Un abonnement vendeur actif est nécessaire pour publier un statut. '
        'Active ou renouvelle ton abonnement.',
      );
    }

    if (type == StatusType.video &&
        await videoStatusesPublishedToday(sellerId) >= maxVideoStatusesPerDay) {
      throw Exception(
        'Limite atteinte : $maxVideoStatusesPerDay statuts vidéo par jour. '
        'Tu peux encore publier des photos, ou réessayer demain.',
      );
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = type == StatusType.video
        ? _storage.ref().child('annonces/$sellerId/statuses/$timestamp.mp4')
        : _storage.ref().child('annonces/$sellerId/statuses/$timestamp.jpg');

    String? r2MediaUrl;
    if (type == StatusType.video) {
      final Uint8List videoBytes;
      var metadata = <String, String>{};
      if (kIsWeb) {
        // Pas de transcodage natif disponible sur le web : on applique
        // uniquement le plafond de taille, sans recompression.
        videoBytes = await mediaFile.readAsBytes();
        if (videoBytes.lengthInBytes > VideoCompressionService.maxOutputBytes) {
          throw Exception(
            'La vidéo doit faire moins de '
            '${VideoCompressionService.maxOutputMegabytes} Mo (30s max).',
          );
        }
      } else {
        final compressed = await VideoCompressionService.compress(
          mediaFile,
          onProgress: (progress) => onProgress?.call(
            StatusUploadProgress(StatusUploadPhase.compressing, progress),
          ),
        );
        videoBytes = await compressed.file.readAsBytes() as Uint8List;
        metadata = {
          'originalSize': compressed.originalSize.toString(),
          'compressedSize': compressed.compressedSize.toString(),
        };
      }

      void reportUpload(double progress) => onProgress?.call(
        StatusUploadProgress(StatusUploadPhase.uploading, progress),
      );

      r2MediaUrl = await _uploadVideoToR2(videoBytes, onProgress: reportUpload);
      if (r2MediaUrl == null) {
        // Repli : R2 indisponible (réseau, configuration) — la publication
        // passe quand même, sur Firebase Storage comme avant.
        final uploadTask = ref.putData(
          videoBytes,
          SettableMetadata(contentType: 'video/mp4', customMetadata: metadata),
        );
        uploadTask.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes <= 0) return;
          reportUpload(snapshot.bytesTransferred / snapshot.totalBytes);
        });
        await uploadTask;
      }
    } else {
      final compressed = await ImageCompressionService.compressXFile(
        mediaFile,
        maxWidth: 1080,
        quality: 90,
      );
      if (compressed.compressedSize > 5 * 1024 * 1024) {
        throw Exception("L'image reste trop lourde après compression.");
      }
      await ref.putData(
        compressed.bytes,
        SettableMetadata(
          contentType: compressed.contentType,
          customMetadata: {
            'originalSize': compressed.originalSize.toString(),
            'compressedSize': compressed.compressedSize.toString(),
            'width': compressed.width.toString(),
            'height': compressed.height.toString(),
          },
        ),
      );
    }
    final mediaUrl = r2MediaUrl ?? await ref.getDownloadURL();

    final docRef = _statuses.doc();
    final status = Status(
      id: docRef.id,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerProfileImageUrl: sellerProfileImageUrl,
      mediaUrl: mediaUrl,
      type: type,
      caption: caption,
      productId: productId,
      status: 'published',
      active: true,
      createdAt: DateTime.now(),
    );

    await docRef.set(status.toMap());
  }

  /// Bascule le like côté serveur (transaction anti-double-like, voir
  /// `functions/index.js::toggleStatusLike`) — `likesCount` n'est plus
  /// modifiable directement par le client (`firestore.rules`).
  Future<bool> toggleLike(String statusId) async {
    final result = await _functions.httpsCallable('toggleStatusLike').call({
      'statusId': statusId,
    });
    return (result.data as Map)['liked'] as bool;
  }

  /// Identifiants des statuts déjà likés par [userId] (lecture ponctuelle,
  /// utilisée pour restaurer l'état "j'ai déjà aimé" après reconnexion —
  /// jamais persisté seulement en mémoire côté client).
  Future<Set<String>> likedStatusIds(String userId) async {
    final snap = await _db
        .collection('statusLikes')
        .where('userId', isEqualTo: userId)
        .get();
    return snap.docs
        .map((doc) => doc.data()['statusId'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Marque [statusId] comme vu par [userId] (bulle "stories" de
  /// l'accueil) — écriture cliente directe (pas de compteur agrégé à
  /// protéger, contrairement aux likes), id déterministe pour qu'une
  /// relance n'écrive jamais deux fois la même marque.
  Future<void> markViewed(String statusId, String userId) {
    return _db.collection('statusViews').doc('${statusId}_$userId').set({
      'statusId': statusId,
      'userId': userId,
      'viewedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Identifiants des statuts déjà vus par [userId] — même principe que
  /// [likedStatusIds] : lecture ponctuelle pour restaurer l'état "déjà vu"
  /// après reconnexion, jamais gardé seulement en mémoire côté client.
  Future<Set<String>> viewedStatusIds(String userId) async {
    final snap = await _db
        .collection('statusViews')
        .where('userId', isEqualTo: userId)
        .get();
    return snap.docs
        .map((doc) => doc.data()['statusId'] as String?)
        .whereType<String>()
        .toSet();
  }

  /// Suppression côté serveur (voir `functions/index.js::deleteStatus`) :
  /// nettoie aussi le fichier Storage et les `statusLikes` associés, ce
  /// qu'une suppression Firestore directe ne ferait pas.
  Future<void> deleteStatus(String statusId) async {
    await _functions.httpsCallable('deleteStatus').call({'statusId': statusId});
  }
}

/// Requête PUT dont le corps est émis par morceaux à la demande de la
/// connexion : sur mobile, la progression suit donc réellement l'envoi
/// (le navigateur, lui, lit tout d'un coup — la barre saute alors à 100 %).
class _ProgressPutRequest extends http.BaseRequest {
  _ProgressPutRequest(
    Uri url,
    this._bytes, {
    required String contentType,
    this.onProgress,
  }) : super('PUT', url) {
    headers['content-type'] = contentType;
    contentLength = _bytes.lengthInBytes;
  }

  final Uint8List _bytes;
  final void Function(double progress)? onProgress;

  static const _chunkSize = 64 * 1024;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    final total = _bytes.lengthInBytes;
    for (var offset = 0; offset < total; offset += _chunkSize) {
      final end = offset + _chunkSize < total ? offset + _chunkSize : total;
      yield Uint8List.sublistView(_bytes, offset, end);
      onProgress?.call(end / total);
    }
  }
}
