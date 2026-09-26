import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_language.dart';
import '../providers/auth_provider.dart';

const _privacyPolicyUrl =
    'https://davekbg08-cloud.github.io/occasion/privacy.html';

/// Paramètres du compte : regroupe les réglages secondaires qui
/// encombraient auparavant le menu du profil (alertes de recherche,
/// utilisateurs bloqués, confidentialité, suppression du compte).
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authNotifierProvider).currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(tr('Paramètres'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(tr('Langue')),
            trailing: ValueListenableBuilder<String>(
              valueListenable: AppLanguage.current,
              builder: (context, language, _) => SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'fr', label: Text('FR')),
                  ButtonSegment(value: 'en', label: Text('EN')),
                ],
                selected: {language},
                onSelectionChanged: (value) => AppLanguage.set(value.first),
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(tr('Mes alertes de recherche')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/search-alerts'),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text(tr('Utilisateurs bloqués')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/blocked-users', extra: userId),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr('Politique de confidentialité')),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse(_privacyPolicyUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              tr('Supprimer mon compte'),
              style: TextStyle(color: Colors.red),
            ),
            onTap: () => context.push('/delete-account', extra: userId),
          ),
        ],
      ),
    );
  }
}
