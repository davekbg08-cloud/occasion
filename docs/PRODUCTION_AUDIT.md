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

**Décision** : refonte complète différée à une phase ultérieure (chantier
important : nouvelle collection `notifications` réellement branchée,
multi-appareils `users/{uid}/devices/{deviceId}`, Cloud Function idempotente,
`NotificationRouter`). Non traité dans la Phase 1.

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

**Décision** : unification complète (fusionner les deux piles, une seule
conversion `Annonce → ProductModel`, un seul schéma canonique de champs)
différée à une phase ultérieure — changement transverse à fort risque de
régression, à traiter isolément avec sa propre suite de tests. Non traité
dans la Phase 1.

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

**Décision** : agrégats serveur via Cloud Functions différés à une phase
ultérieure. Non traité en Phase 1.

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

## Phases suivantes (hors de portée de cette session)

- Refonte complète des notifications (persistance réelle + multi-appareils +
  Cloud Function idempotente + routeur de notifications).
- Écran administrateur dédié aux demandes d'abonnement + Cloud Function
  d'activation sécurisée.
- Système de fidélité/récompenses acheteur et vendeur (entièrement nouveau).
- Statistiques serveur agrégées via Cloud Functions.
- Unification complète des deux piles de providers d'annonces.
- App Check.
- Documentation d'optimisation des coûts Firestore.
- Migrations généralisées (anciens signalements, anciens champs, anciens
  tokens FCM).
- Suite de tests Firebase Emulator exhaustive (rôles, sécurité, tous les
  scénarios listés dans le cahier des charges original).
- Plan de validation sur appareils physiques.
