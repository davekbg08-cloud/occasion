import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/report.dart';
import '../providers/moderation_provider.dart';

Future<void> showReportOrBlockSheet(
  BuildContext context, {
  required String currentUserId,
  required String targetUserId,
  required String targetUserName,
  required ReportTargetType targetType,
  String? contentId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportOrBlockSheet(
      currentUserId: currentUserId,
      targetUserId: targetUserId,
      targetUserName: targetUserName,
      targetType: targetType,
      contentId: contentId,
    ),
  );
}

class _ReportOrBlockSheet extends ConsumerWidget {
  const _ReportOrBlockSheet({
    required this.currentUserId,
    required this.targetUserId,
    required this.targetUserName,
    required this.targetType,
    required this.contentId,
  });

  final String currentUserId;
  final String targetUserId;
  final String targetUserName;
  final ReportTargetType targetType;
  final String? contentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isContentReport = contentId != null;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: Text(
                isContentReport
                    ? 'Signaler ce contenu'
                    : 'Signaler $targetUserName',
              ),
              onTap: () {
                Navigator.pop(context);
                _openReasonPicker(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: Text(
                'Bloquer $targetUserName',
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmBlock(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Annuler'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _openReasonPicker(BuildContext context, WidgetRef ref) {
    final detailsController = TextEditingController();
    ReportReason selected = ReportReason.spam;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pourquoi signalez-vous ce contenu ?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ...reportReasonLabels.entries.map((entry) {
                    final isSelected = selected == entry.key;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? Theme.of(sheetContext).colorScheme.primary
                            : null,
                      ),
                      title: Text(entry.value),
                      onTap: () => setState(() => selected = entry.key),
                    );
                  }),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Details supplementaires (facultatif)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await ref
                            .read(moderationServiceProvider)
                            .submitReport(
                              reporterId: currentUserId,
                              targetId: contentId ?? targetUserId,
                              targetType: targetType,
                              reason: selected,
                              details: detailsController.text.trim().isEmpty
                                  ? null
                                  : detailsController.text.trim(),
                            );

                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Signalement envoye. Merci de nous aider a garder Occasion sur.',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Envoyer le signalement'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(detailsController.dispose);
  }

  void _confirmBlock(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Bloquer $targetUserName ?'),
        content: const Text(
          'Vous ne verrez plus son contenu et cette personne ne pourra plus '
          'vous contacter. Vous pourrez debloquer a tout moment depuis votre profil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref
                  .read(moderationServiceProvider)
                  .blockUser(
                    currentUserId: currentUserId,
                    blockedUserId: targetUserId,
                    blockedUserName: targetUserName,
                  );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$targetUserName a ete bloque(e).')),
                );
              }
            },
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
  }
}
