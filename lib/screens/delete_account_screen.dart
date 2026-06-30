import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../services/account_deletion_service.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmController = TextEditingController();
  final _service = AccountDeletionService();
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
      await _service.deleteAccount(widget.userId);
      ref.read(authNotifierProvider.notifier).logout();

      if (mounted) context.go('/auth');
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login' && mounted) {
        setState(() => _isDeleting = false);
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Reconnexion necessaire'),
            content: const Text(
              'Pour des raisons de securite, veuillez vous reconnecter '
              'avant de supprimer definitivement votre compte.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      setState(() => _isDeleting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Suppression impossible.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supprimer mon compte')),
      body: Padding(
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
            const Text(
              'Cette action est irreversible',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text(
              'En supprimant votre compte :\n\n'
              '- Votre profil sera anonymise\n'
              '- Vos articles publies seront supprimes\n'
              '- Vos conversations resteront visibles pour vos contacts, '
              'mais votre nom apparaitra comme "Utilisateur supprime"\n'
              "- Vous perdrez l'acces a votre abonnement en cours\n\n"
              'Certaines donnees peuvent etre conservees temporairement '
              'pour des raisons legales, conformement a notre politique de confidentialite.',
            ),
            const SizedBox(height: 24),
            const Text('Tapez SUPPRIMER pour confirmer :'),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'SUPPRIMER',
              ),
            ),
            const Spacer(),
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
                    : const Text('Supprimer definitivement mon compte'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
