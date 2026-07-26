import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift_catalog_item.dart';
import '../providers/auth_provider.dart';
import '../providers/gift_catalog_provider.dart';

class SellerGiftCatalogScreen extends ConsumerWidget {
  const SellerGiftCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellerId = ref.watch(authNotifierProvider).currentUser?.id ?? '';
    final itemsAsync = ref.watch(sellerGiftCatalogProvider(sellerId));

    return Scaffold(
      appBar: AppBar(title: const Text('Mon catalogue de cadeaux')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context, ref, sellerId: sellerId),
        child: const Icon(Icons.add),
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            const Center(child: Text('Impossible de charger le catalogue.')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ajoutez des cadeaux que vos clients pourront échanger '
                  'contre les points de fidélité gagnés chez vous.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.pointsCost} points · ${item.isActive ? "Actif" : "Inactif"}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Modifier',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openForm(
                          context,
                          ref,
                          sellerId: sellerId,
                          item: item,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref
                            .read(giftCatalogRepositoryProvider)
                            .deleteItem(item.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    required String sellerId,
    GiftCatalogItem? item,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _GiftItemFormDialog(sellerId: sellerId, item: item),
    );
  }
}

class _GiftItemFormDialog extends ConsumerStatefulWidget {
  const _GiftItemFormDialog({required this.sellerId, this.item});

  final String sellerId;
  final GiftCatalogItem? item;

  @override
  ConsumerState<_GiftItemFormDialog> createState() =>
      _GiftItemFormDialogState();
}

class _GiftItemFormDialogState extends ConsumerState<_GiftItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(
    text: widget.item?.title ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.item?.description ?? '',
  );
  late final _pointsController = TextEditingController(
    text: widget.item?.pointsCost.toString() ?? '',
  );
  late bool _isActive = widget.item?.isActive ?? true;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _pointsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final item = GiftCatalogItem(
      id: widget.item?.id ?? '',
      sellerId: widget.sellerId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      pointsCost: int.tryParse(_pointsController.text.trim()) ?? 0,
      isActive: _isActive,
    );

    try {
      final repository = ref.read(giftCatalogRepositoryProvider);
      if (widget.item == null) {
        await repository.createItem(item);
      } else {
        await repository.updateItem(item);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de l\'enregistrement.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.item == null ? 'Nouveau cadeau' : 'Modifier le cadeau',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Titre obligatoire'
                    : null,
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
              TextFormField(
                controller: _pointsController,
                decoration: const InputDecoration(labelText: 'Coût en points'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Nombre de points invalide';
                  }
                  return null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actif (visible des acheteurs)'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
