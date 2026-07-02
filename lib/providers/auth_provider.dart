import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';

export '../models/user.dart';

class AuthState {
  const AuthState({
    required this.isAuthenticated,
    this.isLoading = false,
    this.selectedRole,
    this.user,
  });

  final bool isAuthenticated;
  final bool isLoading;
  final UserRole? selectedRole;
  final UserModel? user;

  UserModel? get currentUser => isAuthenticated ? user : null;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserRole? selectedRole,
    UserModel? user,
    bool clearSelectedRole = false,
    bool clearUser = false,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      selectedRole: clearSelectedRole
          ? null
          : selectedRole ?? this.selectedRole,
      user: clearUser ? null : user ?? this.user,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier({firebase_auth.FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? firebase_auth.FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance,
      super(const AuthState(isAuthenticated: false, isLoading: true)) {
    _authSubscription = _auth.authStateChanges().listen(
      _restoreSession,
      onError: (_) {
        state = state.copyWith(
          isAuthenticated: false,
          isLoading: false,
          clearUser: true,
          clearSelectedRole: true,
        );
      },
    );
  }

  final firebase_auth.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  StreamSubscription<firebase_auth.User?>? _authSubscription;

  void selectRole(UserRole role) {
    state = state.copyWith(selectedRole: role);
  }

  Future<void> _restoreSession(firebase_auth.User? firebaseUser) async {
    if (firebaseUser == null) {
      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
        clearUser: true,
        clearSelectedRole: true,
      );
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .get();
      final data = snapshot.data();

      if (data == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final user = UserModel.fromMap({...data, 'id': firebaseUser.uid});
      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        clearSelectedRole: true,
        user: user,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> login({
    UserRole? role,
    String? displayName,
    String? phoneNumber,
    String? email,
  }) async {
    state = state.copyWith(isLoading: true);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final effectiveRole = role ?? state.selectedRole ?? UserRole.buyer;
    final fallbackName = effectiveRole == UserRole.seller
        ? 'Vendeur Occasion'
        : 'Client Occasion';
    final name = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : fallbackName;
    final phone = phoneNumber?.trim().isNotEmpty == true
        ? phoneNumber!.trim()
        : '';

    UserModel user;
    try {
      final credential = await _auth.signInAnonymously();
      final uid = credential.user?.uid;
      if (uid == null) throw StateError('Firebase Auth UID indisponible');

      user = UserModel(
        id: uid,
        name: name,
        role: effectiveRole,
        phone: phone,
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection('users')
          .doc(uid)
          .set(user.toMap(), SetOptions(merge: true));
    } catch (_) {
      user = UserModel(
        id: '${effectiveRole.name}_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        role: effectiveRole,
        phone: phone,
        createdAt: DateTime.now(),
      );
    }

    state = state.copyWith(
      isAuthenticated: true,
      isLoading: false,
      clearSelectedRole: true,
      user: user,
    );
  }

  Future<void> logout() async {
    await _auth.signOut().catchError((_) {});
    state = state.copyWith(
      isAuthenticated: false,
      isLoading: false,
      clearSelectedRole: true,
      clearUser: true,
    );
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
