import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/auth_provider.dart';
import '../../services/seller_subscription_guard.dart';
import '../../shared/models/annonce.dart';
import '../providers/annonce_provider.dart';

class CreateAnnonceScreen extends ConsumerStatefulWidget {
  const CreateAnnonceScreen({super.key, this.initialAnnonce});

  final Annonce? initialAnnonce;

  @override
  ConsumerState<CreateAnnonceScreen> createState() =>
      _CreateAnnonceScreenState();
}

class _CreateAnnonceScreenState extends ConsumerState<CreateAnnonceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _phoneController = TextEditingController();

  String _category = 'Divers';
  String _condition = 'occasion';
  String _currency = 'USD';
  String _publicationStatus = 'active';
  List<XFile> _selectedImages = [];

  bool get _isEditing => widget.initialAnnonce != null;

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

  static const _conditions = <String, String>{
    'neuf': 'Neuf',
    'bon_etat': 'Bon état',
    'occasion': 'Occasion',
    'a_reparer': 'À réparer',
  };

  static const _currencies = <String>['FC', 'USD'];

  static const _publicationStatuses = <String, String>{
    'active': 'En ligne',
    'pending': 'En attente',
  };

  @override
  void initState() {
    super.initState();
    final annonce = widget.initialAnnonce;
    if (annonce == null) return;

    _titleController.text = annonce.title;
    _descriptionController.text = annonce.description;
    _priceController.text = annonce.price.toStringAsFixed(
      annonce.price.truncateToDouble() == annonce.price ? 0 : 2,
    );
    _cityController.text = annonce.city;
    _districtController.text = annonce.district;
    _phoneController.text = annonce.phone;
    _category = annonce.category.isEmpty ? 'Divers' : annonce.category;
    _condition = _conditions.containsKey(annonce.condition)
        ? annonce.condition
        : 'occasion';
    _currency = _currencies.contains(annonce.currency)
        ? annonce.currency
        : 'USD';
    _publicationStatus = _publicationStatuses.containsKey(annonce.status)
        ? annonce.status
        : (annonce.isActive ? 'active' : 'pending');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 80);
    if (!mounted) return;
    setState(() => _selectedImages = images.take(8).toList());
  }

  Future<void> _publish() async {
    if (!checkSellerSubscription(context, ref)) return;
    if (!_formKey.currentState!.validate()) return;

    final currentUser = ref.read(authNotifierProvider).currentUser;
    if (currentUser == null || !currentUser.isSeller) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connecte-toi avec ton compte vendeur.'),
        ),
      );
      return;
    }

    final price = double.tryParse(
      _priceController.text.trim().replaceAll(',', '.'),
    );
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prix invalide.')));
      return;
    }

    final city = _cityController.text.trim();
    final district = _districtController.text.trim();
    final location = [city, district]
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
    final initial = widget.initialAnnonce;
    final annonce = Annonce(
      id: initial?.id ?? '',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      price: price,
      currency: _currency,
      category: _category,
      userId: currentUser.id,
      imageUrls: initial?.imageUrls ?? const <String>[],
      location: location.isEmpty ? null : location,
      city: city,
      district: district,
      condition: _condition,
      phone: _phoneController.text.trim(),
      status: _publicationStatus,
      createdAt: initial?.createdAt,
      updatedAt: initial?.updatedAt,
      isActive: _publicationStatus == 'active',
      views: initial?.views ?? 0,
      favoritesCount: initial?.favoritesCount ?? 0,
      messagesCount: initial?.messagesCount ?? 0,
    );

    if (_isEditing) {
      await ref.read(createAnnonceProvider.notifier).update(annonce);
    } else {
      await ref
          .read(createAnnonceProvider.notifier)
          .create(annonce, _selectedImages);
    }
  }

  @override
  Widget build(BuildContext context) {
    final createState = ref.watch(createAnnonceProvider);

    ref.listen(createAnnonceProvider, (previous, next) {
      next.whenOrNull(
        data: (annonce) {
          if (annonce == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isEditing
                    ? 'Annonce modifiée avec succès.'
                    : 'Annonce publiée avec succès.',
              ),
            ),
          );
          ref.read(createAnnonceProvider.notifier).reset();
          context.go('/my-listings');
        },
        error: (error, stackTrace) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "L'annonce n'a pas pu être enregistrée. Vérifiez vos droits et réessayez.",
              ),
            ),
          );
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? "Modifier l'annonce" : 'Publier une annonce'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(
              title: 'Informations produit',
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titre',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? "Entre le titre de l'annonce"
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
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: createState.isLoading
                      ? null
                      : (value) =>
                            setState(() => _category = value ?? 'Divers'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _condition,
                  decoration: const InputDecoration(
                    labelText: 'État',
                    border: OutlineInputBorder(),
                  ),
                  items: _conditions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: createState.isLoading
                      ? null
                      : (value) =>
                            setState(() => _condition = value ?? 'occasion'),
                ),
              ],
            ),
            _Section(
              title: 'Photos',
              children: [
                OutlinedButton.icon(
                  onPressed: createState.isLoading ? null : _pickImages,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Choisir des photos'),
                ),
                if (_selectedImages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SelectedImages(images: _selectedImages),
                ] else if (_isEditing &&
                    widget.initialAnnonce!.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ExistingImages(imageUrls: widget.initialAnnonce!.imageUrls),
                ],
              ],
            ),
            _Section(
              title: 'Prix et localisation',
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Prix',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Entre le prix'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: const InputDecoration(
                          labelText: 'Devise',
                          border: OutlineInputBorder(),
                        ),
                        items: _currencies
                            .map(
                              (currency) => DropdownMenuItem(
                                value: currency,
                                child: Text(currency),
                              ),
                            )
                            .toList(),
                        onChanged: createState.isLoading
                            ? null
                            : (value) =>
                                  setState(() => _currency = value ?? 'USD'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'Ville',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Entre la ville'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _districtController,
                  decoration: const InputDecoration(
                    labelText: 'Quartier',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            _Section(
              title: 'Contact vendeur',
              children: [
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de contact',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Entre un numéro de contact'
                      : null,
                ),
              ],
            ),
            _Section(
              title: 'Publication',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _publicationStatus,
                  decoration: const InputDecoration(
                    labelText: 'Statut de publication',
                    border: OutlineInputBorder(),
                  ),
                  items: _publicationStatuses.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: createState.isLoading
                      ? null
                      : (value) =>
                            setState(() => _publicationStatus = value ?? 'active'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: createState.isLoading ? null : _publish,
                    icon: createState.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.publish_outlined),
                    label: Text(
                      createState.isLoading
                          ? 'Enregistrement...'
                          : _isEditing
                          ? "Enregistrer l'annonce"
                          : "Publier l'annonce",
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SelectedImages extends StatelessWidget {
  const _SelectedImages({required this.images});

  final List<XFile> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = images[index];
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
    );
  }
}

class _ExistingImages extends StatelessWidget {
  const _ExistingImages({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imageUrls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imageUrls[index],
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }
}
