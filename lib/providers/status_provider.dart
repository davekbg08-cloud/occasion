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
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.isUploading = false,
    this.uploadProgress,
    this.error,
  });

  final List<Status> statuses;
  final Set<String> likedIds;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isUploading;
  final StatusUploadProgress? uploadProgress;
  final String? error;

  bool isLiked(String statusId) => likedIds.contains(statusId);

  StatusState copyWith({
    List<Status>? statuses,
    Set<String>? likedIds,
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
  StatusNotifier({StatusService? service})
    : _service = service ?? StatusService(),
      super(const StatusState());

  final StatusService _service;
  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
  _feedSubscription;
  bool _feedLoaded = false;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  void loadFeed() {
    if (_feedLoaded) return;

    _feedLoaded = true;
    _feedSubscription?.cancel();
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      _feedSubscription = _service.feed().listen(
        (docs) {
          _lastDoc = docs.isEmpty ? null : docs.last;
          state = state.copyWith(
            statuses: docs
                .map((doc) => Status.fromMap({...doc.data(), 'id': doc.id}))
                .toList(),
            isLoading: false,
            hasMore: docs.length >= StatusService.feedPageSize,
            clearError: true,
          );
        },
        onError: (Object error) {
          state = state.copyWith(isLoading: false, error: error.toString());
        },
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
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
      final docs = await _service.fetchMoreFeed(after: lastDoc);
      if (docs.isNotEmpty) _lastDoc = docs.last;
      state = state.copyWith(
        statuses: [
          ...state.statuses,
          ...docs.map(
            (doc) => Status.fromMap({...doc.data(), 'id': doc.id}),
          ),
        ],
        isLoadingMore: false,
        hasMore: docs.length >= StatusService.feedPageSize,
      );
    } catch (error) {
      state = state.copyWith(isLoadingMore: false, error: error.toString());
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

  Future<void> toggleLike(String statusId) async {
    final liked = state.likedIds.contains(statusId);
    final nextLikedIds = {...state.likedIds};

    if (liked) {
      nextLikedIds.remove(statusId);
    } else {
      nextLikedIds.add(statusId);
    }

    final delta = liked ? -1 : 1;
    final nextStatuses = [
      for (final status in state.statuses)
        if (status.id == statusId)
          status.copyWith(likesCount: status.likesCount + delta)
        else
          status,
    ];

    state = state.copyWith(
      statuses: nextStatuses,
      likedIds: nextLikedIds,
      clearError: true,
    );

    try {
      await _service.toggleLike(statusId, liked: !liked);
    } catch (error) {
      final rollbackLikedIds = {...state.likedIds};
      if (liked) {
        rollbackLikedIds.add(statusId);
      } else {
        rollbackLikedIds.remove(statusId);
      }

      state = state.copyWith(
        statuses: state.statuses
            .map(
              (status) => status.id == statusId
                  ? status.copyWith(likesCount: status.likesCount - delta)
                  : status,
            )
            .toList(),
        likedIds: rollbackLikedIds,
        error: error.toString(),
      );
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
    super.dispose();
  }
}

final statusNotifierProvider =
    StateNotifierProvider<StatusNotifier, StatusState>((ref) {
      return StatusNotifier();
    });
