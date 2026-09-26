import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_language.dart';
import '../providers/auth_provider.dart';
import '../services/phone_number_validator.dart';

/// Numéro Mobile Money sur lequel le vendeur reçoit l'argent de ses
/// ventes (reversement pawaPay, commission Occasion déduite).
class PayoutAccountScreen extends ConsumerStatefulWidget {
  const PayoutAccountScreen({super.key});

  @override
  ConsumerState<PayoutAccountScreen> createState() =>
      _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends ConsumerState<PayoutAccountScreen> {
  static const _providers = <String, String>{
    'VODACOM_MPESA_COD': 'M-Pesa',
    'AIRTEL_COD': 'Airtel Money',
    'ORANGE_COD': 'Orange Money',
  };

  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  String? _provider;
  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>>? get _ref {
    final uid = ref.read(authNotifierProvider).currentUser?.id;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('payoutAccounts').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _ref?.get();
      final data = snap?.data();
      if (data != null) {
        _provider = data['provider'] as String?;
        _phoneController.text = '+${data['phoneNumber'] ?? ''}';
        _nameController.text = data['holderName'] as String? ?? '';
      }
    } catch (_) {
      // Pas encore de compte enregistré : formulaire vide.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = _provider;
    if (provider == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Choisis ton opérateur Mobile Money.'))),
      );
      return;
    }
    final phone = PhoneNumberValidator.validate(
      _phoneController.text,
      countryIso: 'CD',
    );
    if (!phone.isValid) {
      messenger.showSnackBar(SnackBar(content: Text(phone.message)));
      return;
    }
    final name = _nameController.text.trim();
    if (name.length < 2) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Indique le nom du titulaire du compte.'))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _ref?.set({
        'provider': provider,
        'phoneNumber': phone.normalized.replaceAll('+', ''),
        'holderName': name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr('Numéro de reversement enregistré.')),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr("Échec de l'enregistrement. Réessaie.")),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Numéro de reversement'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr(
                    "L'argent de tes ventes payées par Mobile Money est envoyé sur ce numéro, après confirmation de réception par l'acheteur. Occasion retient une commission de 4 %.",
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr('Ton opérateur'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in _providers.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _provider == entry.key,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() => _provider = entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: tr('Numéro Mobile Money'),
                    hintText: '+243 8xx xxx xxx',
                    prefixIcon: const Icon(Icons.phone_android),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: tr('Nom du titulaire du compte'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(tr('Enregistrer')),
                ),
              ],
            ),
    );
  }
}
