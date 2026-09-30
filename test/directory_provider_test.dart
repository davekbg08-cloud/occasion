import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/user.dart';
import 'package:occasion/providers/directory_provider.dart';

UserModel _user(String id, String name, {UserRole role = UserRole.buyer}) {
  return UserModel(
    id: id,
    name: name,
    phone: '',
    role: role,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('filterDirectory', () {
    final all = [
      _user('me', 'Moi-même'),
      _user('u1', 'Alice Kabongo', role: UserRole.seller),
      _user('u2', 'Bob Mukendi'),
      _user('u3', 'alice tshisola'),
    ];

    test('exclut toujours l\'utilisateur lui-même', () {
      final result = filterDirectory(
        all,
        selfId: 'me',
        blockedUserIds: const {},
      );
      expect(result.any((u) => u.id == 'me'), isFalse);
      expect(result.length, 3);
    });

    test('exclut les utilisateurs bloqués', () {
      final result = filterDirectory(
        all,
        selfId: 'me',
        blockedUserIds: const {'u2'},
      );
      expect(result.map((u) => u.id), ['u1', 'u3']);
    });

    test('recherche insensible à la casse sur le nom', () {
      final result = filterDirectory(
        all,
        selfId: 'me',
        blockedUserIds: const {},
        query: 'ALICE',
      );
      expect(result.map((u) => u.id).toSet(), {'u1', 'u3'});
    });

    test('recherche vide (ou espaces) ne filtre rien', () {
      final result = filterDirectory(
        all,
        selfId: 'me',
        blockedUserIds: const {},
        query: '   ',
      );
      expect(result.length, 3);
    });

    test('combine exclusion de soi-même, des bloqués et la recherche', () {
      final result = filterDirectory(
        all,
        selfId: 'me',
        blockedUserIds: const {'u1'},
        query: 'a',
      );
      // 'u1' (Alice, bloquée) exclue ; 'u3' (alice) et 'u2' (Bob... pas de
      // 'a') -> seul 'u3' correspond à la fois au filtre bloqué et à la
      // recherche 'a'.
      expect(result.map((u) => u.id), ['u3']);
    });
  });
}
