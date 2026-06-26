import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/auth_provider.dart';
import '../../shared/models/annonce.dart';
import '../providers/annonce_provider.dart';

class CreateAnnonceScreen extends ConsumerStatefulWidget {
  const CreateAnnonceScreen({super.key});

  @override
  ConsumerState<CreateAnnonceScreen> createState() => _CreateAnnonceScreenState();
}

class _CreateAnnonceScreenState extends ConsumerState<CreateAnnonceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();

  String _category = 'Divers';
  String _currency = 'USD';
  List<XFile> _selectedImages = [];

  static const _categories = <String>[
    'Divers',
    'Véhicules',
    'Immobilier',
    'Téléphones',
    'Électronique',
    'Mode',
    'Maison',
    'Services',
  ];

  static const _currencies = <String>['USD', 'FC'];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 80);
    if (!mounted) return;
    setState(() => _selectedImages = images.take(8).toList());
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = ref.read(authNotifierProvider).currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connecte-toi avant de publier une annonce.')),
      );
      return;
    }

    final price = double.tryParse(_priceController.text.trim().replaceAll(',', '.'));
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prix invalide.')),
      );
      return;
    }

    final annonce = Annonce(
      id: '',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      price: price,
      currency: _currency,
      category: _category,
      userId: currentUser.id,
      imageUrls: const <String>[],
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
    );

    await ref.read(createAnnonceProvider.notifier).create(annonce, _selectedImages);
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createAnnonceProvider);

    ref.listen(createAnnonceProvider, (previous, next) {
      next.whenOrNull(
        data: (annonce) {
          if (annonce == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Annonce publiée avec succès.')),
          );
          _formKey.currentState?.reset();
          _titleController.clear();
          _descriptionController.clear();
          _priceController.clear();
          _locationController.clear();
          setState(() {
            _category = 'Divers';
            _currency = 'USD';
            _selectedImages = [];
          });
          ref.read(createAnnonceProvider.notifier).reset();
        },
        error: (error, stackTrace) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Créer une annonce')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              OutlinedButton.icon(
                onPressed: createState.isLoading ? null : _pickImages,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Choisir des images'),
              ),
              if (_selectedImages.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final image = _selectedImages[index];
                      return FutureBuilder(
                        future: image.readAsBytes(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox(
                              width: 100,
                              height: 100,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              snapshot.data!,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Titre',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Entre le titre de l’annonce'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Entre une description'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Prix',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Entre le prix'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: const InputDecoration(
                        labelText: 'Devise',
                        border: OutlineInputBorder(),
                      ),
                      items: _currencies
                          .map((currency) => DropdownMenuItem(
                                value: currency,
                                child: Text(currency),
                              ))
                          .toList(),
                      onChanged: createState.isLoading
                          ? null
                          : (value) => setState(() => _currency = value ?? 'USD'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Catégorie',
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map((category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ))
                    .toList(),
                onChanged: createState.isLoading
                    ? null
                    : (value) => setState(() => _category = value ?? 'Divers'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Localisation',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: createState.isLoading ? null : _publish,
                child: createState.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Publier l’annonce'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
