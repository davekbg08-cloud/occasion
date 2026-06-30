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

Le projet est une marketplace Flutter en developpement. L'identite visible doit rester `Occasion`, mais l'`applicationId` Android est encore `com.example.occasion` parce que le fichier Firebase `google-services.json` actuel est lie a ce package. Avant une publication officielle, il faudra creer/configurer l'application Android finale dans Firebase puis remplacer proprement l'`applicationId`.

## Points a faire avant publication

1. Choisir le package final, par exemple `com.mediavision.occasion`.
2. Creer l'application Android correspondante dans Firebase.
3. Telecharger le nouveau `google-services.json`.
4. Mettre a jour `applicationId` et `namespace` Android.
5. Ajouter une vraie signature release.
6. Tester l'auth telephone, Firestore, Storage, notifications et paiement sur telephone reel.
7. Verifier les regles Firestore/Storage avant test public.

## Commandes utiles

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Note

Ne pas melanger ce depot avec Ma Gestion ou MedConnect. Occasion est le projet marketplace.
