import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/providers/annonce_viewers_provider.dart';
import 'package:occasion/screens/annonce_viewers_screen.dart';

void main() {
  group('buildAnnonceViewers', () {
    test('garde l’ordre des vues et lit nom/photo dans le profil public', () {
      final viewers = buildAnnonceViewers(
        [
          (uid: 'b', viewedAt: DateTime(2026, 10, 11, 10), visits: 3),
          (uid: 'a', viewedAt: DateTime(2026, 10, 10), visits: 1),
        ],
        {
          'a': {'name': 'Fifi', 'profileImageUrl': 'https://x/f.jpg'},
          'b': {'name': 'Dave', 'profileImageUrl': ''},
        },
      );
      expect(viewers.map((v) => v.uid), ['b', 'a']);
      expect(viewers.first.name, 'Dave');
      expect(viewers.first.profileImageUrl, isNull);
      expect(viewers.first.visits, 3);
      expect(viewers.last.profileImageUrl, 'https://x/f.jpg');
    });

    test('écarte les comptes supprimés ou sans profil', () {
      final viewers = buildAnnonceViewers(
        [
          (uid: 'gone', viewedAt: null, visits: 1),
          (uid: 'unknown', viewedAt: null, visits: 1),
          (uid: 'ok', viewedAt: null, visits: 0),
        ],
        {
          'gone': {'name': 'Compte supprimé', 'isDeleted': true},
          'ok': {'name': '  '},
        },
      );
      expect(viewers.map((v) => v.uid), ['ok']);
      expect(viewers.single.name, 'Utilisateur');
      expect(viewers.single.visits, 1);
    });
  });

  group('formatViewedAgo', () {
    final now = DateTime(2026, 10, 11, 12);
    test('minutes, heures, hier, jours puis date', () {
      expect(formatViewedAgo(now, now: now), 'à l’instant');
      expect(
        formatViewedAgo(now.subtract(const Duration(minutes: 5)), now: now),
        'il y a 5 min',
      );
      expect(
        formatViewedAgo(now.subtract(const Duration(hours: 3)), now: now),
        'il y a 3 h',
      );
      expect(formatViewedAgo(DateTime(2026, 10, 10, 9), now: now), 'hier');
      expect(
        formatViewedAgo(DateTime(2026, 10, 8, 9), now: now),
        'il y a 3 jours',
      );
      expect(formatViewedAgo(DateTime(2026, 9, 1), now: now), '01/09/26');
    });
  });
}
