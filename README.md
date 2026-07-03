# Occasion - Marketplace

Occasion est une application Flutter de marketplace destinee a mettre en relation vendeurs et acheteurs autour de produits publies dans l'application.

## Objectif

Construire une marketplace mobile avec profils utilisateurs, catalogue produits, panier, paiement, messagerie, statuts/fil d'actualite, notifications et verification d'identite.

## Fonctionnalites visibles dans le projet

- Selection du role utilisateur : acheteur ou vendeur.
- Authentification telephone.
- Scan d'identite / OCR.
- Liste de produits.
- Panier.
- Paiement.
- Abonnement.
- Profil utilisateur.
- Statuts / fil d'actualite.
- Messagerie acheteur-vendeur.
- Notifications Firebase/locales.
- Gestion des utilisateurs bloques et suppression de compte.

## Stack technique

- Flutter
- Firebase Core, Auth, Firestore, Storage et Messaging
- Riverpod
- GoRouter
- GetIt / Injectable
- CinetPay
- Camera / Image Picker / Google ML Kit OCR
- Notifications locales

## Etat actuel

Marketplace Flutter en production. L'identite visible est `Occasion` (titre, PWA,
icones, splash, canal de notification). Les regles Firestore et Storage sont
deployees sur le projet Firebase `occasion-10cdb`.

L'`applicationId` Android reste `com.example.occasion` car le `google-services.json`
actuel est lie a ce package. Pour une publication Play Store officielle, il faudra
recreer l'application Android sous le package final dans Firebase et remplacer
`applicationId`, `namespace` et `google-services.json`.

## Deploiement

- **Web** : deploiement automatique sur GitHub Pages a chaque push sur `main`
  (voir `.github/workflows/deploy-pages.yml`).
- **Regles Firebase** : `firebase deploy --only firestore:rules,firestore:indexes,storage`.
- **Android release** : `flutter build apk --release` (ajouter une signature release
  avant publication Play Store).

## Commandes utiles

```bash
flutter pub get
flutter analyze
flutter build web --release
flutter build apk --release
firebase deploy --only firestore:rules,firestore:indexes,storage
```

## Note

Ne pas melanger ce depot avec Ma Gestion ou MedConnect. Occasion est le projet marketplace.
