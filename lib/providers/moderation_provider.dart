import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/moderation_service.dart';

final moderationServiceProvider = Provider<ModerationService>((ref) {
  return ModerationService();
});

final blockedUserIdsProvider = StreamProvider.family<Set<String>, String>((
  ref,
  currentUserId,
) {
  return ref.watch(moderationServiceProvider).blockedUserIds(currentUserId);
});

final blockedUsersDetailedProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      currentUserId,
    ) {
      return ref
          .watch(moderationServiceProvider)
          .blockedUsersDetailed(currentUserId);
    });
