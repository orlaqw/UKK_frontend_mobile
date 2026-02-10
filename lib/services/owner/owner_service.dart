import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../auth_service.dart';

class OwnerService {
  static String _authValue(String token) {
    final t = token.trim();
    if (t.toLowerCase().startsWith('bearer ')) return t;
    return 'Bearer $t';
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

    String extractErrorMessage(String raw) {
      final body = raw.trim();
      if (body.isEmpty) return 'Tidak ada detail dari server.';

      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final msg = decoded['message'] ?? decoded['msg'] ?? decoded['error'];
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
        // not JSON
      }

      final looksHtml = body.toLowerCase().startsWith('<!doctype') ||
          body.toLowerCase().startsWith('<html');
      if (looksHtml) return 'Respon HTML (kemungkinan endpoint salah)';
      return body;
    }

    final headers = {
      'Content-Type': 'application/json',
      'MakerID': ApiConfig.makerId,
      'Authorization': _authValue(token),
    };

    final candidates = <Uri>[
      // UKK docs: admin update profile
      Uri.parse('${ApiConfig.authBaseUrl}/admin/update_profile'),
      // Some deployments use owner prefix
      Uri.parse('${ApiConfig.authBaseUrl}/owner/update_profile'),
      // Legacy local backend
      Uri.parse('${ApiConfig.baseUrl}/owner/update_profile'),
    ];

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      http.Response res =
          await http.put(url, headers: headers, body: jsonEncode(body));
      if (res.statusCode == 405) {
        res = await http.post(url, headers: headers, body: jsonEncode(body));
      }

      lastRes = res;
      if (res.statusCode >= 200 && res.statusCode < 300) return;

      // Try next candidate on not found / method not allowed
      if (res.statusCode == 404 || res.statusCode == 405) continue;
      // For auth errors, no need to keep trying.
      if (res.statusCode == 401 || res.statusCode == 403) {
        final detail = extractErrorMessage(res.body);
        throw Exception('Gagal update profile (${res.statusCode}): $detail');
      }
    }

    final res = lastRes;
    final url = lastUrl;
    if (res == null || url == null) {
      throw Exception('Gagal update profile: tidak ada response dari server');
    }
    final detail = extractErrorMessage(res.body);
    throw Exception('Gagal update profile (${res.statusCode})\n$url\n$detail');
  }
}
