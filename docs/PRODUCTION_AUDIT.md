# Audit de production — Occasion

Date : 2026-07-09. Branche : `release/occasion-production-v2`.

Cet audit couvre l'état réel du dépôt (pas l'état souhaité), établi par lecture
directe du code, `firestore.rules`, `storage.rules`, `firestore.indexes.json`,
`functions/index.js` et les workflows CI. Il sert de base à la Phase 1 de
durcissement production (voir section "Phase 1" ci-dessous) et aux phases
suivantes.

## 1. Messagerie — compteur de messages non lus

**Bug confirmé** : `Chat.unreadCount` (`lib/models/chat.dart`) est un compteur
unique partagé entre acheteur et vendeur, pas un compteur par participant.

- `ChatService.sendMessage` incrémente `unreadCount` à chaque message, quel
  que soit le destinataire réel (`lib/services/chat_service.dart`).
- `ChatService.markAsRead(chatId, userId)` remet `unreadCount` à **zéro pour
  les deux participants** dès que l'un des deux ouvre la conversation — donc
  si le vendeur ouvre le chat, le badge de l'acheteur peut se retrouver
  également à zéro alors qu'il n'a rien lu.
- Le badge global (`lib/main.dart`) et la liste des conversations
  (`lib/screens/chat_list_screen.dart`) somment/lisent ce même champ partagé.
- `ChatService.chatMessages(chatId)` charge tout l'historique des messages
  sans limite (`orderBy('sentAt')`, pas de `.limit()`) — coûteux et lent sur
  de longues conversations.

**Risque** : un utilisateur peut croire avoir un nouveau message alors qu'il a
déjà été lu par l'autre, ou l'inverse (badge qui disparaît sans qu'il ait rien
lu). Cause directe de confusion signalée précédemment dans cette session
("le vendeur ne voit pas les messages").

**Cause** : le modèle de données n'a jamais distingué les deux participants
pour ce champ précis (contrairement au statut par message, qui lui est déjà
correctement scopé par `receiverId`).

## 2. Notifications — système persistant existant mais jamais branché

Deux implémentations de notifications coexistent, indépendantes :

- **`NotificationNotifier`** (`lib/providers/notification_provider.dart`) :
  purement en mémoire (`StateNotifier<List<AppNotification>>`), aucune
  persistance Firestore, perdu au redémarrage. C'est celle réellement utilisée
  par `lib/screens/notifications_screen.dart`.
- **`NotificationsOccasionRepository`** (`lib/repositories/occasion_firestore_repositories.dart`)
  + modèle `NotificationOccasion` + providers (`lib/providers/occasion_firestore_providers.dart`) :
  système Firestore complet et fonctionnel côté rules (`firestore.rules`,
  collection `notifications`, champs français `utilisateurId`/`lu`/`date`),
  mais **jamais lu ni écrit par aucun écran** — code mort, confirmé par
  recherche exhaustive des points d'appel.

**FCM** : un seul token par utilisateur (`users/{uid}.fcmToken`,
`lib/services/notification_service.dart`), écrasé à chaque nouvelle connexion
— pas de support multi-appareils. `functions/index.js` (`onNewMessage`) envoie
sur ce token unique via l'API single-token, donc un utilisateur connecté sur 2
appareils ne reçoit la notification que sur le dernier connecté.

**Traité en Phase 2** : voir section "Phase 2" ci-dessous (nouvelle collection
`notifications` réellement branchée, multi-appareils
`users/{uid}/devices/{deviceId}`, Cloud Functions idempotentes, code mort
supprimé).

## 3. Annonces — deux piles de providers parallèles

Deux chemins de lecture indépendants vers la même collection Firestore
`annonces` :

- **Pile A** (`lib/annonce/`) : `AnnonceRepositoryImpl` + `sellerAnnoncesProvider`/
  `annonceByIdProvider`/`createAnnonceProvider`. Utilisée par le tableau de
  bord vendeur, "Mes annonces", le détail d'annonce, la création.
- **Pile B** (`lib/repositories/occasion_firestore_repositories.dart`) :
  `AnnoncesCrudRepository` + `activeAnnoncesStreamProvider` → `productNotifierProvider`
  (conversion vers `ProductModel`). Utilisée par l'écran principal du
  marketplace (`product_list_screen.dart`).

Deux providers sont morts (zéro appelant) : `annoncesProvider`
(`lib/annonce/providers/annonce_provider.dart`) et `searchResultsProvider` du
même fichier (le vrai écran de recherche utilise un provider équivalent dans
`lib/search/providers/search_provider.dart`).

Le modèle `Annonce` tolère déjà les deux jeux de noms de champs (français/
anglais) en lecture et écrit les deux à chaque sauvegarde
(`lib/models/annonce.dart`) — fonctionnel mais fragile (double écriture
permanente au lieu d'une source de vérité unique).

**Traité en Phase 4** : voir section "Phase 4" ci-dessous. Le champ `Annonce`
dual français/anglais n'a pas été touché (hors périmètre, aucun rapport avec
la duplication des deux piles de lecture).

## 4. Widgets image / carrousel

- `lib/widgets/occasion_image.dart` et `lib/widgets/photo_carousel.dart`
  **n'existent pas**.
- 7 sites utilisent `Image.network` brut (pas de cache, pas de gestion
  d'erreur uniforme) : `annonce_card.dart`, `create_annonce_screen.dart`,
  `annonce_detail_screen.dart`, `profile_screen.dart`, `my_listings_screen.dart`,
  `fullscreen_image_viewer.dart`, `product_card.dart`.
- `cached_network_image` est déjà une dépendance (`pubspec.yaml`) mais
  seulement utilisée dans le feed et la messagerie — pas dans les annonces.
- **Bug UX confirmé** : `ProductCard` et `AnnonceCard` n'affichent que
  `imageUrls.first` — aucun balayage, aucun indicateur de nombre de photos,
  alors que le modèle contient déjà toutes les URLs. `FullscreenImageViewer`
  fonctionne (zoom, PageView) mais n'a ni points ni compteur "1/5".

**Traité en Phase 1** : voir section Phase 1 ci-dessous.

## 5. Grille produits

`lib/screens/product_list_screen.dart` utilise `ListView.builder` (colonne
unique), aucune logique responsive (`MediaQuery`/breakpoint). Sur tablette/PWA
desktop, les cartes s'étirent sur toute la largeur.

**Traité en Phase 1.**

## 6. Feed (statuts) — déjà correct, ne pas toucher

`StatusFeedScreen` gère déjà correctement : `BoxFit.cover` pour images/vidéos,
cycle de vie des `VideoPlayerController` par page (pause/dispose au scroll),
pagination réelle (`StatusService.fetchMoreFeed`/`startAfterDocument`), pas de
stream permanent sur tout l'historique. Aucune action nécessaire ici.

## 7. Likes vs favoris — déjà correct, ne pas toucher

Deux systèmes distincts et fonctionnels, pas de duplication : les "likes"
concernent les statuts (`StatusService.toggleLike`), les "favoris" concernent
les annonces (`lib/favoris/`). Séparation intentionnelle, pas un bug.

## 8. Statistiques vendeur — chiffres partiellement fictifs

`SellerDashboardScreen` additionne `annonce.views`/`messagesCount` (réels
depuis la correction de session précédente) mais la tuile "Statistiques"
affiche un texte statique ("Bientôt", corrigé précédemment ; auparavant
`'--'`). Aucun agrégat serveur (`sellerStatistics/{sellerId}`) n'existe.

**Traité en Phase 3** : voir section "Phase 3" ci-dessous (agrégat serveur
`sellerStatistics/{sellerId}`, comptage de vues anti-fraude, écran
`/seller-statistics` réel).

## 9. Système de fidélité / récompenses — inexistant

Recherche exhaustive (lib/, functions/, règles, index) : **aucune trace** de
points, récompenses, cadeaux, conversion de points. `UserModel` n'a aucun
champ de ce type. Confirmé entièrement absent.

**Décision** : chantier complet différé à une phase ultérieure dédiée
(sections 18-25 du cahier des charges original) — nouveau sous-système
produit à part entière (modèles, Cloud Functions, écrans acheteur/vendeur/
admin, anti-fraude, tests). Non traité en Phase 1.

## 10. Abonnement vendeur

Le paiement Orange Money est manuel et externe par conception. Une
redirection vers un paiement web (`_mustPaySubscriptionOnWeb` dans
`subscription_screen.dart`) avait été ajoutée dans une session précédente
pour respecter la politique Google Play sur les paiements in-app (Play
Billing) pour Android. **Décision utilisateur pour cette phase** : retirer
cette redirection et revenir à un flux 100% in-app (bouton "J'AI ENVOYÉ
L'ARGENT"), le risque de non-conformité Play Store étant accepté en
connaissance de cause.

Il n'existe pas d'écran administrateur dédié aux demandes d'abonnement — le
flux passe par l'écran générique "Administration paiements"
(`admin_orders_screen.dart`), qui traite indifféremment commandes et
abonnements via `paymentIntents`. Fonctionnel mais pas spécialisé.

**Traité en Phase 1** : retrait de la redirection web + durcissement du
bouton existant. **Différé** : écran admin dédié aux abonnements.

## 11. Signalements — corrigé (session précédente), sain

`reports` a un ID déterministe anti-doublon, des règles `isAdmin()` correctes
pour lecture/mise à jour, un écran admin à onglets fonctionnel (vérifié plus
tôt dans cette session, y compris l'ajout de l'index composite manquant).
L'ancien système `signalements`/`SignalementsOccasionRepository` reste présent
mais mort (zéro appelant) — candidat à suppression dans une phase de nettoyage
ultérieure, pas critique.

## 12. Contrôle d'accès administrateur — trou de sécurité confirmé

`PaymentSettlementService.isCurrentUserAdmin()` vérifie correctement
l'existence de `admins/{uid}`, et cache bien les entrées de menu admin côté
UI. **Mais** les routes `/admin/orders` et `/admin/reports`
(`lib/main.dart`) n'ont **aucun garde au niveau du routeur** — contrairement
aux autres routes protégées par `_AuthGuard`/`_RoleGuard`. Un utilisateur qui
devine l'URL atteint l'écran (les données resteraient bloquées côté
Firestore par les règles, mais l'écran se construit et affiche une coquille
vide/erreur au lieu d'une redirection propre).

**Traité en Phase 1** : ajout d'un `_AdminGuard` au niveau GoRouter.

## 13. Règles Firestore / Storage — globalement saines

Lecture complète de `firestore.rules` (576 lignes) et `storage.rules` (54
lignes) : aucune règle `allow read, write: if true` sur des données
sensibles. `subscriptions`, `orders`, `paymentIntents` sont déjà bien
restreints côté écriture client (transitions de statut limitées, champs
financiers non modifiables directement). Point mineur : la collection legacy
française `utilisateurs/{userId}` (doublon de `users`) autorise
lecture/écriture au propriétaire sans validation de forme — à nettoyer dans
une phase future de suppression du schéma legacy.

**App Check** : n'existe pas dans le projet (aucune dépendance, aucune
initialisation). Différé à une phase ultérieure.

## 14. CI — non bloquante, corrigé en Phase 1

`.github/workflows/deploy-pages.yml` : les étapes `flutter analyze` et
`flutter test` ont chacune un `|| echo "::warning::..."` **et**
`continue-on-error: true` — un échec de lint ou de test ne bloque jamais le
déploiement. Aucune étape n'exécute la suite `firestore-tests/rules.test.js`
existante (11 tests contre l'émulateur), écrite mais jamais lancée en CI.

**Traité en Phase 1.**

---

## Phase 1 — Ce qui est corrigé maintenant

1. Compteurs de messages non lus par participant (`buyerUnreadCount`/
   `sellerUnreadCount`) + pagination des anciens messages + script de
   migration dry-run.
2. Abonnement vendeur : retrait de la redirection web, retour au paiement
   in-app, bouton durci (garde contre les doubles demandes).
3. `_AdminGuard` au niveau GoRouter pour `/admin/orders` et `/admin/reports`.
4. CI bloquante (analyze/test/format) + suite `firestore-tests` intégrée.
5. Widgets `OccasionImage`/`PhotoCarousel` unifiés, remplaçant les 7 sites
   `Image.network` bruts et l'affichage mono-photo des cartes produit/annonce.
6. Grille responsive pour la liste produits (1/2/3 colonnes selon largeur).

## Phase 2 — Notifications : persistance réelle + multi-appareils

Remplace intégralement le système décrit en section 2 (`NotificationNotifier`
en mémoire + `NotificationsOccasionRepository` mort, code français, jamais
branché). Un seul système désormais :

1. Modèle `AppNotification` (`lib/models/app_notification.dart`, champs
   anglais : `recipientId`, `senderId`, `type`, `title`, `body`, `route`,
   `entityId`/`chatId`/`listingId`/`statusId`/`orderId`/`paymentIntentId`,
   `isRead`, `createdAt`, `readAt`, `data`), persistée dans
   `notifications/{id}`.
2. Suppression du code mort : `NotificationOccasion`,
   `NotificationsOccasionRepository`, `notificationsOccasionRepositoryProvider`,
   `notificationsByUserProvider` — évite deux systèmes concurrents sur la
   même collection.
3. `firestore.rules` : `notifications/{id}` n'est **créable que côté serveur**
   (`allow create: if false`, Cloud Functions via l'Admin SDK contournent les
   règles) ; le destinataire peut lire, marquer lu/non lu (`isRead`/`readAt`
   uniquement) et supprimer sa propre notification. Index composite
   `recipientId`+`createdAt` (et `+isRead`) ajouté.
4. Multi-appareils : `users/{uid}/devices/{deviceId}` remplace le champ
   unique `fcmToken`. `deviceId` généré une fois et persisté localement
   (`shared_preferences`), donc stable par appareil/installation — un même
   compte connecté sur 2 téléphones reçoit désormais les push sur les deux.
   Règles : lecture/écriture réservées au propriétaire.
5. `functions/index.js` : helper `sendToUser()` unique — persiste la
   notification Firestore (ID déterministe = idempotent aux retries Cloud
   Functions) et envoie un multicast à tous les appareils du destinataire,
   avec nettoyage des jetons invalides. Branché sur :
   - `onNewMessage` (notification + push par message reçu) ;
   - `applySettlement` (paiement de commande confirmé/rejeté → acheteur, et
     vendeurs notifiés d'une commande payée ; abonnement activé/rejeté →
     vendeur) ;
   - `autoReleaseEscrow` (fonds libérés → vendeur).
   `onNewStatus` reste push-only (diffusion à tous les acheteurs) : pas de
   notification persistée par destinataire, décision volontaire de maîtrise
   des coûts Firestore vu le volume potentiel (un document par acheteur et
   par statut publié serait disproportionné).
6. Écran `/notifications` réellement branché sur Firestore (liste, swipe pour
   supprimer, "tout marquer comme lu", tap = marque lu + navigue via
   `route`). Point d'entrée ajouté dans `ProfileScreen` (icône cloche avec
   badge du nombre de non-lues) — l'écran était auparavant inatteignable
   depuis l'UI.
7. Tests : parsing `AppNotification.fromFirestore` (`test/app_notification_test.dart`),
   règles `notifications`/`devices` côté émulateur (8 nouveaux cas dans
   `firestore-tests/rules.test.js`).

**Corrections post-vérification** (avant d'entamer la Phase 3) : nettoyage de
`users/{uid}/devices` à la suppression de compte (manquait, contrairement à
`blockedUsers`) ; `sendToUser()` promeut désormais `chatId`/`orderId`/... au
premier niveau du document notification (le modèle les lisait à ce niveau
mais ils n'étaient écrits que dans `data`) ; nouveau workflow `ci.yml`
déclenché sur `pull_request` — la CI bloquante de la Phase 1 ne tournait
jusque-là qu'après fusion sur `main`, jamais sur la PR elle-même.

## Phase 3 — Statistiques vendeur réelles + vues anti-fraude

Remplace la tuile "Statistiques" statique du tableau de bord vendeur et
l'écran `/seller-statistics` (placeholder générique) par des données
réellement agrégées côté serveur, et corrige au passage une faille trouvée en
l'analysant : `annonces/{id}.vues` était modifiable avec n'importe quelle
valeur par n'importe quel utilisateur connecté (seule la liste des champs
était contrainte, pas qui écrit ni de combien).

1. Comptage de vues déplacé côté serveur : nouvelle Cloud Function callable
   `recordAnnonceView`, dédupliquée par `annonces/{id}/viewers/{uid}` (un
   document par couple annonce/visiteur, idempotent). Les visiteurs non
   connectés ne sont pas comptabilisés (pas d'identité fiable à dédupliquer).
   Le client n'a plus le droit d'écrire `vues` directement
   (`firestore.rules`, retiré du `hasOnly` client-écrivable des `annonces`) ;
   `viewers/{viewerId}` est entièrement fermé côté client.
2. Nouvel agrégat `sellerStatistics/{sellerId}` (`totalViews`,
   `totalMessages`, `totalSales`, `revenue` par devise — jamais mélangées),
   écrit uniquement par les Cloud Functions (`bumpSellerStats()`), lu
   uniquement par le vendeur propriétaire. Alimenté par `recordAnnonceView`
   (vues), `onNewMessage` (messages reçus par un vendeur) et
   `notifySettlement` (ventes + revenu, au sous-total par vendeur d'une
   commande potentiellement multi-vendeur — jamais le total complet de la
   commande crédité à chacun).
3. Écran `/seller-statistics` réellement branché (`SellerStatisticsScreen`,
   provider `sellerStatisticsProvider`), tuile "Ventes" cliquable sur le
   tableau de bord vendeur (plus de `'Bientôt'` statique).
4. Tests : parsing `SellerStatistics.fromFirestore`
   (`test/seller_statistics_test.dart`), 6 nouveaux cas de règles côté
   émulateur (`vues` non écrivable côté client, `favoris` toujours OK,
   `viewers`/`sellerStatistics` fermés en écriture, lecture `sellerStatistics`
   réservée au propriétaire).

**Correctif post-Phase 3** : `confirmManualPayment`/`rejectManualPayment`
(`functions/index.js`) ne vérifiaient pas si l'intention de paiement était
déjà réglée avant de rappeler `applySettlement` — un double-tap admin ou un
retry réseau doublait les compteurs `sellerStatistics` et réinitialisait la
date de départ d'un abonnement déjà activé. Les deux callables sont
désormais des no-op silencieux sur un `transactionId` déjà dans un état
terminal (`paid`/`failed`).

## Phase 4 — Unification des deux piles de providers d'annonces

Avant de trancher entre les deux prochains gros chantiers (fidélité/points ou
unification des annonces), une relecture de `functions/index.js` a mis en
évidence un bug financier à corriger en priorité : `confirmManualPayment`/
`rejectManualPayment` ne vérifiaient pas l'état déjà réglé d'une intention de
paiement avant de rappeler `applySettlement` (double-tap admin/retry réseau
→ double comptage `sellerStatistics`, réinitialisation de la date de départ
d'un abonnement). Corrigé (voir ci-dessus).

L'unification des annonces s'est avérée moins risquée que redouté une fois
scopée en détail (exploration dédiée) : les deux piles utilisaient déjà le
même modèle `Annonce` — la duplication n'était qu'au niveau de la requête
Firestore elle-même, pas de la forme des données.

1. `AnnonceRepositoryImpl.watchActiveAnnonces({category})` (Pile A) remplace
   `AnnoncesCrudRepository.activeByDate()` (Pile B) — requête identique
   (`isPublished` + `dateCreation`, + `categorie` optionnel), mêmes index
   déjà en place, aucun redéploiement Firestore nécessaire.
2. Conversion `Annonce → ProductModel` (nécessaire pour le panier/paiement,
   volontairement inchangés) factorisée en une fonction pure unique
   `annonceToProductModel()` (`lib/providers/product_provider.dart`),
   réutilisée par la liste marketplace et l'écran de détail d'annonce.
   **Bug corrigé au passage** : le détail d'annonce recopiait cette
   conversion à la main sans l'enrichissement vendeur, ce qui masquait les
   badges "vendeur vérifié"/"téléphone vérifié" sur cet écran précis alors
   qu'ils s'affichaient correctement sur la liste.
3. Suppression du code mort : `AnnoncesCrudRepository`,
   `annoncesCrudRepositoryProvider`, `activeAnnoncesStreamProvider` (Pile B
   entière), et `annoncesProvider`/`searchResultsProvider` de
   `lib/annonce/providers/annonce_provider.dart` (zéro appelant, doublons du
   vrai `searchResultsProvider` de `lib/search/providers/search_provider.dart`).
4. Le dual-écriture français/anglais du modèle `Annonce` lui-même n'a pas été
   touchée (hors périmètre — aucun rapport avec la duplication des deux
   piles de lecture).
5. Tests : `test/annonce_to_product_model_test.dart` (conversion pure, y
   compris le cas "avec profil vendeur" qui couvre la régression corrigée).

## Phases suivantes (hors de portée de cette session)

- Écran administrateur dédié aux demandes d'abonnement + Cloud Function
  d'activation sécurisée (évalué en Phase 4 : faible valeur ajoutée,
  l'écran générique différencie déjà commande/abonnement).
- Système de fidélité/récompenses acheteur et vendeur (entièrement nouveau).
- App Check.
- Documentation d'optimisation des coûts Firestore.
- Migrations généralisées (anciens signalements, anciens champs). Le champ
  legacy `users/{uid}.fcmToken` n'est plus écrit à partir de cette phase ;
  les appareils déjà connectés migrent automatiquement vers
  `users/{uid}/devices/{deviceId}` à la prochaine ouverture de l'app (pas de
  script de migration dédié — bascule naturelle, pas de perte de
  fonctionnalité entre-temps puisque `sendToUser` ne lit que la nouvelle
  sous-collection).
- Suite de tests Firebase Emulator exhaustive (rôles, sécurité, tous les
  scénarios listés dans le cahier des charges original).
- Plan de validation sur appareils physiques.
