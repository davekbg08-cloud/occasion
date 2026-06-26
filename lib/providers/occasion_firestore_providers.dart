import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/annonce.dart';
import '../models/favori.dart';
import '../models/firestore/occasion_models.dart';
import '../repositories/occasion_firestore_repositories.dart';

final occasionFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final annoncesCrudRepositoryProvider = Provider<AnnoncesCrudRepository>((ref) {
  return AnnoncesCrudRepository(ref.watch(occasionFirestoreProvider));
});

final favorisCrudRepositoryProvider = Provider<FavorisCrudRepository>((ref) {
  return FavorisCrudRepository(ref.watch(occasionFirestoreProvider));
});

final utilisateursOccasionRepositoryProvider =
    Provider<UtilisateursOccasionRepository>((ref) {
      return UtilisateursOccasionRepository(
        ref.watch(occasionFirestoreProvider),
      );
    });

final messagesOccasionRepositoryProvider = Provider<MessagesOccasionRepository>(
  (ref) {
    return MessagesOccasionRepository(ref.watch(occasionFirestoreProvider));
  },
);

final conversationsOccasionRepositoryProvider =
    Provider<ConversationsOccasionRepository>((ref) {
      return ConversationsOccasionRepository(
        ref.watch(occasionFirestoreProvider),
      );
    });

final signalementsOccasionRepositoryProvider =
    Provider<SignalementsOccasionRepository>((ref) {
      return SignalementsOccasionRepository(
        ref.watch(occasionFirestoreProvider),
      );
    });

final categoriesOccasionRepositoryProvider =
    Provider<CategoriesOccasionRepository>((ref) {
      return CategoriesOccasionRepository(ref.watch(occasionFirestoreProvider));
    });

final notificationsOccasionRepositoryProvider =
    Provider<NotificationsOccasionRepository>((ref) {
      return NotificationsOccasionRepository(
        ref.watch(occasionFirestoreProvider),
      );
    });

final activeAnnoncesStreamProvider = StreamProvider.autoDispose<List<Annonce>>((
  ref,
) {
  return ref.watch(annoncesCrudRepositoryProvider).activeByDate();
});

final categoriesStreamProvider =
    StreamProvider.autoDispose<List<CategorieOccasion>>((ref) {
      return ref.watch(categoriesOccasionRepositoryProvider).ordered();
    });

final userFavorisProvider = StreamProvider.autoDispose
    .family<List<Favori>, String>((ref, userId) {
      return ref.watch(favorisCrudRepositoryProvider).byUser(userId);
    });

final conversationsByParticipantProvider = StreamProvider.autoDispose
    .family<List<ConversationOccasion>, String>((ref, userId) {
      return ref
          .watch(conversationsOccasionRepositoryProvider)
          .byParticipant(userId);
    });

final messagesByConversationProvider = StreamProvider.autoDispose
    .family<List<MessageOccasion>, String>((ref, conversationId) {
      return ref
          .watch(messagesOccasionRepositoryProvider)
          .byConversation(conversationId);
    });

final notificationsByUserProvider = StreamProvider.autoDispose
    .family<List<NotificationOccasion>, String>((ref, userId) {
      return ref.watch(notificationsOccasionRepositoryProvider).byUser(userId);
    });
