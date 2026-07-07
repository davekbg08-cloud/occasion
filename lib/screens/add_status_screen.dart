import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/status.dart';
import '../providers/auth_provider.dart';
import '../providers/status_provider.dart';
import '../services/status_service.dart';

class AddStatusScreen extends ConsumerStatefulWidget {
  const AddStatusScreen({super.key});

  @override
  ConsumerState<AddStatusScreen> createState() => _AddStatusScreenState();
}

class _AddStatusScreenState extends ConsumerState<AddStatusScreen> {
  XFile? _file;
  StatusType? _type;
  VideoPlayerController? _videoController;
  final _captionController = TextEditingController();
  final _productIdController = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _captionController.dispose();
    _productIdController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // Un statut est un contenu éphémère consulté en plein écran mobile :
  // pas besoin de la résolution/qualité maximale utilisée pour les
  // annonces, ce qui réduit le coût de stockage/bande passante Firebase.
  static const _feedImageMaxWidth = 1080.0;
  static const _feedVideoMaxDuration = Duration(seconds: 30);

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: _feedImageMaxWidth,
    );
    if (picked == null) return;

    _videoController?.dispose();
    setState(() {
      _file = picked;
      _type = StatusType.image;
      _videoController = null;
    });
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: _feedVideoMaxDuration,
    );
    if (picked == null) return;

    final controller = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(picked.path))
        : VideoPlayerController.file(io.File(picked.path));
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();

    _videoController?.dispose();
    setState(() {
      _file = picked;
      _type = StatusType.video;
      _videoController = controller;
    });
  }

  Future<void> _publish() async {
    final file = _file;
    final type = _type;
    if (file == null || type == null) return;

    final user = ref.read(authNotifierProvider).currentUser;
    if (user == null) return;

    final success = await ref
        .read(statusNotifierProvider.notifier)
        .createStatus(
          sellerId: user.id,
          sellerName: user.name,
          sellerProfileImageUrl: user.profileImageUrl,
          mediaFile: file,
          type: type,
          caption: _captionController.text.trim().isEmpty
              ? null
              : _captionController.text.trim(),
          productId: _productIdController.text.trim().isEmpty
              ? null
              : _productIdController.text.trim(),
        );

    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
      return;
    }

    final error = ref.read(statusNotifierProvider).error;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_friendlyStatusError(error))));
  }

  String _friendlyStatusError(String? error) {
    final message = error ?? '';
    if (message.contains('permission-denied') ||
        message.contains('unauthorized')) {
      return 'Publication refusée. Vérifiez votre session vendeur.';
    }
    if (message.contains('network')) {
      return 'Connexion réseau indisponible. Réessayez.';
    }
    if (message.contains('abonnement')) {
      return 'Un abonnement vendeur actif est nécessaire pour publier un '
          'statut.';
    }
    return 'Publication impossible pour le moment.';
  }

  @override
  Widget build(BuildContext context) {
    final statusState = ref.watch(statusNotifierProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Nouveau statut',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: _file != null && !statusState.isUploading
                ? _publish
                : null,
            child: statusState.isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  )
                : const Text(
                    'Publier',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (statusState.isUploading)
            _UploadProgressBanner(progress: statusState.uploadProgress),
          Expanded(
            child: _file == null
                ? _PickerPlaceholder(
                    onPickImage: _pickImage,
                    onPickVideo: _pickVideo,
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      _MediaPreview(
                        file: _file!,
                        type: _type!,
                        controller: _videoController,
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _RefreshButton(
                          onTap: _type == StatusType.image
                              ? _pickImage
                              : _pickVideo,
                        ),
                      ),
                    ],
                  ),
          ),
          if (_file != null)
            Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    TextField(
                      controller: _captionController,
                      enabled: !statusState.isUploading,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Ajouter une description...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        border: InputBorder.none,
                      ),
                    ),
                    Divider(color: Colors.grey[800]),
                    TextField(
                      controller: _productIdController,
                      enabled: !statusState.isUploading,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'ID produit lié (optionnel)',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        border: InputBorder.none,
                      ),
                    ),
                    Divider(color: Colors.grey[800]),
                    Row(
                      children: [
                        _QuickButton(
                          icon: Icons.image,
                          label: 'Changer image',
                          onTap: _pickImage,
                        ),
                        const SizedBox(width: 20),
                        _QuickButton(
                          icon: Icons.videocam,
                          label: 'Changer vidéo',
                          onTap: _pickVideo,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickerPlaceholder extends StatelessWidget {
  const _PickerPlaceholder({
    required this.onPickImage,
    required this.onPickVideo,
  });

  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.add_photo_alternate_outlined,
            color: Colors.grey,
            size: 72,
          ),
          const SizedBox(height: 16),
          const Text(
            'Sélectionnez un média',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MediaTypeButton(
                icon: Icons.image,
                label: 'Image',
                onTap: onPickImage,
              ),
              const SizedBox(width: 24),
              _MediaTypeButton(
                icon: Icons.videocam,
                label: 'Vidéo',
                onTap: onPickVideo,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaTypeButton extends StatelessWidget {
  const _MediaTypeButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[700]!),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.file,
    required this.type,
    required this.controller,
  });

  final XFile file;
  final StatusType type;
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    if (type == StatusType.image) {
      return FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return Image.memory(snapshot.data!, fit: BoxFit.contain);
        },
      );
    }

    final video = controller;
    if (video != null && video.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: video.value.aspectRatio,
          child: VideoPlayer(video),
        ),
      );
    }

    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}

class _UploadProgressBanner extends StatelessWidget {
  const _UploadProgressBanner({required this.progress});

  final StatusUploadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress?.progress;
    final label = switch (progress?.phase) {
      StatusUploadPhase.compressing => 'Compression de la vidéo...',
      StatusUploadPhase.uploading => 'Envoi en cours...',
      null => 'Préparation...',
    };
    final percent = value == null ? null : (value.clamp(0, 1) * 100).round();

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            percent == null ? label : '$label $percent%',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value?.clamp(0, 1),
              minHeight: 4,
              backgroundColor: Colors.grey[800],
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.refresh, color: Colors.white, size: 20),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 18),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}
