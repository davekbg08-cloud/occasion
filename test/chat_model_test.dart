import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/chat.dart';

Chat _chat({int buyerUnreadCount = 0, int sellerUnreadCount = 0}) {
  return Chat(
    id: 'chat1',
    buyerId: 'buyer1',
    sellerId: 'seller1',
    buyerName: 'Acheteur',
    sellerName: 'Vendeur',
    buyerUnreadCount: buyerUnreadCount,
    sellerUnreadCount: sellerUnreadCount,
  );
}

void main() {
  group('Chat.unreadCountFor', () {
    test("retourne le compteur de l'acheteur pour l'acheteur", () {
      final chat = _chat(buyerUnreadCount: 3, sellerUnreadCount: 5);
      expect(chat.unreadCountFor('buyer1'), 3);
    });

    test('retourne le compteur du vendeur pour le vendeur', () {
      final chat = _chat(buyerUnreadCount: 3, sellerUnreadCount: 5);
      expect(chat.unreadCountFor('seller1'), 5);
    });
  });

  group('Chat.clearUnreadFor', () {
    test("ne remet à zéro que le compteur de l'acheteur", () {
      final chat = _chat(buyerUnreadCount: 3, sellerUnreadCount: 5);
      final cleared = chat.clearUnreadFor('buyer1');
      expect(cleared.buyerUnreadCount, 0);
      expect(cleared.sellerUnreadCount, 5);
    });

    test('ne remet à zéro que le compteur du vendeur', () {
      final chat = _chat(buyerUnreadCount: 3, sellerUnreadCount: 5);
      final cleared = chat.clearUnreadFor('seller1');
      expect(cleared.sellerUnreadCount, 0);
      expect(cleared.buyerUnreadCount, 3);
    });
  });

  group('Chat.fromMap compatibilité ancien champ unreadCount', () {
    test(
      'retombe sur unreadCount tant que buyerUnreadCount/sellerUnreadCount absents',
      () {
        final chat = Chat.fromMap({
          'id': 'chat1',
          'buyerId': 'buyer1',
          'sellerId': 'seller1',
          'buyerName': 'Acheteur',
          'sellerName': 'Vendeur',
          'unreadCount': 4,
        });
        expect(chat.buyerUnreadCount, 4);
        expect(chat.sellerUnreadCount, 4);
      },
    );

    test('utilise les nouveaux champs par participant une fois migrés', () {
      final chat = Chat.fromMap({
        'id': 'chat1',
        'buyerId': 'buyer1',
        'sellerId': 'seller1',
        'buyerName': 'Acheteur',
        'sellerName': 'Vendeur',
        'unreadCount': 4,
        'buyerUnreadCount': 1,
        'sellerUnreadCount': 0,
      });
      expect(chat.buyerUnreadCount, 1);
      expect(chat.sellerUnreadCount, 0);
    });
  });
}
