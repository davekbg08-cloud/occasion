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

**Traité en Phase 5** : voir section "Phase 5" ci-dessous.

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

## Phase 5 — Système de fidélité/points (acheteur + vendeur)

Dernier gros chantier du cahier des charges original (section 9), entièrement
nouveau (rien n'existait). Quatre décisions produit validées par
l'utilisateur avant conception : barème acheteur proportionnel au montant
dépensé, crédit à la réception confirmée de la commande (pas au simple
paiement), échange scopé par vendeur (pas un pool global), barème vendeur
par vente confirmée.

**Point de conception trouvé en creusant `orders.status`** : la transition
vers `'completed'` peut venir de trois chemins différents (confirmation
acheteur, libération auto du séquestre, résolution d'un litige admin) — deux
sont des écritures client directes, pas des Cloud Functions. Un crédit de
points branché uniquement sur `autoReleaseEscrow` (comme `sellerStatistics`
en Phase 3) aurait silencieusement raté les deux autres chemins. Résolu par
un unique trigger générique `onDocumentUpdated('orders/{orderId}')` qui
détecte la transition quel que soit le chemin emprunté.

1. Modèle de données : `loyaltyPoints/{buyerId}_{sellerId}` (solde acheteur
   par vendeur, id déterministe), `sellerStatistics.loyaltyPoints` (points
   vendeur — pas de nouvelle collection, même agrégat que Phase 3),
   `giftCatalogItems/{id}` (catalogue par vendeur), `giftRedemptions/{id}`
   (demandes d'échange, créées/modifiées uniquement par Cloud Functions),
   `loyaltyPointsAuditLog/{id}` (trace des resets admin).
2. `functions/index.js` : `onOrderCompleted` (crédit acheteur + vendeur,
   sous-total par vendeur comme `notifySettlement`), `requestGiftRedemption`
   (transaction : vérifie solde, débite, crée la demande — anti-double-
   dépense), `respondToGiftRedemption` (vendeur ou admin valide/rejette,
   rejet = remboursement atomique), `adminResetLoyaltyPoints` (reset
   exceptionnel, motif obligatoire, trace d'audit).
3. Barème (`LOYALTY_POINTS_RATE`, placeholder business ajustable) : 1 point
   par 1000 FC ou 1 USD dépensé/vendu, compté indépendamment par devise
   (même principe que `revenue` en Phase 3 — pas de taux de change inventé).
4. Écrans : `LoyaltyPointsScreen` (acheteur — soldes par vendeur, catalogue,
   échange, historique), `SellerGiftCatalogScreen` (CRUD du catalogue),
   `SellerGiftRedemptionsScreen` (file d'attente à onglets, motif réutilisé
   de `admin_reports_screen.dart`), `AdminLoyaltyScreen` (reset exceptionnel,
   `_AdminGuard`). Carte "Points fidélité" ajoutée à `SellerStatisticsScreen`.
5. Bug trouvé et corrigé pendant l'implémentation : `GiftCatalogItem.toFirestore()`
   écrivait `imageUrl: null` explicitement quand l'image est absente, ce que
   la règle `validGiftCatalogItem` (`optionalString`) rejette (un champ
   présent doit être une string, `null` échoue) — un vendeur créant un cadeau
   sans photo aurait vu sa création systématiquement refusée. Corrigé en
   omettant la clé plutôt que d'écrire `null`.
6. Tests : parsing des 3 nouveaux modèles, 15 nouveaux cas de règles côté
   émulateur (solde de points fermé en écriture, catalogue public si actif/
   géré par le propriétaire, demandes d'échange fermées en écriture client
   y compris création, journal d'audit réservé aux admins).

## Phase 6 — Stabilisation finale avant AAB 1.1.1+7

Passe de stabilisation demandée par l'utilisateur (14 sections), précédée
d'une vérification indépendante de chaque affirmation contre le code réel
(3 agents d'exploration + lecture directe). Quasi-totalité confirmée, avec
une découverte majeure : **la messagerie était cassée en production**
(règle Firestore déployée en Phase 2-5 qui contredisait le code client
existant — tout envoi de message échouait). Corrigée en priorité.

1. **Messagerie (bug bloquant)** : `firestore.rules` interdisait à un
   participant de modifier le compteur non-lu de l'autre, mais
   `ChatService.sendMessage` incrémentait toujours ce même compteur dans
   son batch → `permission-denied` systématique, message jamais créé.
   Corrigé en déplaçant l'incrément côté serveur (`onNewMessage`,
   idempotent via un marqueur `unreadCounted` sur le message), le client ne
   touchant plus que les métadonnées non sensibles du chat. Règle durcie :
   le client ne peut plus que remettre SON propre compteur à 0, plus
   l'incrémenter lui-même. `markAsRead` paginé par lots de 400 (limite
   Firestore de 500 écritures/batch). 7 nouveaux cas de règles + garde
   d'idempotence côté fonction.
2. **Feed de statuts** : images en `BoxFit.contain` sur fond noir (réutilise
   `OccasionImage.detail`, déjà correct pour ce cas) ; état d'erreur +
   bouton Réessayer sur les vidéos ; partage réel (`share_plus`) au lieu du
   `SnackBar` "Partage à venir" ; likes désormais idempotents via
   `statusLikes/{statusId}_{userId}` + Cloud Function transactionnelle
   `toggleStatusLike` (plus d'incrément client direct) ; suppression
   devenue une Cloud Function `deleteStatus` (nettoie aussi le fichier
   Storage et les likes associés, réservée au propriétaire ou à un admin) ;
   route morte `/status` supprimée.
3. **FullscreenImageViewer** : `PageController` déplacé de `build()` vers
   `initState()`, avec `dispose()` (fuite de contrôleurs corrigée).
4. **Fonctionnalités fantômes** : entrées de navigation retirées pour
   `/addresses` et `/favorites` (écrans `SimplePlaceholderScreen` non
   branchés) ; `/seller-revenue` déjà sans aucun point d'entrée. Fichiers
   conservés pour un développement futur.
5. **Notification admin abonnement** : nouveau trigger
   `onSubscriptionAwaitingVerification` (Firestore `paymentIntents`) qui
   notifie tous les admins dès qu'une demande passe à
   `awaiting_manual_verification`. `applySettlement` (confirmation/rejet
   d'un paiement manuel) rendu entièrement atomique (une seule transaction
   lecture+décision+écriture) — élimine la fenêtre de course entre deux
   admins ou un double-clic qui pouvait doubler les compteurs
   `sellerStatistics` ou réinitialiser une date d'abonnement.
6. **NotificationService** : repli sur `message.data` quand
   `message.notification` est absent (data-only) ; notification de message
   route désormais vers `/chat/{chatId}` (nouvelle route + résolution du
   chat par id) au lieu de `/chat-list` en dur ; envoi FCM rendu idempotent
   via un champ `pushSentAt` (une redélivrance de trigger ne renvoie plus
   le push) ; badge natif iOS (`aps.badge`) calculé à partir du vrai nombre
   de notifications non lues au lieu d'une valeur `1` codée en dur.
7. **Session en cas d'erreur réseau** : `AuthNotifier._restoreSession`
   distingue désormais réseau/permission (session Firebase conservée,
   message "Connexion indisponible, réessayez", log Crashlytics, aucun
   `signOut()`) du seul cas qui déconnecte réellement (profil confirmé
   absent après lecture serveur). Nouvel écran de retry (`_AuthGate`) et
   méthode `retryRestoreSession()`.
8. **Statistiques vendeur** : libellés corrigés ("Messages" →
   "Conversations" pour le compteur de fils uniques du tableau de bord ;
   "En attente" → "Annonces inactives"). `recordAnnonceView` refuse
   désormais l'auto-vue du propriétaire et les annonces non publiées.
9. **Coûts Firestore** : `.limit(20)` + `fetchMoreActiveAnnonces` (pagination)
   sur le listing public ; plafond défensif sur les annonces vendeur (tri
   client conservé, un `orderBy('dateCreation')` aurait exclu les annonces
   historiques qui n'ont que l'ancien champ `createdAt`) ; cache Riverpod
   par vendeur (`sellerProfileProvider`) partagé entre marketplace et
   détail d'annonce ; suppression complète de la notification de masse à
   la publication d'un statut (`onNewStatus` lisait tous les acheteurs +
   toutes leurs sous-collections `devices` à chaque publication — décision
   produit : le feed paginé reste le canal de découverte, pas de sujet FCM
   ni de préférences d'abonnement dans cette passe) ; `.limit(30)` sur la
   liste de conversations.
10. **Fidélité** : logique intacte (comme demandé), commentaire "placeholder"
    remplacé par une documentation claire du barème (méthode de calcul,
    taux, date d'entrée en vigueur).

**Tests** : 7 nouveaux cas de règles messagerie, 4 nouveaux cas
statuts/statusLikes (53/53 au total côté émulateur), test widget
`FullscreenImageViewer` (balayage sur 5 photos), 3 nouveaux tests
`AuthNotifier._restoreSession` (erreur réseau persistante, profil absent,
cas nominal). CI (`ci.yml`) : ajout de `flutter build web` et
`node --check functions/index.js` (`npm test` dans `functions/`), qui ne
tournaient auparavant que dans `deploy-pages.yml`, jamais sur les PR.

## Phase 6bis — Corrections de suivi sur la Phase 6 (7 points)

Vérification indépendante demandée par l'utilisateur sur 7 points précis de
la Phase 6, effectuée par relecture directe du code (pas de nouvelle
exploration à l'aveugle). 3 régressions/risques réels confirmés et non
détectés en Phase 6, 2 omissions, et 1 décision produit reconsidérée à la
demande de l'utilisateur.

1. **Canaux Android** : le canal unique `occasion_channel` remplacé par
   trois canaux dédiés (`occasion_messages`, `occasion_orders`,
   `occasion_general`), chacun avec sa propre vibration explicite. Un canal
   Android ne peut pas être reconfiguré une fois créé sur l'appareil — d'où
   des identifiants distincts plutôt qu'une modification du canal existant.
   Mapping type → canal synchronisé entre `functions/index.js`
   (`androidChannelIdForType`) et `lib/services/notification_service.dart`
   (`_channelForType`).
2. **Idempotence de `sendToUser`** : le fix Phase 6 (lecture `pushSentAt`
   puis écriture séparée après l'envoi FCM) restait racy — deux appels
   quasi simultanés pouvaient tous les deux lire "non envoyé" avant que
   l'un des deux n'écrive le marqueur. Remplacé par `claimPushSlot`, une
   transaction Firestore qui lit et réserve le marqueur atomiquement juste
   avant l'appel FCM ; en cas d'échec réel de l'envoi, le marqueur est
   retiré (`FieldValue.delete()`) pour que l'échec reste retentable.
3. **Course sur le compteur lu/non lu** : `markAsRead` remettait le
   compteur à `0` par une écriture absolue, ce qui pouvait écraser
   silencieusement un `increment(1)` serveur concurrent (message reçu au
   moment même où l'utilisateur ouvre la conversation). Remplacé par
   `FieldValue.increment(-n)` où `n` est le nombre exact de messages
   marqués lus dans le lot — commutatif avec les incréments serveur quel
   que soit l'ordre d'arrivée. `firestore.rules` assoupli en conséquence :
   le client peut décrémenter son propre compteur de tout montant partiel
   (plus seulement le remettre à 0), toujours interdit de l'augmenter.
4. **Vidéos du feed** : dimensionnement aligné sur les images
   (`AspectRatio` + `FittedBox(fit: BoxFit.contain)` sur fond noir) au lieu
   d'un `FittedBox(fit: BoxFit.cover)` autour des dimensions natives.
5. **Notification de publication** : réintroduite via un sujet FCM global
   `new_status` (au lieu de la suppression pure décidée en Phase 6) — tout
   acheteur s'y abonne automatiquement à l'enregistrement de son appareil
   (pas d'écran de préférence, décision produit confirmée avec
   l'utilisateur). `onNewStatus` n'effectue plus aucune lecture
   Firestore (ni utilisateurs ni sous-collections `devices`), un seul
   appel `fcm.send({topic: ...})`.
6. **Tests réels des Cloud Functions** : nouveau
   `functions/test/functions.test.js` (6 tests) exécuté contre le véritable
   émulateur Firestore via `.run()` (méthode exposée par les fonctions
   `onCall`/`onDocumentCreated` de `firebase-functions` v2, qui invoque le
   handler directement sans mock) : idempotence de
   `incrementChatUnread`/`onNewMessage`, concurrence de `claimPushSlot`,
   bascule `toggleStatusLike`, chunking de `deleteStatus` (450 likes
   seedés), atomicité de `applySettlement` sous double confirmation
   concurrente, garde-fous de `recordAnnonceView`. Exécuté dans le même
   `firebase emulators:exec` que `firestore-tests` (CI mise à jour).
7. **Suppression des likes par lots** : `deleteStatus` construisait un seul
   `batch()` pour le statut + tous ses likes, risquant de dépasser la
   limite de 500 écritures/batch sur un statut viral (échec total de la
   suppression). Découpé en lots de 400.

**Tests** : 2 nouveaux cas de règles messagerie (décrément partiel autorisé,
augmentation toujours refusée — 55/55 au total côté émulateur rules) ; 6
nouveaux tests d'intégration Cloud Functions (`functions/test/`,
`npm run test:integration`, contre l'émulateur réel).

## Phase 6ter — Durcissement de l'idempotence du push (bug résiduel de la Phase 6bis)

Le fix Phase 6bis (`claimPushSlot` transactionnel) restait incomplet sur
deux cas non couverts :

1. **Échec total silencieux** : si `fcm.sendEachForMulticast` répondait
   sans lever d'exception mais avec 100% des jetons en échec (aucun des
   deux codes d'erreur surveillés par le nettoyage des jetons), le
   marqueur `pushSentAt` restait posé indéfiniment — la notification était
   marquée "envoyée" alors qu'aucun push n'avait atteint l'utilisateur, et
   plus aucune redélivrance ne pouvait jamais retenter l'envoi.
2. **Absence de bail** : si la Cloud Function s'arrêtait (crash, timeout)
   entre la réservation du slot et l'application du résultat FCM, le
   marqueur posé par la réservation restait lui aussi bloqué pour
   toujours, sans jamais expirer.

**Fix** : remplacement du simple champ `pushSentAt` par une machine à
états `pushState` (`functions/index.js`) : `pending` (jamais tenté),
`sending` (réservation posée par `claimPushSlot`, avec un bail
`pushLeaseUntil` de `PUSH_LEASE_MS = 2 min` — une réservation dont le bail
a expiré peut être reprise par un appel suivant), `sent` (au moins un
succès FCM réel, appliqué par `applyPushResult` uniquement si
`result.successCount > 0`), `failed` (tenté, zéro succès ou exception —
retentable), `pending_no_device` (aucun appareil enregistré au moment de
l'appel, posé par `markNoDevicePush`, sans jamais régresser un état déjà
`sent`). Le contenu de la notification (titre/corps/route/data) est
maintenant mis à jour séparément par `upsertNotificationContent`, qui ne
touche jamais `isRead`/`createdAt` sur une redélivrance — une notification
déjà lue par l'utilisateur ne peut plus jamais redevenir non lue à cause
d'un retry du trigger appelant.

**Tests** : 6 nouveaux tests d'intégration Cloud Functions au total pour
cette partie (création initiale de la notification, aucun appareil,
reprise après bail expiré, échec total non marqué comme envoyé et
retentable, au moins un succès marqué `sent` avec nettoyage du jeton
invalide, contenu mis à jour sans jamais réinitialiser `isRead`).

## Phase 6quater — Compteurs non lus : élimination du risque de valeur négative/incohérente

La Phase 6bis (décrément exact `increment(-n)`) restait vulnérable à deux
scénarios non couverts : un message marqué lu par le client avant même
qu'`onNewMessage` ne l'ait traité pouvait quand même incrémenter le
compteur ensuite (le marqueur `unreadCounted` ne portait aucune
information sur le statut au moment du traitement) ; et rien
n'empêchait structurellement un compteur de devenir négatif si
l'historique était déjà incohérent (le client gardait la main sur
l'écriture finale du compteur).

**Fix** :
- `incrementChatUnread` (`functions/index.js`) remplace le marqueur
  unique `unreadCounted` par deux marqueurs distincts posés dans la même
  transaction : `unreadProcessed` (ce message a déjà été traité, jamais
  retraité sur redélivrance) et `unreadIncrementApplied` (le compteur a
  RÉELLEMENT été incrémenté pour ce message — `false` si le message était
  déjà `status: read` au moment du traitement, course avec
  `markChatAsRead`).
- Le client ne modifie plus JAMAIS `buyerUnreadCount`/`sellerUnreadCount`
  ni le `status` d'un message, y compris pour les diminuer
  (`firestore.rules`) : tout passe désormais par la nouvelle Cloud
  Function callable `markChatAsRead`, qui identifie l'utilisateur via
  `request.auth.uid` (jamais un paramètre client), pagine les messages non
  lus par lots de 200, et calcule le nouveau compteur comme
  `max(0, actuel - nombreDeMessagesAvecIncrémentAppliqué)` dans une
  transaction par page (jamais un `increment` négatif non borné : la
  transaction se relance automatiquement si `onNewMessage` incrémente le
  compteur au même moment, garantissant qu'aucune écriture n'est perdue et
  que le résultat ne peut jamais devenir négatif).
- `ChatService.markAsRead` (Flutter) appelle désormais cette fonction au
  lieu d'écrire directement Firestore, avec un verrou local par `chatId`
  pour éviter deux appels concurrents identiques.
- Script de migration `tool/migrate_chat_unread_processing.dart`
  (dry-run par défaut) pour initialiser ces marqueurs sur les messages
  antérieurs à ce changement et recaler les compteurs existants, sans
  jamais supprimer de champ ni exécuter automatiquement l'écriture.

**Tests** : 9 nouveaux tests d'intégration Cloud Functions (course avec
`markChatAsRead`, remise à 0, idempotence, jamais de valeur négative même
sur un historique incohérent, cohérence sous concurrence avec un nouveau
message, isolation stricte entre participants, rejets
non-authentifié/non-participant, pagination sur 250 messages non lus) et
9 tests de règles Firestore (compteurs et statut totalement non
modifiables par le client, autres métadonnées du chat toujours
modifiables). **80 tests au total côté émulateur : 59 rules + 21
fonctions.**

## Phases suivantes (hors de portée de cette session)

- Écran administrateur dédié aux demandes d'abonnement + Cloud Function
  d'activation sécurisée (évalué en Phase 4 : faible valeur ajoutée,
  l'écran générique différencie déjà commande/abonnement).
- App Check.
- Documentation d'optimisation des coûts Firestore (partiellement traitée
  en Phase 6 : pagination/plafonds ajoutés, pas de document dédié).
- Migrations généralisées (anciens signalements, anciens champs). Le champ
  legacy `users/{uid}.fcmToken` n'est plus écrit à partir de cette phase ;
  les appareils déjà connectés migrent automatiquement vers
  `users/{uid}/devices/{deviceId}` à la prochaine ouverture de l'app (pas de
  script de migration dédié — bascule naturelle, pas de perte de
  fonctionnalité entre-temps puisque `sendToUser` ne lit que la nouvelle
  sous-collection).
- Suite de tests Firebase Emulator exhaustive (rôles, sécurité, tous les
  scénarios listés dans le cahier des charges original).
- Écran de liste "Favoris" réellement branché (le système de like sur les
  annonces existe déjà côté données, `lib/favoris/`, juste pas d'écran de
  liste dédié — route `/favorites` masquée en attendant).
- Pagination "charger plus" pour les annonces publiques : la méthode
  `fetchMoreActiveAnnonces` existe côté repository mais n'est pas encore
  branchée à un bouton/scroll infini dans l'écran marketplace (seules les
  20 annonces les plus récentes sont visibles en temps réel pour l'instant).
- Plan de validation sur appareils physiques.
