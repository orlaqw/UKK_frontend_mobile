import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

class SocietyImageKosService {
  static String _authValue(String token) {
    final t = token.trim();
    if (t.toLowerCase().startsWith('bearer ')) return t;
    return 'Bearer $t';
  }

  static Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'MakerID': ApiConfig.makerId,
      'Authorization': _authValue(token),
    };
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'] ?? decoded['images'] ?? decoded['result'];
      if (data is List) return data;
      if (data is Map) {
        final inner = data['data'] ?? data['items'] ?? data['images'];
        if (inner is List) return inner;
      }
    }
    return const [];
  }

  static List<dynamic> _extractImagesFromDetail(dynamic decoded) {
    if (decoded is! Map) return const [];

    dynamic data = decoded['data'] ?? decoded['result'] ?? decoded;
    if (data is List && data.isNotEmpty) data = data.first;
    if (data is! Map) return const [];

    for (final key in const [
      'kos_image',
      'kos_images',
      'image_kos',
      'images_kos',
      'images',
      'gallery',
      'photos',
    ]) {
      final v = data[key];
      if (v is List) return v;
      if (v is Map) return [v];
    }
    return const [];
  }

  static Future<http.Response> _safeGet(Uri url, {required String token}) {
    return http
        .get(url, headers: _headers(token))
        .timeout(const Duration(seconds: 20));
  }

  static Exception _httpError(
    String action,
    List<Uri> urls,
    http.Response? res,
    Object? lastError,
  ) {
    final code = res?.statusCode;
    final body = (res?.body ?? '').trim();
    final lower = body.toLowerCase();
    final looksHtml = body.trimLeft().startsWith('<!doctype html') ||
        body.trimLeft().startsWith('<html');
    final accessDenied =
        code == 401 || code == 403 || lower.contains('tidak memiliki akses');
    final notFound = code == 404 || lower.contains('not found');
    final trimmed = looksHtml
        ? 'Respon HTML (mungkin endpoint salah / tidak tersedia)'
        : (body.length > 200 ? '${body.substring(0, 200)}…' : body);

    if (accessDenied) {
      return Exception(
        'Akses gambar ditolak untuk akun Society. '
        'Di dokumentasi UKK, endpoint gambar berada di group Owner/Admin, '
        'jadi Society tidak bisa mengambil daftar gambar (401).',
      );
    }

    if (notFound) {
      return Exception(
        'Endpoint gambar tidak ditemukan (404). '
        'Coba cek dokumentasi backend UKK untuk endpoint show_image yang benar.',
      );
    }

    return Exception(
      '$action gagal.\n'
      'Tried: ${urls.map((e) => e.toString()).join(' | ')}\n'
      '(${code ?? '-'}) ${trimmed.isEmpty ? '' : trimmed}\n'
      '${lastError == null ? '' : lastError.toString()}',
    );
  }

  static Future<List<dynamic>> getImages({
    required String token,
    required int kosId,
  }) async {
    // Best effort: society/detail_kos often already includes kos_image list.
    try {
      final detailRes = await _safeGet(
        Uri.parse(ApiConfig.societyDetailKosUrl(kosId)),
        token: token,
      );
      // If detail_kos is available for Society, prefer it and don't probe other endpoints.
      // For many deployments, image endpoints are Owner/Admin-only and will 401 for Society.
      if (detailRes.statusCode == 200) {
        if (detailRes.body.trim().isEmpty) return const [];
        final decoded = jsonDecode(detailRes.body);
        return _extractImagesFromDetail(decoded);
      }
    } catch (_) {
      // ignore and continue to endpoint probing
    }

    final urls = <Uri>[
      // Prefer non-role (public) endpoints if the backend provides them.
      Uri.parse('${ApiConfig.authBaseUrl}/show_image/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/show_images/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/show_image_kos/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/show_images_kos/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/images/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/image/$kosId'),

      // Some deployments (older commits) used society-prefixed endpoints.
      Uri.parse('${ApiConfig.authBaseUrl}/society/show_image/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/society/show_images/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/society/show_image_kos/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/society/images/$kosId'),
      Uri.parse('${ApiConfig.authBaseUrl}/society/image/$kosId'),

      // Last resort: admin endpoint (will likely 401 for Society).
      Uri.parse(ApiConfig.ownerShowImagesUrl(kosId)),
    ];

    http.Response? lastRes;
    Object? lastError;

    for (final url in urls) {
      try {
        final res = await _safeGet(url, token: token);
        lastRes = res;
        if (res.statusCode == 200) {
          if (res.body.trim().isEmpty) return const [];
          final decoded = jsonDecode(res.body);
          return _extractList(decoded);
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw _httpError('Gagal memuat gambar', urls, lastRes, lastError);
  }

  static Future<String?> getFirstImageUrl({
    required String token,
    required int kosId,
  }) async {
    try {
      final images = await getImages(token: token, kosId: kosId);
      for (final it in images) {
        if (it is! Map) continue;
        final raw = (it['image_url'] ??
                it['url'] ??
                it['image'] ??
                it['file'] ??
                it['path'] ??
                '')
            .toString()
            .trim();
        if (raw.isNotEmpty) return raw;
      }
    } catch (_) {
      // ignore, fall through to detail parsing
    }

    // UKK docs show society has detail_kos endpoint; images are commonly embedded there.
    // Fallback to legacy endpoint if needed.
    final ukkUrl = Uri.parse(ApiConfig.societyDetailKosUrl(kosId));
    final legacyUrl =
        Uri.parse('${ApiConfig.baseUrl}/society/kos/$kosId/images');

    Future<String?> parseFromDetail(String body) async {
      final decoded = jsonDecode(body);
      Map? root;
      if (decoded is Map) {
        root = decoded;
      }

      Map? data;
      if (root != null) {
        final d = root['data'];
        if (d is Map) data = d;
        if (d is List && d.isNotEmpty && d.first is Map) {
          data = d.first as Map;
        }
      }

      final source = data ?? root;
      if (source == null) return null;

      // Look for common list keys
      for (final key in const [
        'kos_image',
        'kos_images',
        'images',
        'image',
        'image_kos',
        'images_kos',
        'gallery',
        'photos'
      ]) {
        final v = source[key];
        if (v is List) {
          for (final it in v) {
            if (it is! Map) continue;
            final raw = (it['image_url'] ??
                    it['url'] ??
                    it['image'] ??
                    it['file'] ??
                    it['path'] ??
                    '')
                .toString()
                .trim();
            if (raw.isNotEmpty) return raw;
          }
        }
      }

      // Or a direct string
      for (final key in const [
        'image_url',
        'cover_url',
        'thumbnail_url',
        'image',
        'cover',
        'thumbnail',
        'file',
        'path'
      ]) {
        final raw = (source[key] ?? '').toString().trim();
        if (raw.isNotEmpty) return raw;
      }
      return null;
    }

    try {
      final res = await _safeGet(ukkUrl, token: token);
      if (res.statusCode == 200) {
        return await parseFromDetail(res.body);
      }
    } catch (_) {
      // ignore
    }

    try {
      final res = await _safeGet(legacyUrl, token: token);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      List<dynamic> list = const [];
      if (decoded is Map) {
        final data = decoded['data'];
        if (data is List) list = data;
      } else if (decoded is List) {
        list = decoded;
      }

      for (final it in list) {
        if (it is! Map) continue;
        final raw = (it['image_url'] ?? it['url'] ?? it['image'] ?? '')
            .toString()
            .trim();
        if (raw.isNotEmpty) return raw;
      }
    } catch (_) {
      // ignore
    }

    return null;
  }
}
