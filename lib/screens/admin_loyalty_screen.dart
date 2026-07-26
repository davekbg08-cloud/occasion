import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/loyalty_points_provider.dart';

/// Remise à zéro exceptionnelle du solde de points d'un acheteur chez un
/// vendeur donné. Action rare et sensible : motif obligatoire, tracé côté
/// serveur dans `loyaltyPointsAuditLog` (voir `adminResetLoyaltyPoints`).
class AdminLoyaltyScreen extends ConsumerStatefulWidget {
  const AdminLoyaltyScreen({super.key});

  @override
  ConsumerState<AdminLoyaltyScreen> createState() => _AdminLoyaltyScreenState();
}

class _AdminLoyaltyScreenState extends ConsumerState<AdminLoyaltyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _buyerIdController = TextEditingController();
  final _sellerIdController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _buyerIdController.dispose();
    _sellerIdController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmer la remise à zéro'),
        content: Text(
          'Le solde de points de l\'acheteur ${_buyerIdController.text.trim()} '
          'chez le vendeur ${_sellerIdController.text.trim()} sera remis à 0. '
          'Cette action est tracée et irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(loyaltyServiceProvider)
          .adminResetLoyaltyPoints(
            buyerId: _buyerIdController.text.trim(),
            sellerId: _sellerIdController.text.trim(),
            reason: _reasonController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Solde remis à zéro.')));
      _buyerIdController.clear();
      _sellerIdController.clear();
      _reasonController.clear();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Échec de la réinitialisation.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/profile'),
        ),
        title: const Text('Remise à zéro des points (exceptionnelle)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Action réservée aux cas exceptionnels (fraude avérée, '
                'erreur de crédit massive...). Chaque réinitialisation est '
                'enregistrée avec le motif fourni.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _buyerIdController,
                decoration: const InputDecoration(
                  labelText: 'ID de l\'acheteur',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Obligatoire'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sellerIdController,
                decoration: const InputDecoration(labelText: 'ID du vendeur'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Obligatoire'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Motif'),
                maxLines: 3,
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Un motif est obligatoire'
                    : null,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Remettre à zéro'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
