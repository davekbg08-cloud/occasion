# Nettoyage visible — anciennes traces “Gestion Money”

Ce fichier sert de point de repère visible à la racine du dépôt.

Objectif : centraliser les anciennes traces de l’ancien nom/prototype **Gestion Money** trouvées dans le projet **Occasion**, sans modifier le code existant et sans supprimer de fichiers.

## Règle importante

Ne pas modifier directement les fichiers source tant que le projet principal n’est pas stabilisé.

Ce fichier est uniquement une note de suivi pour Codex / développement futur.

## Traces repérées

### 1. Titre visible de l’application

Fichier : `lib/main.dart`

Trace :

```dart
title: 'Gestion Money RDC'
```

Action future recommandée : remplacer plus tard par :

```dart
title: 'Occasion'
```

### 2. Canal de notification Android / Firebase

Fichiers concernés :

- `android/app/src/main/AndroidManifest.xml`
- `lib/services/notification_service.dart`
- `functions/index.js`

Trace :

```text
gestion_money_channel
```

Action future recommandée : renommer plus tard en :

```text
occasion_channel
```

Attention : ne pas renommer sans vérifier Firebase Messaging et les notifications Android, car un changement de canal peut affecter les notifications déjà créées sur les appareils.

## Pourquoi ne pas corriger immédiatement ?

Ces traces ne bloquent pas forcément l’exécution de l’application, mais elles donnent une impression de projet non finalisé.

Pour éviter de casser l’app maintenant, elles sont simplement documentées ici.

## Priorité future

Quand le projet Occasion sera prêt pour nettoyage avant publication :

1. Corriger le titre visible de l’app.
2. Corriger le canal de notification.
3. Vérifier que les notifications fonctionnent encore.
4. Vérifier l’APK release.
5. Faire un commit séparé uniquement pour le nettoyage du branding.

## Instruction Codex future

```text
Ne modifie pas les fonctionnalités.
Fais uniquement un nettoyage de branding de l’ancien nom Gestion Money vers Occasion.
Vérifie les occurrences : Gestion Money, Gestion Money RDC, gestion_money, gestion_money_channel.
Ne supprime aucun fichier.
Teste flutter analyze après modification.
```
