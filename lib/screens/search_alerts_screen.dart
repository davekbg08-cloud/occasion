import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/search_alert_provider.dart';

class SearchAlertsScreen extends ConsumerWidget {
  const SearchAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authNotifierProvider).currentUser?.id ?? '';
    final alertsAsync = ref.watch(searchAlertsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('Mes alertes de recherche'),
      ),
      body: alertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Impossible de charger tes alertes pour le moment.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (alerts) {
          if (alerts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Aucune alerte enregistrée. Depuis l'écran Rechercher, "
                  "utilise l'icône 🔖 pour être notifié des nouvelles "
                  "annonces correspondantes.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(alert.label),
                  trailing: IconButton(
                    tooltip: 'Supprimer cette alerte',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () =>
                        ref.read(searchAlertServiceProvider).delete(alert.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
