import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../models/status.dart' show StatusType;
import 'image_compression_service.dart';
import 'video_compression_service.dart';

/// Résultat d'un upload réussi — c'est tout ce qui a besoin de survivre à
/// un redémarrage de l'app (voir `PendingChatMessage.mediaUrl`), jamais les
/// octets bruts de l'image/vidéo.
class ChatMediaUploadResult {
  const ChatMediaUploadResult({
    required this.url,
    required this.type,
    this.width,
    this.height,
  });

  final String url;
  final StatusType type;
  final int? width;
  final int? height;
}

/// Upload d'une photo/vidéo de chat vers `chatMedia/{chatId}/{clientMessageId}.ext`
/// — le même `clientMessageId` que le message qui la référencera, pour que
/// le chemin Storage soit directement gouverné par `storage.rules`
/// (`isChatParticipant(chatId)`, voir ce fichier). Aucune tentative de
/// reprise après une fermeture de l'app en plein upload : tant que
/// [upload] n'a pas renvoyé son résultat, rien n'est persisté localement
/// (voir le commentaire de `PendingChatMessage`) — un échec ici se retente
/// simplement en repartant de zéro (nouveau `clientMessageId`), jamais en
/// essayant de reprendre un transfert partiel.
class ChatMediaUploadService {
  ChatMediaUploadService([this._storageOverride]);

  final FirebaseStorage? _storageOverride;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  static const int maxImageBytes = 5 * 1024 * 1024;
  static const int maxVideoBytes = 25 * 1024 * 1024;

  Future<ChatMediaUploadResult> upload({
    required String chatId,
    required String clientMessageId,
    required XFile mediaFile,
    required StatusType type,
    void Function(double progress)? onProgress,
  }) {
    return type == StatusType.video
        ? _uploadVideo(chatId, clientMessageId, mediaFile, onProgress)
        : _uploadImage(chatId, clientMessageId, mediaFile, onProgress);
  }

  Future<ChatMediaUploadResult> _uploadImage(
    String chatId,
    String clientMessageId,
    XFile file,
    void Function(double progress)? onProgress,
  ) async {
    final compressed = await ImageCompressionService.compressXFile(
      file,
      maxWidth: 1600,
      quality: 80,
    );
    if (compressed.compressedSize > maxImageBytes) {
      throw Exception('L\'image reste trop lourde après compression.');
    }

    final ref = _storage.ref().child('chatMedia/$chatId/$clientMessageId.jpg');
    final task = ref.putData(
      compressed.bytes,
      SettableMetadata(
        contentType: compressed.contentType,
        customMetadata: {
          'originalSize': compressed.originalSize.toString(),
          'compressedSize': compressed.compressedSize.toString(),
        },
      ),
    );
    _listenProgress(task, onProgress);
    await task;
    final url = await ref.getDownloadURL();

    return ChatMediaUploadResult(
      url: url,
      type: StatusType.image,
      width: compressed.width,
      height: compressed.height,
    );
  }

  Future<ChatMediaUploadResult> _uploadVideo(
    String chatId,
    String clientMessageId,
    XFile file,
    void Function(double progress)? onProgress,
  ) async {
    final ref = _storage.ref().child('chatMedia/$chatId/$clientMessageId.mp4');

    if (kIsWeb) {
      // Pas de transcodage natif disponible sur le web : on applique
      // uniquement le plafond de taille, sans recompression (même
      // limitation que le flux de statuts, voir `status_service.dart`).
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > maxVideoBytes) {
        throw Exception('La vidéo doit faire moins de 25 Mo.');
      }
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'video/mp4'),
      );
      _listenProgress(task, onProgress);
      await task;
    } else {
      final compressed = await VideoCompressionService.compress(file);
      final task = ref.putFile(
        compressed.file,
        SettableMetadata(
          contentType: 'video/mp4',
          customMetadata: {
            'originalSize': compressed.originalSize.toString(),
            'compressedSize': compressed.compressedSize.toString(),
          },
        ),
      );
      _listenProgress(task, onProgress);
      await task;
    }

    final url = await ref.getDownloadURL();
    return ChatMediaUploadResult(url: url, type: StatusType.video);
  }

  void _listenProgress(
    UploadTask task,
    void Function(double progress)? onProgress,
  ) {
    if (onProgress == null) return;
    task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes <= 0) return;
      onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
    });
  }
}
