import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/providers/subscription_provider.dart';

void main() {
  test('la demande d’abonnement transmet à l’admin le numéro et le titulaire '
      'Orange Money qui ont payé', () async {
    final firestore = FakeFirebaseFirestore();
    final notifier = SubscriptionNotifier(
      firestore: firestore,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'v1')),
    );
    addTearDown(notifier.dispose);

    final id = await notifier.submitManualSubscriptionPayment(
      planId: 'seller_monthly',
      planName: 'Vendeur Mensuel',
      price: 7,
      manualPaymentReference: 'MP241005.1234.A56789',
      payerPhone: '+243856373707',
      payerName: 'Dave K.',
    );

    final intent = (await firestore.collection('paymentIntents').doc(id).get())
        .data()!;
    expect(intent['status'], 'awaiting_manual_verification');
    expect(intent['manualPaymentReference'], 'MP241005.1234.A56789');
    expect(intent['manualPayerPhone'], '+243856373707');
    expect(intent['manualPayerName'], 'Dave K.');
    expect(intent['userId'], 'v1');
  });
}
