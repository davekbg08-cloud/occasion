import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/status.dart';
import '../services/status_service.dart';

class StatusState {
  const StatusState({
    this.statuses = const [],
    this.likedIds = const {},
    this.viewedIds = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.isUploading = false,
    this.uploadProgress,
    this.error,
  });

  final List<Status> statuses;
  final Set<String> likedIds;
  final Set<String> viewedIds;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isUploading;
  final StatusUploadProgress? uploadProgress;
  final String? error;

  bool isLiked(String statusId) => likedIds.contains(statusId);
  bool isViewed(String statusId) => viewedIds.contains(statusId);

  StatusState copyWith({
    List<Status>? statuses,
    Set<String>? likedIds,
    Set<String>? viewedIds,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isUploading,
    StatusUploadProgress? uploadProgress,
    bool clearUploadProgress = false,
    String? error,
    bool clearError = false,
  }) {
    return StatusState(
      statuses: statuses ?? this.statuses,
      likedIds: likedIds ?? this.likedIds,
      viewedIds: viewedIds ?? this.viewedIds,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: clearUploadProgress
          ? null
          : uploadProgress ?? this.uploadProgress,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class StatusNotifier extends StateNotifier<StatusState> {
  StatusNotifier({StatusService? service, Duration? loadTimeout})
    : _service = service ?? StatusService(),
      _loadTimeout = loadTimeout ?? const Duration(seconds: 12),
      super(const StatusState());

  final StatusService _service;
  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
  _feedSubscription;
  bool _feedLoaded = false;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  Timer? _loadTimeoutTimer;

  /// Compte les `toggleLike()` en vol par statut (jamais juste un `Set` :
  /// un double-tap avant résolution du premier appel retirerait l'id trop
  /// tôt). Tant qu'un id est présent ici, le listener de [loadFeed] ne
  /// doit jamais écraser son `likesCount` local avec un instantané encore
  /// susceptible de refléter l'état serveur d'avant le commit de la
  /// bascule — sinon le compteur affiché revient brièvement à l'ancienne
  /// valeur avant de "sauter" au bon nombre une fois le vrai instantané
  /// reçu (régression observée en prod).
  final Map<String, int> _pendingLikeToggles = {};

  /// Le flux `snapshots()` Firestore ne fait JAMAIS échouer sur une simple
  /// instabilité réseau/DNS (déjà observé en prod : `ERR_NAME_NOT_RESOLVED`
  /// récurrent) — il retente silencieusement en arrière-plan, sans jamais
  /// émettre ni données ni erreur s'il n'y a rien en cache local. Sans ce
  /// garde-fou, `isLoading` resterait bloqué à `true` indéfiniment (spinner
  /// sans fin), contrairement au lecteur vidéo qui, lui, est déjà borné.
  /// Configurable (constructeur) uniquement pour permettre aux tests de ne
  /// pas attendre 12 vraies secondes.
  final Duration _loadTimeout;

  void loadFeed() {
    if (_feedLoaded) return;

    _feedLoaded = true;
    _feedSubscription?.cancel();
    state = state.copyWith(isLoading: true, clearError: true);

    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(_loadTimeout, () {
      if (state.isLoading && state.statuses.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error:
              'Connexion instable : impossible de charger le contenu pour '
              'le moment.',
        );
      }
    });

    try {
      _feedSubscription = _service.feed().listen(
        (docs) {
          _loadTimeoutTimer?.cancel();
          _lastDoc = docs.isEmpty ? null : docs.last;
          state = state.copyWith(
            statuses: docs.map((doc) {
              final fresh = Status.fromMap({...doc.data(), 'id': doc.id});
              if ((_pendingLikeToggles[doc.id] ?? 0) <= 0) return fresh;
              // Une bascule de like est en vol pour ce statut : garder le
              // compteur local optimiste plutôt que celui de l'instantané,
              // qui peut encore refléter l'état serveur d'avant le commit
              // de toggleLike() — les autres champs (légende, actif...)
              // restent bien ceux à jour.
              Status? local;
              for (final status in state.statuses) {
                if (status.id == doc.id) {
                  local = status;
                  break;
                }
              }
              return local == null
                  ? fresh
                  : fresh.copyWith(likesCount: local.likesCount);
            }).toList(),
            isLoading: false,
            hasMore: docs.length >= StatusService.feedPageSize,
            clearError: true,
          );
        },
        onError: (Object error) {
          _loadTimeoutTimer?.cancel();
          state = state.copyWith(isLoading: false, error: error.toString());
        },
      );
    } catch (error) {
      _loadTimeoutTimer?.cancel();
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  /// Relance le chargement après un échec (bouton "Réessayer") — sans quoi
  /// [loadFeed] ne referait rien puisque `_feedLoaded` est déjà à `true`.
  void retryLoadFeed() {
    _feedLoaded = false;
    loadFeed();
  }

  /// Charge la page suivante du feed (pagination), à appeler quand
  /// l'utilisateur approche de la fin de la liste déjà chargée.
  Future<void> loadMore() async {
    final lastDoc = _lastDoc;
    if (lastDoc == null ||
        !state.hasMore ||
        state.isLoadingMore ||
        state.isLoading) {
      return;
    }

    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final docs = await _service
          .fetchMoreFeed(after: lastDoc)
          .timeout(_loadTimeout);
      if (docs.isNotEmpty) _lastDoc = docs.last;
      state = state.copyWith(
        statuses: [
          ...state.statuses,
          ...docs.map((doc) => Status.fromMap({...doc.data(), 'id': doc.id})),
        ],
        isLoadingMore: false,
        hasMore: docs.length >= StatusService.feedPageSize,
      );
    } catch (error) {
      state = state.copyWith(isLoadingMore: false, error: error.toString());
    }
  }

  /// Restaure l'état "j'ai déjà aimé" depuis Firestore (`statusLikes`), qui
  /// persiste après reconnexion — contrairement à l'ancien `Set` en mémoire
  /// jamais alimenté qu'en local.
  Future<void> loadLikedStatuses(String userId) async {
    if (userId.isEmpty) return;
    try {
      final ids = await _service.likedStatusIds(userId);
      state = state.copyWith(likedIds: ids);
    } catch (_) {
      // Best-effort : un like déjà connu côté serveur qui échoue à se
      // charger ne doit pas bloquer l'affichage du feed.
    }
  }

  /// Restaure l'état "déjà vu" depuis Firestore (`statusViews`), même
  /// principe que [loadLikedStatuses] — pilote la couleur des bulles
  /// "stories" de l'accueil (`StatusStrip`).
  Future<void> loadViewedStatuses(String userId) async {
    if (userId.isEmpty) return;
    try {
      final ids = await _service.viewedStatusIds(userId);
      state = state.copyWith(viewedIds: ids);
    } catch (_) {
      // Best-effort : ne doit jamais bloquer l'affichage du feed.
    }
  }

  /// Marque [statusId] comme vu par [userId] — optimiste (mise à jour
  /// immédiate de l'état local) puis persisté côté serveur ; en cas
  /// d'échec réseau, la bulle reste "vue" pour cette session (best-effort,
  /// se resynchronisera au prochain [loadViewedStatuses]).
  Future<void> markViewed(String statusId, String userId) async {
    if (userId.isEmpty || state.viewedIds.contains(statusId)) return;
    state = state.copyWith(viewedIds: {...state.viewedIds, statusId});
    try {
      await _service.markViewed(statusId, userId);
    } catch (_) {
      // Best-effort, voir ci-dessus.
    }
  }

  Future<bool> createStatus({
    required String sellerId,
    required String sellerName,
    String? sellerProfileImageUrl,
    required XFile mediaFile,
    required StatusType type,
    String? caption,
    String? productId,
  }) async {
    state = state.copyWith(
      isUploading: true,
      clearUploadProgress: true,
      clearError: true,
    );

    try {
      await _service.createStatus(
        sellerId: sellerId,
        sellerName: sellerName,
        sellerProfileImageUrl: sellerProfileImageUrl,
        mediaFile: mediaFile,
        type: type,
        caption: caption,
        productId: productId,
        onProgress: (progress) {
          state = state.copyWith(uploadProgress: progress);
        },
      );
      state = state.copyWith(
        isUploading: false,
        clearUploadProgress: true,
        clearError: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isUploading: false,
        clearUploadProgress: true,
        error: error.toString(),
      );
      return false;
    }
  }

  /// Bascule le like en optimiste (UI instantanée), puis réconcilie avec la
  /// réponse serveur (`toggleStatusLike`, transaction anti-double-like) —
  /// annule l'effet optimiste en cas d'échec réseau, ou corrige le
  /// compteur/l'état si le serveur renvoie un résultat différent de la
  /// supposition locale (ex. déjà basculé depuis un autre appareil).
  Future<void> toggleLike(String statusId) async {
    _pendingLikeToggles.update(statusId, (n) => n + 1, ifAbsent: () => 1);

    final guessedLiked = !state.likedIds.contains(statusId);
    final optimisticDelta = guessedLiked ? 1 : -1;

    state = state.copyWith(
      statuses: [
        for (final status in state.statuses)
          if (status.id == statusId)
            status.copyWith(likesCount: status.likesCount + optimisticDelta)
          else
            status,
      ],
      likedIds: guessedLiked
          ? {...state.likedIds, statusId}
          : ({...state.likedIds}..remove(statusId)),
      clearError: true,
    );

    try {
      final actuallyLiked = await _service.toggleLike(statusId);
      if (actuallyLiked == guessedLiked) return;

      // Le serveur a tranché différemment de notre supposition locale :
      // corriger le compteur (annuler l'optimiste, appliquer le réel) et
      // l'état "liké".
      final correctionDelta = actuallyLiked ? 1 : -1;
      state = state.copyWith(
        statuses: [
          for (final status in state.statuses)
            if (status.id == statusId)
              status.copyWith(
                likesCount:
                    status.likesCount - optimisticDelta + correctionDelta,
              )
            else
              status,
        ],
        likedIds: actuallyLiked
            ? {...state.likedIds, statusId}
            : ({...state.likedIds}..remove(statusId)),
      );
    } catch (error) {
      state = state.copyWith(
        statuses: [
          for (final status in state.statuses)
            if (status.id == statusId)
              status.copyWith(likesCount: status.likesCount - optimisticDelta)
            else
              status,
        ],
        likedIds: guessedLiked
            ? ({...state.likedIds}..remove(statusId))
            : {...state.likedIds, statusId},
        error: error.toString(),
      );
    } finally {
      final remaining = (_pendingLikeToggles[statusId] ?? 1) - 1;
      if (remaining <= 0) {
        _pendingLikeToggles.remove(statusId);
      } else {
        _pendingLikeToggles[statusId] = remaining;
      }
    }
  }

  Future<void> deleteStatus(String statusId) async {
    try {
      await _service.deleteStatus(statusId);
      state = state.copyWith(
        statuses: state.statuses
            .where((status) => status.id != statusId)
            .toList(),
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  @override
  void dispose() {
    _feedSubscription?.cancel();
    _loadTimeoutTimer?.cancel();
    super.dispose();
  }
}

final statusNotifierProvider =
    StateNotifierProvider<StatusNotifier, StatusState>((ref) {
      return StatusNotifier();
    });
