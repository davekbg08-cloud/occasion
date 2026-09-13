import 'package:cloud_functions/cloud_functions.dart';

/// Déclenche `ensureReferralCode` (Cloud Function) — voir ce fichier pour
/// le pourquoi : les comptes créés avant l'ajout du parrainage n'ont
/// jamais reçu de `referralCode` (le déclencheur `onUserCreated` ne
/// s'exécute qu'à la création du compte), donc l'écran Parrainage doit
/// pouvoir demander sa génération a posteriori.
class ReferralService {
  ReferralService({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

  Future<void> ensureReferralCode() async {
    await _functions.httpsCallable('ensureReferralCode').call();
  }
}
