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

Le projet est une marketplace Flutter en developpement. L'identite visible doit rester `Occasion`. L'`applicationId` Android final est `com.mediavision.occasion`; l'application Android Firebase correspondante est creee et `android/app/google-services.json` pointe vers ce package.

## Points a faire avant publication

1. Ajouter une vraie signature release via `android/key.properties` et un keystore prive non versionne.
2. Tester l'auth telephone, Firestore, Storage, notifications et paiement sur telephone reel.
3. Verifier les regles Firestore/Storage avant test public.
4. Creer les applications Firebase separees avant toute publication iOS/macOS.

## Commandes utiles

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Note

Ne pas melanger ce depot avec Ma Gestion ou MedConnect. Occasion est le projet marketplace.
