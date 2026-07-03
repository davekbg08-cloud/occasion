import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/user.dart';
import '../providers/auth_provider.dart' hide UserRole;
import '../services/phone_number_validator.dart';
import '../widgets/occasion_logo.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key, this.role});

  final UserRole? role;

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _phoneCountryIso = PhoneNumberValidator.defaultCountryIso;
  bool _obscurePassword = true;

  bool get _isRegistration => widget.role != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final notifier = ref.read(authNotifierProvider.notifier);
      if (_isRegistration) {
        await notifier.register(
          role: widget.role!,
          displayName: _nameController.text,
          phoneNumber: _phoneController.text,
          phoneCountryIso: _phoneCountryIso,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await notifier.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }

      if (!mounted) return;
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      final stateMessage = ref.read(authNotifierProvider).errorMessage;
      final message = stateMessage ?? _friendlyError(error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final roleLabel = widget.role == UserRole.seller ? 'vendeur' : 'acheteur';
    final title = _isRegistration ? 'Créer un compte $roleLabel' : 'Connexion';
    final subtitle = _isRegistration
        ? 'Utilise une adresse e-mail, un mot de passe et un numero international valide.'
        : 'Connecte-toi avec ton compte Firebase Occasion.';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const OccasionLogo(size: 132),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(height: 28),
                if (_isRegistration) ...[
                  TextFormField(
                    controller: _nameController,
                    enabled: !auth.isLoading,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nom',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Entre ton nom.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _phoneCountryIso,
                    decoration: const InputDecoration(
                      labelText: 'Pays du numéro',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.public_outlined),
                    ),
                    items: PhoneNumberValidator.countries
                        .map(
                          (country) => DropdownMenuItem(
                            value: country.isoCode,
                            child: Text(
                              '${country.name} (${country.dialCode})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: auth.isLoading
                        ? null
                        : (value) => setState(
                            () => _phoneCountryIso =
                                value ?? PhoneNumberValidator.defaultCountryIso,
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    enabled: !auth.isLoading,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone',
                      hintText: '+243812345678',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (value) {
                      final result = PhoneNumberValidator.validate(
                        value?.trim() ?? '',
                        countryIso: _phoneCountryIso,
                      );
                      return result.isValid ? null : result.message;
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _emailController,
                  enabled: !auth.isLoading,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return 'Entre ton adresse e-mail.';
                    if (!email.contains('@')) return 'Adresse e-mail invalide.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  enabled: !auth.isLoading,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.isEmpty) return 'Entre ton mot de passe.';
                    if (_isRegistration && password.length < 6) {
                      return 'Minimum 6 caractères.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: auth.isLoading ? null : _submit,
                    icon: auth.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isRegistration ? Icons.person_add : Icons.login,
                          ),
                    label: Text(
                      auth.isLoading
                          ? 'Veuillez patienter...'
                          : _isRegistration
                          ? 'Créer le compte'
                          : 'Se connecter',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: auth.isLoading
                      ? null
                      : () => context.go(
                          _isRegistration ? '/login' : '/role-selection',
                        ),
                  child: Text(
                    _isRegistration ? 'J’ai déjà un compte' : 'Créer un compte',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    if (error is ArgumentError) return error.message.toString();
    if (error is StateError) return error.message;
    return 'Authentification impossible. Réessaie.';
  }
}
