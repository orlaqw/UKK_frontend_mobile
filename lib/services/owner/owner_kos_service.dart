import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import 'owner_facility_service.dart';
import 'owner_image_kos_service.dart';
import 'owner_review_service.dart';

class OwnerKosService {
  static const Duration _timeout = Duration(seconds: 20);
  static const bool _enableLegacyFallback = bool.fromEnvironment(
    'ENABLE_LEGACY_FALLBACK',
    defaultValue: false,
  );

  static bool _isUkkEndpoint(Uri url) {
    final auth = Uri.parse(ApiConfig.authBaseUrl);
    if (auth.host.isEmpty) return false;
    if (url.host != auth.host) return false;
    final authPath = auth.path.endsWith('/') ? auth.path : '${auth.path}/';
    final urlPath = url.path.endsWith('/') ? url.path : '${url.path}/';
    return urlPath.startsWith(authPath);
  }

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

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) return data;

      // beberapa API mengembalikan {data: {data: [...]}}
      if (data is Map) {
        final nested = data['data'];
        if (nested is List) return nested;
        final kos = data['kos'];
        if (kos is List) return kos;
      }

      final kos = decoded['kos'];
      if (kos is List) return kos;

      final items = decoded['items'];
      if (items is List) return items;
    }
    return const [];
  }

  static Exception _error(String action, Uri url, http.Response res) {
    final body = res.body.trimLeft();
    final looksLikeHtml =
        body.toLowerCase().startsWith('<!doctype') ||
        body.toLowerCase().startsWith('<html');
    final preview = looksLikeHtml
        ? 'Response HTML (kemungkinan 404/route tidak ada)'
        : (body.length > 250 ? body.substring(0, 250) : body);
    return Exception('$action gagal (${res.statusCode})\n$url\n$preview');
  }

  static dynamic _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeHtml(String body) {
    final b = body.trimLeft().toLowerCase();
    return b.startsWith('<!doctype') || b.startsWith('<html');
  }

  static String _previewBody(http.Response res) {
    final body = res.body.trimLeft();
    if (body.isEmpty) return '(empty body)';
    if (_looksLikeHtml(body)) return 'Response HTML';
    final trimmed = body.trim();
    return trimmed.length > 220 ? trimmed.substring(0, 220) : trimmed;
  }

  static bool _isDefinitiveFailure(http.Response res) {
    // If backend returns JSON {status:false} / {success:false}, this is a real response from
    // the correct route. Don't continue trying other endpoints (would hide the reason).
    final body = res.body.trim();
    if (body.isEmpty || _looksLikeHtml(body)) return false;
    final decoded = _tryDecodeJson(body);
    if (decoded is! Map) return false;

    final status = decoded['status'];
    if (status is bool && status == false) return true;
    final success = decoded['success'] ?? decoded['isSuccess'];
    if (success is bool && success == false) return true;
    if (decoded.containsKey('error') || decoded.containsKey('errors')) return true;
    return false;
  }

  static bool _isLogicalSuccess(http.Response res) {
    if (res.statusCode == 204) return true;

    final trimmed = res.body.trim();
    if (trimmed.isEmpty) {
      return res.statusCode == 200 || res.statusCode == 201;
    }
    if (_looksLikeHtml(trimmed)) return false;

    final decoded = _tryDecodeJson(trimmed);
    if (decoded is Map) {
      final status = decoded['status'];
      if (status is bool) return status;

      final success = decoded['success'] ?? decoded['isSuccess'];
      if (success is bool) return success;

      final ok = decoded['ok'];
      if (ok is bool) return ok;

      // Jika tidak ada indikator, anggap sukses untuk HTTP 200/201.
      return res.statusCode == 200 || res.statusCode == 201;
    }

    // List/primitive: anggap sukses untuk HTTP 200/201.
    return res.statusCode == 200 || res.statusCode == 201;
  }

  static Future<List<dynamic>> getKos({
    required String token,
    String? search,
  }) async {
    final q = (search ?? '').trim();
    final legacyUrl = () {
      if (q.isEmpty) return Uri.parse('${ApiConfig.baseUrl}/owner/kos');
      final encoded = Uri.encodeQueryComponent(q);
      return Uri.parse('${ApiConfig.baseUrl}/owner/kos?search=$encoded');
    };

    final candidates = <Uri>{
      Uri.parse(ApiConfig.ownerShowKosUrl(search: q.isEmpty ? null : q)),
      _ukkQuery('admin/show_kos', q.isEmpty ? const {} : {'search': q}),
      _ukkQuery('show_kos', q.isEmpty ? const {} : {'search': q}),
      if (_enableLegacyFallback) legacyUrl(),
    }.toList(growable: false);

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      final res = await http
          .get(url, headers: _headers(token))
          .timeout(_timeout);
      lastRes = res;

      if (res.statusCode == 200) {
        final decodedAny = _tryDecodeJson(res.body);
        if (decodedAny == null) {
          // Kalau HTML/non-JSON, kemungkinan bukan route yang benar.
          if (_looksLikeHtml(res.body)) continue;
          throw _error('Ambil kos', url, res);
        }
        // Jika backend mengembalikan status:false, surfacing error lebih jelas.
        if (_isDefinitiveFailure(res)) {
          throw _error('Ambil kos', url, res);
        }
        return _extractList(decodedAny);
      }

      if (res.statusCode == 404) {
        // Coba kandidat lain; sebagian backend memakai prefix berbeda.
        continue;
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        // Jangan diam-diam fallback ke backend lain kecuali opt-in.
        if (_isUkkEndpoint(url) && !_enableLegacyFallback) {
          throw Exception(
            'Akses kos ditolak (${res.statusCode}).\n'
            'Pastikan login sebagai Owner/Admin dan token valid.',
          );
        }
        continue;
      }
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.ownerShowKosUrl(search: search));
    if (res == null) return const [];
    if (res.statusCode == 404) return const [];
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception(
        'Akses kos ditolak (${res.statusCode}).\n'
        'Pastikan login sebagai Owner/Admin dan token valid.',
      );
    }
    throw _error('Ambil kos', url, res);
  }

  static int? _toIntLoose(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static int? _idFromMap(dynamic item, List<String> keys) {
    if (item is! Map) return null;
    for (final k in keys) {
      if (!item.containsKey(k)) continue;
      final id = _toIntLoose(item[k]);
      if (id != null && id > 0) return id;
    }
    return null;
  }

  static Future<void> deleteKosCascade({
    required String token,
    required int kosId,
    void Function(String message)? onProgress,
  }) async {
    final errors = <String>[];

    // 1) Delete images
    onProgress?.call('Memuat gambar...');
    List<dynamic> images = const [];
    try {
      images = await OwnerImageKosService.getImages(token: token, kosId: kosId);
    } catch (e) {
      // If listing fails, continue; kos delete may still fail and will show reason.
      errors.add('Gagal memuat gambar: $e');
    }

    final imageIds = <int>{};
    for (final it in images) {
      final id = _idFromMap(it, const ['id', 'image_id', 'id_image', 'id_gambar']);
      if (id != null) imageIds.add(id);
    }

    var idx = 0;
    for (final imageId in imageIds) {
      idx++;
      onProgress?.call('Menghapus gambar ($idx/${imageIds.length})...');
      try {
        await OwnerImageKosService.deleteImage(token: token, imageId: imageId);
      } catch (e) {
        errors.add('Gagal hapus gambar #$imageId: $e');
      }
    }

    // 2) Delete facilities
    onProgress?.call('Memuat fasilitas...');
    List<dynamic> facilities = const [];
    try {
      facilities = await OwnerFacilityService.getFacilities(
        token: token,
        kosId: kosId,
      );
    } catch (e) {
      errors.add('Gagal memuat fasilitas: $e');
    }

    final facilityIds = <int>{};
    for (final it in facilities) {
      final id = _idFromMap(it, const ['id', 'facility_id', 'id_facility']);
      if (id != null) facilityIds.add(id);
    }

    idx = 0;
    for (final facilityId in facilityIds) {
      idx++;
      onProgress?.call('Menghapus fasilitas ($idx/${facilityIds.length})...');
      try {
        final ok = await OwnerFacilityService.deleteFacility(
          token: token,
          facilityId: facilityId,
        );
        if (!ok) {
          errors.add('Gagal hapus fasilitas #$facilityId');
        }
      } catch (e) {
        errors.add('Gagal hapus fasilitas #$facilityId: $e');
      }
    }

    // 3) Delete reviews
    onProgress?.call('Memuat review...');
    List<dynamic> reviews = const [];
    try {
      reviews = await OwnerReviewService.getReviews(token: token, kosId: kosId);
    } catch (e) {
      errors.add('Gagal memuat review: $e');
    }

    final reviewIds = <int>{};
    for (final it in reviews) {
      final id = _idFromMap(it, const ['id', 'review_id', 'id_review']);
      if (id != null) reviewIds.add(id);
    }

    idx = 0;
    for (final reviewId in reviewIds) {
      idx++;
      onProgress?.call('Menghapus review ($idx/${reviewIds.length})...');
      try {
        await OwnerReviewService.deleteReview(token: token, reviewId: reviewId);
      } catch (e) {
        errors.add('Gagal hapus review #$reviewId: $e');
      }
    }

    // 4) Delete kos
    onProgress?.call('Menghapus kos...');
    try {
      await deleteKos(token: token, kosId: kosId);
    } catch (e) {
      final errText = errors.isEmpty
          ? ''
          : '\n\nCatatan: ada error saat menghapus data terkait:\n- ${errors.join('\n- ')}';
      throw Exception('${e.toString().replaceFirst('Exception: ', '')}$errText');
    }
  }

  static Future<Map<String, dynamic>> detailKos({
    required String token,
    required int kosId,
  }) async {
    final candidates = <Uri>[
      Uri.parse(ApiConfig.ownerDetailKosUrl(kosId)),
      // legacy
      if (_enableLegacyFallback)
        Uri.parse('${ApiConfig.baseUrl}/owner/kos/$kosId'),
    ];

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      final res = await http
          .get(url, headers: _headers(token))
          .timeout(_timeout);
      lastRes = res;
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final data = decoded['data'];
          if (data is Map) return Map<String, dynamic>.from(data);
          return Map<String, dynamic>.from(decoded);
        }
        return <String, dynamic>{'raw': res.body};
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        if (_isUkkEndpoint(url) && !_enableLegacyFallback) {
          throw Exception(
            'Akses detail kos ditolak (${res.statusCode}).\n'
            'Pastikan login sebagai Owner/Admin dan token valid.',
          );
        }
        continue;
      }
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.ownerDetailKosUrl(kosId));
    if (res == null) throw Exception('Detail kos gagal\n$url');
    throw _error('Detail kos', url, res);
  }

  static Future<void> addKos({
    required String token,
    required int userId,
    required String name,
    required String address,
    required int pricePerMonth,
    required String gender,
  }) async {
    final candidates = <Uri>[
      Uri.parse(ApiConfig.ownerStoreKosUrl),
      // legacy
      if (_enableLegacyFallback) Uri.parse('${ApiConfig.baseUrl}/owner/kos'),
    ];

    final body = jsonEncode({
      'user_id': userId,
      'name': name,
      'address': address,
      'price_per_month': pricePerMonth,
      'gender': gender,
    });

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      final res = await http
          .post(url, headers: _headers(token), body: body)
          .timeout(_timeout);
      lastRes = res;
      final ok = res.statusCode == 200 || res.statusCode == 201;
      if (ok) return;
      if (res.statusCode == 401 || res.statusCode == 403) {
        if (_isUkkEndpoint(url) && !_enableLegacyFallback) {
          throw Exception(
            'Akses tambah kos ditolak (${res.statusCode}).\n'
            'Pastikan login sebagai Owner/Admin dan token valid.',
          );
        }
        continue;
      }
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.ownerStoreKosUrl);
    if (res == null) throw Exception('Tambah kos gagal\n$url');
    throw _error('Tambah kos', url, res);
  }

  static Future<void> updateKos({
    required String token,
    required int kosId,
    required int userId,
    required String name,
    required String address,
    required int pricePerMonth,
    required String gender,
  }) async {
    final candidates = <Uri>[
      Uri.parse(ApiConfig.ownerUpdateKosUrl(kosId)),
      // legacy
      if (_enableLegacyFallback)
        Uri.parse('${ApiConfig.baseUrl}/owner/kos/$kosId'),
    ];

    final body = jsonEncode({
      'user_id': userId,
      'name': name,
      'address': address,
      'price_per_month': pricePerMonth,
      'gender': gender,
    });

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      final res = await http
          .put(url, headers: _headers(token), body: body)
          .timeout(_timeout);
      lastRes = res;
      final ok = res.statusCode == 200 || res.statusCode == 204;
      if (ok) return;
      if (res.statusCode == 401 || res.statusCode == 403) {
        if (_isUkkEndpoint(url) && !_enableLegacyFallback) {
          throw Exception(
            'Akses update kos ditolak (${res.statusCode}).\n'
            'Pastikan login sebagai Owner/Admin dan token valid.',
          );
        }
        continue;
      }
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.ownerUpdateKosUrl(kosId));
    if (res == null) throw Exception('Update kos gagal\n$url');
    throw _error('Update kos', url, res);
  }

  static Future<void> deleteKos({
    required String token,
    required int kosId,
  }) async {
    final candidates = <Uri>[
      // UKK KOS backend biasanya pakai prefix '/admin' untuk endpoint owner.
      _ukk('admin/delete_kos/$kosId'),
      // Sebagian project menaruhnya tanpa '/admin'.
      _ukk('delete_kos/$kosId'),

      // Configured endpoint (in case project uses a custom route).
      Uri.parse(ApiConfig.ownerDeleteKosUrl(kosId)),

      // Variasi query-parameter (beberapa backend tidak pakai path param).
      _ukkQuery('admin/delete_kos', {'id': '$kosId'}),
      _ukkQuery('admin/delete_kos', {'kos_id': '$kosId'}),
      _ukkQuery('delete_kos', {'id': '$kosId'}),
      _ukkQuery('delete_kos', {'kos_id': '$kosId'}),

      // legacy (opt-in; on Flutter Web this often fails due to CORS / server not running)
      if (_enableLegacyFallback)
        Uri.parse('${ApiConfig.baseUrl}/owner/kos/$kosId'),
    ];

    http.Response? lastRes;
    Uri? lastUrl;
    final attempts = <String>[];

    for (final url in candidates) {
      lastUrl = url;

      // Default: DELETE
      http.Response? res;
      try {
        res = await http
            .delete(url, headers: _headers(token))
            .timeout(_timeout);
      } catch (e) {
        attempts.add('EXCEPTION DELETE $url  $e');
        continue;
      }

      lastRes = res;
      attempts.add('${res.statusCode} DELETE $url  ${_previewBody(res)}');
      final ok =
          (res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 204) &&
          _isLogicalSuccess(res);
      if (ok) return;

      // If backend responded with a structured failure (status:false), surface it.
      if ((res.statusCode == 200 || res.statusCode == 201) && _isDefinitiveFailure(res)) {
        final detail = attempts.isEmpty ? '' : '\n\nDicoba:\n${attempts.join('\n')}';
        throw Exception('${_error('Hapus kos', url, res)}$detail');
      }

      // Banyak backend Laravel tidak mengizinkan DELETE dan memakai POST untuk aksi delete.
      if (res.statusCode == 405) {
        http.Response? resPost;
        try {
          resPost = await http
              .post(url, headers: _headers(token))
              .timeout(_timeout);
        } catch (e) {
          attempts.add('EXCEPTION POST $url  $e');
          continue;
        }

        lastRes = resPost;
        attempts.add('${resPost.statusCode} POST $url  ${_previewBody(resPost)}');
        final okPost =
          (resPost.statusCode == 200 ||
            resPost.statusCode == 201 ||
            resPost.statusCode == 204) &&
          _isLogicalSuccess(resPost);
        if (okPost) return;

        if ((resPost.statusCode == 200 || resPost.statusCode == 201) &&
          _isDefinitiveFailure(resPost)) {
          final detail = attempts.isEmpty ? '' : '\n\nDicoba:\n${attempts.join('\n')}';
          throw Exception('${_error('Hapus kos', url, resPost)}$detail');
        }

        // Jika POST juga 404/401/403, lanjutkan ke kandidat berikutnya.
        if (resPost.statusCode == 404) continue;
        if (resPost.statusCode == 401 || resPost.statusCode == 403) continue;
        continue;
      }

      // 404 bisa berarti: route tidak ada di endpoint ini ATAU kosId tidak ditemukan.
      // Jangan dianggap sukses, karena UI akan menampilkan "Kos dihapus" padahal
      // backend tidak menghapus apa-apa. Coba kandidat endpoint berikutnya.
      if (res.statusCode == 404) continue;
      if (res.statusCode == 401 || res.statusCode == 403) continue;
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.ownerDeleteKosUrl(kosId));
    if (res == null) throw Exception('Hapus kos gagal\n$url');
    if (res.statusCode == 404) {
      final detail = attempts.isEmpty ? '' : '\n\nDicoba:\n${attempts.join('\n')}';
      throw Exception(
        'Hapus kos gagal (404)\n$url\nRoute tidak ditemukan atau kosId tidak ada.$detail',
      );
    }
    final detail = attempts.isEmpty ? '' : '\n\nDicoba:\n${attempts.join('\n')}';
    throw Exception('${_error('Hapus kos', url, res)}$detail');
  }
}
