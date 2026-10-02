import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_language.dart';
import '../providers/auth_provider.dart';
import '../services/account_deletion_service.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key, required this.userId, this.service});

  final String userId;

  /// Remplaçable en test uniquement.
  final AccountDeletionService? service;

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmController = TextEditingController();
  late final _service = widget.service ?? AccountDeletionService();
  bool _isDeleting = false;

  bool get _canDelete =>
      _confirmController.text.trim().toUpperCase() == 'SUPPRIMER';

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() => _isDeleting = true);

    try {
      await _service.deleteAccount();
      await ref.read(authNotifierProvider.notifier).logout();

      if (mounted) context.go('/auth');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      // failed-precondition : commande ou échange de points en cours — le
      // message du serveur dit précisément quoi terminer avant.
      final message =
          error is FirebaseFunctionsException &&
              error.code == 'failed-precondition' &&
              (error.message?.isNotEmpty ?? false)
          ? error.message!
          : tr('Suppression impossible. Vérifie ta connexion et réessaie.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Supprimer mon compte'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              tr('Cette action est irréversible'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text(
              'En supprimant votre compte :\n\n'
              '- Votre profil, votre numéro et votre photo seront effacés\n'
              '- Vos annonces, statuts, favoris et alertes seront supprimés\n'
              "- Vos pièces d'identité et votre numéro de reversement "
              'seront supprimés\n'
              '- Vos conversations resteront visibles pour vos contacts, '
              'mais votre nom apparaîtra comme "Utilisateur supprimé"\n'
              "- Vous perdrez l'accès à votre abonnement en cours\n\n"
              'Une commande en cours (paiement, séquestre, litige ou '
              'reversement) doit être terminée avant la suppression. '
              "L'historique des commandes et paiements est conservé, "
              'anonymisé, pour des raisons légales.',
            ),
            const SizedBox(height: 24),
            Text(tr('Tapez SUPPRIMER pour confirmer :')),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'SUPPRIMER',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: (_canDelete && !_isDeleting) ? _delete : null,
                child: _isDeleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(tr('Supprimer définitivement mon compte')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
