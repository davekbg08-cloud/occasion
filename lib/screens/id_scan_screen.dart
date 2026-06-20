import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/id_document_parser.dart';

class IdScanScreen extends ConsumerStatefulWidget {
  const IdScanScreen({super.key});

  @override
  ConsumerState<IdScanScreen> createState() => _IdScanScreenState();
}

class _IdScanScreenState extends ConsumerState<IdScanScreen> {
  CameraController? _cameraController;
  bool _isInitializing = true;
  bool _isProcessing = false;
  String _recognizedText = '';
  String _extractedInfo = '';
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializing = true;
      _cameraError = null;
    });

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _cameraError = 'Permission camera refusee';
          _isInitializing = false;
        });
        _showSnack('Permission camera refusee', Colors.red);
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cameraError = 'Aucune camera disponible';
          _isInitializing = false;
        });
        return;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = "Impossible d'initialiser la camera : $e";
        _isInitializing = false;
      });
    }
  }

  Future<void> _takePictureAndScan() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isProcessing) {
      return;
    }

    setState(() => _isProcessing = true);

    TextRecognizer? textRecognizer;
    try {
      final picture = await controller.takePicture();
      final imageFile = File(picture.path);
      final inputImage = InputImage.fromFile(imageFile);

      textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      final parsedInfo = IdDocumentParser.parse(recognizedText.text);

      if (!mounted) return;
      setState(() {
        _recognizedText = recognizedText.text;
        _extractedInfo = parsedInfo;
      });

      _showSnack(
        parsedInfo.isNotEmpty && !parsedInfo.startsWith('Texte detecte')
            ? 'Informations extraites avec succes'
            : 'Texte detecte mais aucune info structuree',
        parsedInfo.isNotEmpty && !parsedInfo.startsWith('Texte detecte')
            ? Colors.green
            : Colors.orange,
      );
    } catch (e) {
      if (mounted) {
        _showSnack("Erreur lors de l'analyse : $e", Colors.red);
      }
    } finally {
      await textRecognizer?.close();
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner document'),
        actions: [
          IconButton(
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.account_circle),
            tooltip: 'Mon compte',
          ),
          IconButton(
            onPressed: _isInitializing ? null : _initializeCamera,
            icon: const Icon(Icons.refresh),
            tooltip: 'Relancer la camera',
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _CameraArea(
              controller: controller,
              isInitializing: _isInitializing,
              cameraError: _cameraError,
            ),
          ),
          const _GuideFrame(),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ResultPanel(
              extractedInfo: _extractedInfo,
              recognizedText: _recognizedText,
              isProcessing: _isProcessing,
              onScan: _takePictureAndScan,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraArea extends StatelessWidget {
  const _CameraArea({
    required this.controller,
    required this.isInitializing,
    required this.cameraError,
  });

  final CameraController? controller;
  final bool isInitializing;
  final String? cameraError;

  @override
  Widget build(BuildContext context) {
    if (cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            cameraError!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    if (isInitializing ||
        controller == null ||
        !controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(child: CameraPreview(controller!)),
    );
  }
}

class _GuideFrame extends StatelessWidget {
  const _GuideFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: Container(
          width: 320,
          height: 210,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.greenAccent, width: 4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Placez le document ici',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.extractedInfo,
    required this.recognizedText,
    required this.isProcessing,
    required this.onScan,
  });

  final String extractedInfo;
  final String recognizedText;
  final bool isProcessing;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        color: Colors.black87,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (extractedInfo.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    extractedInfo,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ),
              )
            else if (recognizedText.isEmpty)
              const Text(
                "CNI, passeport ou carte d'electeur: prenez une photo nette.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isProcessing ? null : onScan,
              icon: const Icon(Icons.camera_alt),
              label: Text(
                isProcessing
                    ? 'Analyse en cours...'
                    : 'Prendre photo et scanner',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
