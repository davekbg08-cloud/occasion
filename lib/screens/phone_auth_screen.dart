import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = ref.read(authNotifierProvider);
    final role = auth.selectedRole ?? UserRole.buyer;

    await ref
        .read(authNotifierProvider.notifier)
        .login(
          role: role,
          displayName: _nameController.text,
          phoneNumber: _phoneController.text,
        );

    if (!mounted) return;

    context.go(role == UserRole.seller ? '/subscription' : '/home');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final role = auth.selectedRole ?? UserRole.buyer;
    final roleLabel = role == UserRole.seller ? 'vendeur' : 'acheteur';

    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Profil $roleLabel',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Entrez vos informations pour ouvrir la session.'),
          const SizedBox(height: 28),
          TextField(
            controller: _nameController,
            enabled: !auth.isLoading,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nom',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            enabled: !auth.isLoading,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telephone',
              hintText: '+243 000 000 000',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: auth.isLoading ? null : _login,
              icon: auth.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(auth.isLoading ? 'Connexion...' : 'Continuer'),
            ),
          ),
        ],
      ),
    );
  }
}
