// Account and preferences.
//
// [AuthController] signs in against the API. Tokens live in secure storage
// (see api_client.dart); the profile is also cached in SharedPreferences so
// the app opens signed in without network.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'models.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthController extends ChangeNotifier {
  AuthController({required this.api}) {
    api.onSessionExpired = _expired;
  }

  static const _kUser = 'auth.user';

  final ApiClient api;
  SharedPreferences? _prefs;
  UserProfile? _user;

  /// True when the server ended the session (refresh token rejected), so
  /// the login screen can say why.
  bool sessionExpired = false;

  UserProfile? get user => _user;
  bool get signedIn => _user != null;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
    }
    final tokens = await api.tokens.read();
    final raw = _prefs?.getString(_kUser);
    if (tokens != null && raw != null) {
      try {
        _user = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _user = null; // Profile from an older version without id.
      }
    }
    if (_user == null) await _forget();
    notifyListeners();
  }

  /// Picks up a name change made on another phone. Silent when offline.
  Future<void> refreshProfile() async {
    if (!signedIn) return;
    try {
      final response = await api.get('/me');
      await _setUser(UserProfile.fromJson(response.body as Map<String, dynamic>));
    } on NetworkException {
      // Keep the cached profile.
    } on ApiException {
      // A rejected session already went through _expired.
    }
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _validate(String email, String password, {bool newPassword = false}) {
    if (!_emailPattern.hasMatch(email.trim())) {
      throw const AuthException('Escribe un correo válido.');
    }
    if (password.isEmpty) {
      throw const AuthException('Escribe tu contraseña.');
    }
    if (newPassword && password.length < 8) {
      throw const AuthException(
        'La contraseña debe tener al menos 8 caracteres.',
      );
    }
  }

  Future<void> signIn(String email, String password) async {
    _validate(email, password);
    await _authenticate('/auth/login', {
      'email': email.trim(),
      'password': password,
    });
  }

  Future<void> signUp(String name, String email, String password) async {
    if (name.trim().isEmpty) {
      throw const AuthException('Escribe tu nombre.');
    }
    _validate(email, password, newPassword: true);
    await _authenticate('/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
    });
  }

  Future<void> signInWithGoogle() async {
    // Needs the google_sign_in package on the phone and GOOGLE_CLIENT_IDS on
    // the server; the API already accepts the ID token at /auth/google.
    throw const AuthException('El acceso con Google todavía no está disponible.');
  }

  Future<void> _authenticate(String path, Map<String, dynamic> body) async {
    try {
      final response = await api.post(path, body: body, auth: false);
      final json = response.body as Map<String, dynamic>;
      await api.storeAuthResponse(json);
      sessionExpired = false;
      await _setUser(UserProfile.fromJson(json['user'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      throw AuthException(e.message);
    } on NetworkException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Ends the session here and on the server. Works offline too: the server
  /// token then simply expires on its own.
  Future<void> signOut() async {
    final tokens = await api.tokens.read();
    if (tokens != null) {
      try {
        await api.post('/auth/logout',
            body: {'refreshToken': tokens.refresh}, auth: false);
      } catch (_) {}
    }
    await _forget();
    notifyListeners();
  }

  void _expired() {
    if (_user == null) return;
    sessionExpired = true;
    _forget().then((_) => notifyListeners());
  }

  Future<void> _forget() async {
    _user = null;
    await api.tokens.clear();
    await _prefs?.remove(_kUser);
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
