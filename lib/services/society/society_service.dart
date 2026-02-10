import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../auth_service.dart';

class SocietyService {
  static String _authValue(String token) {
    final t = token.trim();
    if (t.toLowerCase().startsWith('bearer ')) return t;
    return 'Bearer $t';
  }

  static String _extractErrorMessage(String body) {
    final raw = body.trim();
    if (raw.isEmpty) return 'Tidak ada detail dari server.';

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final msg = (decoded['message'] ?? decoded['msg'] ?? decoded['error']);
        if (msg != null && msg.toString().trim().isNotEmpty) {
          return msg.toString();
        }

        final errors = decoded['errors'] ?? decoded['data'];
        if (errors is Map) {
          final parts = <String>[];
          for (final entry in errors.entries) {
            final k = entry.key.toString();
            final v = entry.value;
            if (v is List) {
              final joined = v.map((e) => e.toString()).join(', ');
              if (joined.trim().isNotEmpty) parts.add('$k: $joined');
            } else if (v != null && v.toString().trim().isNotEmpty) {
              parts.add('$k: ${v.toString()}');
            }
          }
          if (parts.isNotEmpty) return parts.join('\n');
        }
      }
    } catch (_) {
      // Not JSON; fall back to raw.
    }

    return raw;
  }

  static Future<void> updateProfile({
    required String name,
    required String email,
    String? phone,
  }) async {
    final token = await AuthService.getToken();

    if (token == null) {
      throw Exception('Token tidak ditemukan. Silakan login ulang.');
    }

    final body = <String, dynamic>{
      'name': name,
      'email': email,
    };

    if (phone != null && phone.trim().isNotEmpty) {
      body['phone'] = phone;
    }

    final uri = Uri.parse(ApiConfig.societyUpdateProfileUrl);
    final headers = {
      'Content-Type': 'application/json',
      'MakerID': ApiConfig.makerId,
      'Authorization': _authValue(token),
    };

    http.Response response = await http.put(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    // Some backends use POST for updates.
    if (response.statusCode == 405) {
      response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _extractErrorMessage(response.body);
      throw Exception('Gagal update profile (${response.statusCode}): $detail');
    }
  }
}
