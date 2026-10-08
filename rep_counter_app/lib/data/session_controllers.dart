// Account and preferences. [AuthController] is a local stand-in: it accepts
// any well-formed credentials and remembers the profile on the phone. The
// backend version swaps the bodies of signIn / signUp / signInWithGoogle for
// API calls and keeps the token instead of the profile.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthController extends ChangeNotifier {
  static const _kUser = 'auth.user';

  SharedPreferences? _prefs;
  UserProfile? _user;

  UserProfile? get user => _user;
  bool get signedIn => _user != null;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
    }
    final raw = _prefs?.getString(_kUser);
    if (raw != null) {
      _user = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    notifyListeners();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _validate(String email, String password) {
    if (!_emailPattern.hasMatch(email.trim())) {
      throw const AuthException('Escribe un correo válido.');
    }
    if (password.length < 8) {
      throw const AuthException(
        'La contraseña debe tener al menos 8 caracteres.',
      );
    }
  }

  Future<void> signIn(String email, String password) async {
    _validate(email, password);
    final trimmed = email.trim();
    final local = trimmed.split('@').first;
    final name = local.isEmpty
        ? trimmed
        : '${local[0].toUpperCase()}${local.substring(1)}';
    await _setUser(UserProfile(name: name, email: trimmed));
  }

  Future<void> signUp(String name, String email, String password) async {
    if (name.trim().isEmpty) {
      throw const AuthException('Escribe tu nombre.');
    }
    _validate(email, password);
    await _setUser(UserProfile(name: name.trim(), email: email.trim()));
  }

  Future<void> signInWithGoogle() async {
    // Needs the google_sign_in package and a backend that verifies the
    // Google ID token. Until then it is not offered as working.
    throw const AuthException(
      'El acceso con Google estará disponible cuando exista el servidor.',
    );
  }

  Future<void> signOut() async {
    _user = null;
    await _prefs?.remove(_kUser);
    notifyListeners();
  }

  Future<void> _setUser(UserProfile user) async {
    _user = user;
    await _prefs?.setString(_kUser, jsonEncode(user.toJson()));
    notifyListeners();
  }
}

class SettingsController extends ChangeNotifier {
  static const _kDark = 'settings.dark';

  SharedPreferences? _prefs;
  bool _dark = false;

  bool get darkMode => _dark;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
    }
    _dark = _prefs?.getBool(_kDark) ?? false;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _dark = value;
    notifyListeners();
    await _prefs?.setBool(_kDark, value);
  }
}
