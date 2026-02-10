import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _kToken = 'auth_token';
  static const _kRole = 'auth_role';
  static const _kUserId = 'auth_user_id';
  static const _kName = 'user_name';
  static const _kEmail = 'user_email';
  static const _kPhone = 'user_phone';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kToken);
    return (t == null || t.trim().isEmpty) ? null : t;
  }

  static Future<void> saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRole, role);
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getString(_kRole);
    return (r == null || r.trim().isEmpty) ? null : r;
  }

  static Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUserId, userId);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_kUserId);
    return (v == null || v <= 0) ? null : v;
  }

  static Future<void> saveUserName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, value);
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kName);
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  static Future<void> saveUserEmail(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, value);
  }

  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kEmail);
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  static Future<void> saveUserPhone(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPhone, value);
  }

  static Future<String?> getUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kPhone);
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kRole);
    await prefs.remove(_kUserId);
    await prefs.remove(_kName);
    await prefs.remove(_kEmail);
    await prefs.remove(_kPhone);
  }
}
