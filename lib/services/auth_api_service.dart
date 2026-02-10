import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class AuthResult {
  final String? token;
  final String? role;
  final int? userId;
  final Map<String, dynamic>? rawJson;

  const AuthResult({
    required this.token,
    required this.role,
    required this.userId,
    required this.rawJson,
  });
}

class AuthApiService {
  static Map<String, dynamic>? _tryDecodeJson(String body) {
    final b = body.trim();
    if (b.isEmpty) return null;
    try {
      final decoded = jsonDecode(b);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _pickString(dynamic v) {
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    return null;
  }

  static String? _extractToken(Map<String, dynamic>? json) {
    if (json == null) return null;

    // Common shapes: {token: "..."}, {access_token: "..."}, {data: {token: "..."}}
    final direct = _pickString(json['token']) ?? _pickString(json['access_token']);
    if (direct != null) return direct;

    final data = json['data'];
    if (data is Map<String, dynamic>) {
      return _pickString(data['token']) ?? _pickString(data['access_token']);
    }

    return null;
  }

  static String? _extractRole(Map<String, dynamic>? json) {
    if (json == null) return null;

    final direct = _pickString(json['role']);
    if (direct != null) return direct;

    final data = json['data'];
    if (data is Map<String, dynamic>) {
      return _pickString(data['role']);
    }

    final user = json['user'];
    if (user is Map<String, dynamic>) {
      return _pickString(user['role']);
    }

    return null;
  }

  static int? _extractUserId(Map<String, dynamic>? json) {
    if (json == null) return null;

    int? pick(dynamic v) {
      if (v is num) {
        final n = v.toInt();
        return n <= 0 ? null : n;
      }
      return int.tryParse(v?.toString() ?? '');
    }

    final direct = pick(json['user_id']) ?? pick(json['id']);
    if (direct != null) return direct;

    final data = json['data'];
    if (data is Map<String, dynamic>) {
      final fromData = pick(data['user_id']) ?? pick(data['id']);
      if (fromData != null) return fromData;

      final user = data['user'];
      if (user is Map<String, dynamic>) {
        return pick(user['id']) ?? pick(user['user_id']);
      }
    }

    final user = json['user'];
    if (user is Map<String, dynamic>) {
      return pick(user['id']) ?? pick(user['user_id']);
    }

    return null;
  }

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'MakerID': ApiConfig.makerId,
      };

  static Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse(ApiConfig.authLoginUrl),
      headers: _headers(),
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final json = _tryDecodeJson(res.body);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message =
          _pickString(json?['message']) ?? 'Login gagal (${res.statusCode})';
      throw Exception(message);
    }

    return AuthResult(
      token: _extractToken(json),
      role: _extractRole(json),
      userId: _extractUserId(json),
      rawJson: json,
    );
  }

  static Future<AuthResult> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
      'role': role,
    };

    if (phone.trim().isNotEmpty) {
      body['phone'] = phone.trim();
    }

    final res = await http.post(
      Uri.parse(ApiConfig.authRegisterUrl),
      headers: _headers(),
      body: jsonEncode(body),
    );

    final json = _tryDecodeJson(res.body);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = _pickString(json?['message']) ??
          'Register gagal (${res.statusCode})';
      throw Exception(message);
    }

    return AuthResult(
      token: _extractToken(json),
      role: _extractRole(json) ?? role,
      userId: _extractUserId(json),
      rawJson: json,
    );
  }
}
