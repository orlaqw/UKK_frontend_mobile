import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';

class OwnerFacilityService {
  static const Duration _timeout = Duration(seconds: 20);
  static const bool _enableLegacyFallback = bool.fromEnvironment(
    'ENABLE_LEGACY_FALLBACK',
    defaultValue: false,
  );

  static Uri _ukk(String path) {
    final base = Uri.parse(ApiConfig.authBaseUrl);
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    final p = path.startsWith('/') ? path.substring(1) : path;
    return base.replace(path: '$basePath$p');
  }

  static Uri _ukkQuery(String path, Map<String, String> queryParameters) {
    final u = _ukk(path);
    return u.replace(queryParameters: queryParameters);
  }

  static List<Uri> _ukkCandidatesForKos(int kosId) {
    // UKK routes may differ between projects; try common variants.
    return <Uri>[
      _ukk('admin/show_facilities/$kosId'),
      _ukk('admin/show_facility/$kosId'),

      // Configured endpoint (may be non-admin depending on project).
      Uri.parse(ApiConfig.ownerShowFacilitiesUrl(kosId)),

      _ukk('show_facilities/$kosId'),
      _ukk('show_facility/$kosId'),

      // Some backends use query params instead of path params.
      _ukkQuery('admin/show_facilities', {'kos_id': '$kosId'}),
      _ukkQuery('admin/show_facilities', {'id': '$kosId'}),
      _ukkQuery('show_facilities', {'kos_id': '$kosId'}),
      _ukkQuery('show_facilities', {'id': '$kosId'}),
    ];
  }

  static List<Uri> _ukkCandidatesStore(int kosId) {
    return <Uri>[
      Uri.parse(ApiConfig.ownerStoreFacilityUrl(kosId)),
      _ukk('admin/store_facility/$kosId'),
      _ukk('store_facility/$kosId'),

      // Some backends accept kos_id in JSON body.
      _ukk('admin/store_facility'),
      _ukk('store_facility'),
    ];
  }

  static List<Uri> _ukkCandidatesUpdate(int facilityId) {
    return <Uri>[
      Uri.parse(ApiConfig.ownerUpdateFacilityUrl(facilityId)),
      _ukk('admin/update_facility/$facilityId'),
      _ukk('update_facility/$facilityId'),

      // Some backends accept id in query/body.
      _ukkQuery('admin/update_facility', {'id': '$facilityId'}),
      _ukkQuery('update_facility', {'id': '$facilityId'}),
    ];
  }

  static List<Uri> _ukkCandidatesDetail(int facilityId) {
    return <Uri>[
      Uri.parse(ApiConfig.ownerDetailFacilityUrl(facilityId)),
      _ukk('admin/detail_facility/$facilityId'),
      _ukk('detail_facility/$facilityId'),

      _ukkQuery('admin/detail_facility', {'id': '$facilityId'}),
      _ukkQuery('detail_facility', {'id': '$facilityId'}),
    ];
  }

  static List<Uri> _ukkCandidatesDelete(int facilityId) {
    return <Uri>[
      Uri.parse(ApiConfig.ownerDeleteFacilityUrl(facilityId)),
      _ukk('admin/delete_facility/$facilityId'),
      _ukk('delete_facility/$facilityId'),

      _ukkQuery('admin/delete_facility', {'id': '$facilityId'}),
      _ukkQuery('delete_facility', {'id': '$facilityId'}),
    ];
  }

  static String _previewBody(http.Response res) {
    final body = res.body.trimLeft();
    final looksLikeHtml =
        body.toLowerCase().startsWith('<!doctype') ||
        body.toLowerCase().startsWith('<html');
    if (looksLikeHtml) return 'Response HTML';
    if (body.isEmpty) return '(empty body)';
    return body.length > 140 ? body.substring(0, 140) : body;
  }

  static bool _isUkkEndpoint(Uri url) {
    final auth = Uri.parse(ApiConfig.authBaseUrl);
    if (auth.host.isEmpty) return false;
    if (url.host != auth.host) return false;
    // authBaseUrl includes '/kos/api' in its path; ensure the request is under it.
    final authPath = auth.path.endsWith('/') ? auth.path : '${auth.path}/';
    final urlPath = url.path.endsWith('/') ? url.path : '${url.path}/';
    return urlPath.startsWith(authPath);
  }

  static String _authValue(String token) {
    final t = token.trim();
    if (t.toLowerCase().startsWith('bearer ')) return t;
    return 'Bearer $t';
  }

  static Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'MakerID': ApiConfig.makerId,
      'Authorization': _authValue(token),
    };
  }

  static Exception _error(String action, Uri url, http.Response res) {
    final body = res.body.trimLeft();
    final looksLikeHtml =
        body.toLowerCase().startsWith('<!doctype') ||
        body.toLowerCase().startsWith('<html');

    // Jangan dump HTML panjang ke UI.
    final preview = looksLikeHtml
        ? 'Response HTML (kemungkinan 404/route tidak ada)'
        : (body.length > 200 ? body.substring(0, 200) : body);

    return Exception('$action gagal (${res.statusCode})\n$url\n$preview');
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data =
          decoded['data'] ?? decoded['facilities'] ?? decoded['result'];
      if (data is List) return data;
      if (data is Map) {
        final nested = data['data'];
        if (nested is List) return nested;
      }
    }
    return const [];
  }

  static dynamic _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeNoFacilities(http.Response res) {
    final body = res.body.trim();
    if (body.isEmpty) return true;
    final lower = body.toLowerCase();
    if (lower.contains('no facilities') ||
        lower.contains('tidak ada fasilitas')) {
      return true;
    }

    final decoded = _tryDecodeJson(body);
    if (decoded is Map) {
      final status = (decoded['status'] ?? '').toString().toLowerCase();
      final msg = (decoded['message'] ?? decoded['msg'] ?? '')
          .toString()
          .toLowerCase();
      final data = decoded['data'];
      if ((status == 'failed' || status == 'fail') &&
          (data is List) &&
          data.isEmpty) {
        return true;
      }
      if (msg.contains('no facilities') ||
          msg.contains('tidak ada fasilitas')) {
        return true;
      }
    }
    return false;
  }

  static Future<http.Response> _safeGet(Uri url, {required String token}) {
    return http.get(url, headers: _headers(token)).timeout(_timeout);
  }

  static Future<http.Response> _safePost(
    Uri url, {
    required String token,
    Object? body,
  }) {
    return http
        .post(url, headers: _headers(token), body: body)
        .timeout(_timeout);
  }

  static Future<http.Response> _safePut(
    Uri url, {
    required String token,
    Object? body,
  }) {
    return http
        .put(url, headers: _headers(token), body: body)
        .timeout(_timeout);
  }

  static Future<http.Response> _safeDelete(Uri url, {required String token}) {
    return http.delete(url, headers: _headers(token)).timeout(_timeout);
  }

  static Future<List<dynamic>> getFacilities({
    required String token,
    required int kosId,
  }) async {
    final candidates = <Uri>[
      ..._ukkCandidatesForKos(kosId),
      if (_enableLegacyFallback)
        Uri.parse('${ApiConfig.showFacilities}/$kosId'),
    ];

    http.Response? lastRes;
    Uri? lastUrl;
    final attempts = <String>[];

    for (final url in candidates) {
      lastUrl = url;
      try {
        final res = await _safeGet(url, token: token);
        lastRes = res;
        attempts.add('${res.statusCode} $url  ${_previewBody(res)}');
        if (res.statusCode == 200) {
          if (res.body.trim().isEmpty) return const [];
          final decodedAny = jsonDecode(res.body);
          return _extractList(decodedAny);
        }
        if (res.statusCode == 404 && _looksLikeNoFacilities(res)) {
          return const [];
        }
        if (res.statusCode == 404) {
          // Route not found for this variant; try next.
          continue;
        }
        if (res.statusCode == 401 || res.statusCode == 403) {
          // Don't try legacy if UKK endpoint explicitly denies access.
          // Legacy fallback often points to localhost/10.0.2.2 and will cause long waiting.
          if (_isUkkEndpoint(url)) {
            throw Exception(
              'Akses fasilitas ditolak (${res.statusCode}).\n'
              'Pastikan login sebagai Owner/Admin dan token valid.\n'
              'Dicoba:\n${attempts.join('\n')}',
            );
          }
          continue;
        }
      } catch (e) {
        // Flutter Web biasanya melempar "XMLHttpRequest error" kalau kena CORS,
        // DNS gagal, atau request diblokir browser. Sertakan URL biar jelas.
        if (url != candidates.last) continue;
        throw Exception(
          'Memuat fasilitas gagal\n'
          'kosId=$kosId\n'
          'Dicoba:\n${attempts.join('\n')}\n'
          'Error terakhir: $url\n'
          '$e',
        );
      }
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.ownerShowFacilitiesUrl(kosId));
    if (res == null) {
      throw Exception(
        'Memuat fasilitas gagal\n'
        'kosId=$kosId\n'
        'Dicoba:\n${attempts.join('\n')}',
      );
    }

    throw Exception(
      'Memuat fasilitas gagal (${res.statusCode})\n'
      'kosId=$kosId\n'
      'Dicoba:\n${attempts.join('\n')}\n'
      'Terakhir: $url\n'
      '${_previewBody(res)}',
    );
  }

  static Future<bool> addFacility({
    required String token,
    required int kosId,
    required String facilityName,
  }) async {
    final candidates = <Uri>[
      ..._ukkCandidatesStore(kosId),
      if (_enableLegacyFallback) Uri.parse('${ApiConfig.addFacility}/$kosId'),
    ];

    final bodyPath = jsonEncode({'facility_name': facilityName});
    final bodyWithKosId = jsonEncode({
      'kos_id': kosId,
      'facility_name': facilityName,
    });

    for (final url in candidates) {
      try {
        final useKosIdInBody =
            url.path.endsWith('/store_facility') ||
            url.path.endsWith('/admin/store_facility');
        final res = await _safePost(
          url,
          token: token,
          body: useKosIdInBody ? bodyWithKosId : bodyPath,
        );
        if (res.statusCode == 200 || res.statusCode == 201) return true;
        if (res.statusCode == 404) continue;
        if (res.statusCode == 401 || res.statusCode == 403) continue;
      } catch (_) {
        if (url != candidates.last) continue;
        rethrow;
      }
    }
    return false;
  }

  static Future<bool> updateFacility({
    required String token,
    required int facilityId,
    required String facilityName,
  }) async {
    final candidates = <Uri>[
      ..._ukkCandidatesUpdate(facilityId),
      if (_enableLegacyFallback)
        Uri.parse('${ApiConfig.updateFacility}/$facilityId'),
    ];

    final body = jsonEncode({'facility_name': facilityName});

    for (final url in candidates) {
      try {
        final res = await _safePut(url, token: token, body: body);
        if (res.statusCode == 200 || res.statusCode == 204) return true;
        if (res.statusCode == 404) continue;
        if (res.statusCode == 401 || res.statusCode == 403) continue;
      } catch (_) {
        if (url != candidates.last) continue;
        rethrow;
      }
    }
    return false;
  }

  static Future<Map<String, dynamic>> detailFacility({
    required String token,
    required int facilityId,
  }) async {
    final candidates = <Uri>[
      ..._ukkCandidatesDetail(facilityId),
      if (_enableLegacyFallback)
        Uri.parse('${ApiConfig.detailFacility}/$facilityId'),
    ];

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      try {
        final res = await _safeGet(url, token: token);
        lastRes = res;
        if (res.statusCode == 200) {
          if (res.body.trim().isEmpty) return <String, dynamic>{};
          final decodedAny = jsonDecode(res.body);
          if (decodedAny is Map) {
            final data = decodedAny['data'];
            if (data is Map) return Map<String, dynamic>.from(data);
            return Map<String, dynamic>.from(decodedAny);
          }
          return <String, dynamic>{'raw': res.body};
        }
        if (res.statusCode == 404) continue;
        if (res.statusCode == 401 || res.statusCode == 403) continue;
      } catch (_) {
        if (url != candidates.last) continue;
        rethrow;
      }
    }

    final res = lastRes;
    final url =
        lastUrl ?? Uri.parse(ApiConfig.ownerDetailFacilityUrl(facilityId));
    if (res == null) throw Exception('Detail fasilitas gagal\n$url');
    throw _error('Detail fasilitas', url, res);
  }

  static Future<bool> deleteFacility({
    required String token,
    required int facilityId,
  }) async {
    final candidates = <Uri>[
      ..._ukkCandidatesDelete(facilityId),
      if (_enableLegacyFallback)
        Uri.parse('${ApiConfig.deleteFacility}/$facilityId'),
    ];

    for (final url in candidates) {
      try {
        final res = await _safeDelete(url, token: token);
        if (res.statusCode == 200 || res.statusCode == 204) return true;
        if (res.statusCode == 404) continue;
        if (res.statusCode == 401 || res.statusCode == 403) continue;
      } catch (_) {
        if (url != candidates.last) continue;
        rethrow;
      }
    }
    return false;
  }
}
