import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user.dart';
import '../services/image_compression_service.dart';
import '../services/phone_number_validator.dart';

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
    String phoneCountryIso = PhoneNumberValidator.defaultCountryIso,
    required String email,
    required String password,
  }) async {
    final name = displayName.trim();
    final phoneValidation = PhoneNumberValidator.validate(
      phoneNumber,
      countryIso: phoneCountryIso,
    );
    final phone = phoneValidation.normalized;
    if (name.isEmpty) {
      throw ArgumentError('Le nom est obligatoire.');
    }
    if (!phoneValidation.isValid) {
      throw ArgumentError(phoneValidation.message);
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
        phoneVerified: false,
        identityStatus: SellerIdentityStatus.unverified,
      );

      await _users.doc(firebaseUser.uid).set({
        ...user.toMap(),
        'email': email.trim(),
        'phoneCountry': phoneValidation.country?.isoCode ?? phoneCountryIso,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _firestore.collection('publicProfiles').doc(firebaseUser.uid).set({
        'id': firebaseUser.uid,
        'name': name,
        'role': role.name,
        'profileImageUrl': null,
        'identityStatus': SellerIdentityStatus.unverified.firestoreValue,
        'sellerStatus': SellerIdentityStatus.unverified.firestoreValue,
        'phoneVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
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
      final compressed = await ImageCompressionService.compressXFile(
        image,
        maxWidth: 1024,
        quality: 82,
      );
      final ref = _storage.ref().child(
        'profiles/${firebaseUser.uid}/profile.${compressed.extension}',
      );
      await ref.putData(
        compressed.bytes,
        SettableMetadata(
          contentType: compressed.contentType,
          customMetadata: {
            'originalSize': compressed.originalSize.toString(),
            'compressedSize': compressed.compressedSize.toString(),
            'width': compressed.width.toString(),
            'height': compressed.height.toString(),
          },
        ),
      );
      final url = await ref.getDownloadURL();

      await _users.doc(firebaseUser.uid).set({
        'profileImageUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _firestore.collection('publicProfiles').doc(firebaseUser.uid).set({
        'id': firebaseUser.uid,
        'name': currentUser.name,
        'role': currentUser.role.name,
        'profileImageUrl': url,
        'identityStatus': currentUser.identityStatus.firestoreValue,
        'sellerStatus': currentUser.identityStatus.firestoreValue,
        'phoneVerified': currentUser.phoneVerified,
        'createdAt': currentUser.createdAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      state = state.copyWith(
        isLoading: false,
        clearError: true,
        user: currentUser.copyWith(profileImageUrl: url),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Echec upload photo profil',
        name: 'AuthNotifier.updateProfilePhoto',
        error: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        user: currentUser,
        errorMessage: _storageMessage(error),
      );
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

  String _storageMessage(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unauthorized':
        case 'permission-denied':
          return "La photo n'a pas pu être envoyée. Vérifiez votre session puis réessayez.";
        case 'quota-exceeded':
          return 'Stockage temporairement indisponible. Réessayez plus tard.';
        case 'canceled':
          return "L'envoi de la photo a été annulé.";
      }
    }
    if (error is ImageCompressionException) return error.message;
    return 'Impossible de mettre à jour la photo de profil.';
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
