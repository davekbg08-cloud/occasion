import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user.dart';

export '../models/user.dart';

class AuthState {
  const AuthState({
    required this.isAuthenticated,
    this.isLoading = false,
    this.selectedRole,
    this.user,
    this.errorMessage,
  });

  final bool isAuthenticated;
  final bool isLoading;
  final UserRole? selectedRole;
  final UserModel? user;
  final String? errorMessage;

  UserModel? get currentUser => isAuthenticated ? user : null;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserRole? selectedRole,
    UserModel? user,
    String? errorMessage,
    bool clearSelectedRole = false,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      selectedRole: clearSelectedRole
          ? null
          : selectedRole ?? this.selectedRole,
      user: clearUser ? null : user ?? this.user,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({
    firebase_auth.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth ?? firebase_auth.FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       super(const AuthState(isAuthenticated: false, isLoading: true)) {
    _authSubscription = _auth.authStateChanges().listen(
      _restoreSession,
      onError: (error) {
        state = state.copyWith(
          isAuthenticated: false,
          isLoading: false,
          clearUser: true,
          clearSelectedRole: true,
          errorMessage: 'Session Firebase indisponible. Reconnecte-toi.',
        );
      },
    );
  }

  final firebase_auth.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  StreamSubscription<firebase_auth.User?>? _authSubscription;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  void selectRole(UserRole role) {
    state = state.copyWith(selectedRole: role, clearError: true);
  }

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _restoreSession(credential.user);
    } on firebase_auth.FirebaseAuthException catch (error) {
      _fail(_authMessage(error));
      rethrow;
    } catch (_) {
      _fail('Connexion impossible. Vérifie ta connexion puis réessaie.');
      rethrow;
    }
  }

  Future<void> register({
    required UserRole role,
    required String displayName,
    required String phoneNumber,
    required String email,
    required String password,
  }) async {
    final name = displayName.trim();
    final phone = phoneNumber.trim();
    if (name.isEmpty) {
      throw ArgumentError('Le nom est obligatoire.');
    }
    if (!_isValidCongolesePhone(phone)) {
      throw ArgumentError('Numéro invalide. Utilisez le format +243…');
    }
    if (email.trim().isEmpty) {
      throw ArgumentError('L’adresse e-mail est obligatoire.');
    }
    if (password.length < 6) {
      throw ArgumentError(
        'Le mot de passe doit contenir au moins 6 caractères.',
      );
    }

    state = state.copyWith(
      isLoading: true,
      selectedRole: role,
      clearError: true,
    );
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw StateError('Compte Firebase créé sans identifiant utilisateur.');
      }

      await firebaseUser.updateDisplayName(name);
      final user = UserModel(
        id: firebaseUser.uid,
        name: name,
        phone: phone,
        role: role,
        createdAt: DateTime.now(),
      );

      await _users.doc(firebaseUser.uid).set({
        ...user.toMap(),
        'email': email.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        clearSelectedRole: true,
        clearError: true,
        user: user,
      );
    } on firebase_auth.FirebaseAuthException catch (error) {
      _fail(_authMessage(error));
      rethrow;
    } catch (error) {
      final message = error is ArgumentError
          ? error.message.toString()
          : 'Inscription impossible. Réessaie dans un instant.';
      _fail(message);
      rethrow;
    }
  }

  Future<void> updateProfilePhoto(XFile image) async {
    final firebaseUser = _auth.currentUser;
    final currentUser = state.currentUser;
    if (firebaseUser == null || currentUser == null) {
      throw StateError('Connecte-toi avant de modifier la photo.');
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final bytes = await image.readAsBytes();
      final extension = _extension(image.name);
      final ref = _storage.ref().child(
        'profile_photos/${firebaseUser.uid}/profile.$extension',
      );
      await ref.putData(
        bytes,
        SettableMetadata(contentType: _contentType(extension)),
      );
      final url = await ref.getDownloadURL();

      await _users.doc(firebaseUser.uid).set({
        'profileImageUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      state = state.copyWith(
        isLoading: false,
        clearError: true,
        user: currentUser.copyWith(profileImageUrl: url),
      );
    } catch (_) {
      _fail('Impossible de mettre à jour la photo de profil.');
      rethrow;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    state = state.copyWith(
      isAuthenticated: false,
      isLoading: false,
      clearSelectedRole: true,
      clearUser: true,
      clearError: true,
    );
  }

  Future<void> _restoreSession(firebase_auth.User? firebaseUser) async {
    if (firebaseUser == null) {
      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
        clearUser: true,
        clearSelectedRole: true,
        clearError: true,
      );
      return;
    }

    try {
      final snapshot = await _users.doc(firebaseUser.uid).get();
      final data = snapshot.data();
      if (data == null) {
        await _auth.signOut();
        state = state.copyWith(
          isAuthenticated: false,
          isLoading: false,
          clearUser: true,
          clearSelectedRole: true,
          errorMessage:
              'Profil Occasion introuvable. Crée un compte acheteur ou vendeur.',
        );
        return;
      }

      final user = UserModel.fromMap({...data, 'id': firebaseUser.uid});
      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        clearSelectedRole: true,
        clearError: true,
        user: user,
      );
    } catch (_) {
      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
        clearUser: true,
        errorMessage: 'Impossible de charger le profil utilisateur.',
      );
    }
  }

  void _fail(String message) {
    state = state.copyWith(
      isAuthenticated: false,
      isLoading: false,
      clearUser: true,
      errorMessage: message,
    );
  }

  String _extension(String name) {
    final parts = name.toLowerCase().split('.');
    final extension = parts.length > 1 ? parts.last : 'jpg';
    if (extension == 'png' || extension == 'webp') return extension;
    return 'jpg';
  }

  String _contentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  String _authMessage(firebase_auth.FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'Cette adresse e-mail est déjà utilisée.';
      case 'invalid-email':
        return 'Adresse e-mail invalide.';
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'E-mail ou mot de passe incorrect.';
      case 'weak-password':
        return 'Le mot de passe doit contenir au moins 6 caractères.';
      case 'network-request-failed':
        return 'Connexion réseau indisponible. Réessaie dans un instant.';
      default:
        return error.message ?? 'Authentification Firebase impossible.';
    }
  }

  bool _isValidCongolesePhone(String phone) {
    return RegExp(r'^\+243\d{9}$').hasMatch(phone.trim());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
