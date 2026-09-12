import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/review_provider.dart';

/// Ouvre une feuille pour déposer un avis (note 1-5 + commentaire optionnel)
/// après une commande complétée. Retourne `true` si l'avis a bien été
/// envoyé (créé ou déjà existant — jamais d'erreur pour un rejeu), `null`
/// si l'utilisateur a annulé.
Future<bool?> showLeaveReviewSheet(
  BuildContext context, {
  required String orderId,
  required String sellerId,
  required String title,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _LeaveReviewSheet(orderId: orderId, sellerId: sellerId, title: title),
  );
}

class _LeaveReviewSheet extends ConsumerStatefulWidget {
  const _LeaveReviewSheet({
    required this.orderId,
    required this.sellerId,
    required this.title,
  });

  final String orderId;
  final String sellerId;
  final String title;

  @override
  ConsumerState<_LeaveReviewSheet> createState() => _LeaveReviewSheetState();
}

class _LeaveReviewSheetState extends ConsumerState<_LeaveReviewSheet> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      setState(() => _error = 'Choisis une note avant d\'envoyer.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref
          .read(reviewServiceProvider)
          .submitReview(
            orderId: widget.orderId,
            sellerId: widget.sellerId,
            rating: _rating,
            comment: _commentController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = "Échec de l'envoi. Réessaie.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              return IconButton(
                iconSize: 32,
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() {
                        _rating = starValue;
                        _error = null;
                      }),
                icon: Icon(
                  starValue <= _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 3,
            maxLength: 1000,
            enabled: !_isSubmitting,
            decoration: const InputDecoration(
              hintText: 'Commentaire (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Envoyer l'avis"),
            ),
          ),
        ],
      ),
    );
  }
}
