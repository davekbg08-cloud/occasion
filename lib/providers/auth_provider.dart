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
  AuthNotifier() : super(const AuthState(isAuthenticated: false));

  void selectRole(UserRole role) {
    state = state.copyWith(selectedRole: role);
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
      final credential = await firebase_auth.FirebaseAuth.instance
          .signInAnonymously();
      final uid = credential.user?.uid;
      if (uid == null) throw StateError('Firebase Auth UID indisponible');

      user = UserModel(
        id: uid,
        name: name,
        role: effectiveRole,
        phone: phone,
        createdAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
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

  void logout() {
    firebase_auth.FirebaseAuth.instance.signOut().catchError((_) {});
    state = state.copyWith(
      isAuthenticated: false,
      isLoading: false,
      clearSelectedRole: true,
      clearUser: true,
    );
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
