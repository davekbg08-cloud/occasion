# Occasion — Marketplace

Occasion est une application Flutter de marketplace destinée à mettre en relation vendeurs et acheteurs autour de produits publiés dans l’application.

## Objectif

Construire une marketplace mobile avec profils utilisateurs, catalogue produits, panier, paiement, messagerie, statuts/fil d’actualité, notifications et vérification d’identité.

## Fonctionnalités visibles dans le projet

- Sélection du rôle utilisateur : acheteur ou vendeur.
- Authentification téléphone.
- Scan d’identité / OCR.
- Liste de produits.
- Panier.
- Paiement.
- Abonnement.
- Profil utilisateur.
- Statuts / fil d’actualité.
- Messagerie acheteur-vendeur.
- Notifications Firebase/locales.
- Gestion des utilisateurs bloqués et suppression de compte.

## Stack technique

- Flutter
- Firebase Core, Auth, Firestore, Storage et Messaging
- Riverpod
- GoRouter
- GetIt / Injectable
- CinetPay
- Camera / Image Picker / Google ML Kit OCR
- Notifications locales

## État actuel

Le projet est une marketplace Flutter en développement. L’identité visible doit rester `Occasion`, mais l’`applicationId` Android est encore `com.example.occasion` parce que le fichier Firebase `google-services.json` actuel est lié à ce package. Avant une publication officielle, il faudra créer/configurer l’application Android finale dans Firebase puis remplacer proprement l’`applicationId`.

## Points à faire avant publication

1. Choisir le package final, par exemple `com.mediavision.occasion`.
2. Créer l’application Android correspondante dans Firebase.
3. Télécharger le nouveau `google-services.json`.
4. Mettre à jour `applicationId` et `namespace` Android.
5. Ajouter une vraie signature release.
6. Tester l’auth téléphone, Firestore, Storage, notifications et paiement sur téléphone réel.
7. Vérifier les règles Firestore/Storage avant test public.

## Commandes utiles

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Note

Ne pas mélanger ce dépôt avec Ma Gestion ou MedConnect. Occasion est le projet marketplace.
