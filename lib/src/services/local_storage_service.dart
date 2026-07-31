import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  LocalStorageService._();

  static final LocalStorageService instance = LocalStorageService._();
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Map<String, String>? readCredentials() {
    final email = _prefs?.getString('saved_email');
    final passwordHash = _prefs?.getString('saved_password_hash');
    if (email == null || passwordHash == null) return null;
    return {'email': email, 'password': passwordHash};
  }

  Future<void> saveCredentials({
    required String email,
    required String passwordHash,
  }) async {
    await _prefs?.setString('saved_email', email);
    await _prefs?.setString('saved_password_hash', passwordHash);
  }

  Future<void> clearCredentials() async {
    await _prefs?.remove('saved_email');
    await _prefs?.remove('saved_password_hash');
  }
}
