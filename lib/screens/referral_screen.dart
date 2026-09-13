import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/referral_provider.dart';

/// Points gagnés par le parrain ET par le filleul au 1er achat complété de
/// ce dernier — doit rester synchronisé avec `REFERRAL_REWARD_POINTS` dans
/// `functions/index.js` (affichage uniquement, la vraie source de vérité
/// reste côté serveur).
const int _referralRewardPoints = 5;

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authNotifierProvider).currentUser?.id ?? '';
    final userAsync = ref.watch(currentUserDocProvider(userId));

    return Scaffold(
      appBar: AppBar(title: const Text('Parrainage')),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Impossible de charger votre code de parrainage.'),
          ),
        ),
        data: (user) {
          final code = user?.referralCode;
          if (code == null || code.isEmpty) {
            // Comptes créés avant l'ajout du parrainage : `onUserCreated`
            // (déclencheur onCreate) ne leur a jamais attribué de code.
            // Sans cet appel, l'écran resterait bloqué indéfiniment sur ce
            // message, "revenez dans un instant" n'arrivant jamais.
            ref.watch(ensureReferralCodeProvider(userId));
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Votre code de parrainage est en cours de génération, '
                  'revenez dans un instant.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Invitez vos proches sur Occasion',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Vous gagnez $_referralRewardPoints points dès que la '
                'personne invitée effectue son premier achat — elle gagne '
                'aussi $_referralRewardPoints points de bienvenue.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
              ),
              const SizedBox(height: 24),
              _CodeCard(code: code),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.group_outlined,
                      label: 'Filleuls inscrits',
                      value: '${user?.referralCount ?? 0}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.stars_outlined,
                      label: 'Points gagnés',
                      value: '${user?.referralRewardPoints ?? 0}',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

  String get _shareMessage =>
      'Rejoins-moi sur Occasion et utilise mon code de parrainage "$code" '
      'à l\'inscription pour qu\'on gagne tous les deux des points ! 🎁';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Votre code', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Text(
              code,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copié.')),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copier'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Share.share(_shareMessage),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Partager'),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: Colors.amber),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
}
