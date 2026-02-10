import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

class BookingService {
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

  static List<dynamic> _extractList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) return data;
      if (data is Map) {
        final inner = data['data'];
        if (inner is List) return inner;
        final innerItems = data['items'];
        if (innerItems is List) return innerItems;
      }
      final items = decoded['items'];
      if (items is List) return items;
    }
    return const [];
  }

  static Map<String, dynamic> _extractMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is List && data.isNotEmpty && data.first is Map) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      return Map<String, dynamic>.from(decoded);
    }
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return Map<String, dynamic>.from(decoded.first as Map);
    }
    return <String, dynamic>{};
  }

  static Future<http.Response> _safeGet(Uri url, {required String token}) {
    return http.get(url, headers: _headers(token)).timeout(const Duration(seconds: 20));
  }

  static Future<http.Response> _safePost(Uri url, {required String token, Object? body}) {
    return http
        .post(url, headers: _headers(token), body: body)
        .timeout(const Duration(seconds: 25));
  }

  static Future<List<dynamic>> showKos({required String token, String? search}) async {
    final trimmedSearch = (search ?? '').trim();

    final ukkUrl = Uri.parse(ApiConfig.societyShowKosUrl(search: trimmedSearch));
    final legacyUrl = Uri.parse('${ApiConfig.baseUrl}/society/kos').replace(
      queryParameters: trimmedSearch.isEmpty ? const {} : {'search': trimmedSearch},
    );

    http.Response? res;
    Object? lastError;

    try {
      res = await _safeGet(ukkUrl, token: token);
      if (res.statusCode == 200) return _extractList(res.body);
    } catch (e) {
      lastError = e;
    }

    try {
      res = await _safeGet(legacyUrl, token: token);
      if (res.statusCode == 200) return _extractList(res.body);
    } catch (e) {
      lastError = e;
    }

    final code = res?.statusCode;
    final bodyPreview = (res?.body ?? '').trim();
    final trimmed = bodyPreview.length > 160 ? '${bodyPreview.substring(0, 160)}…' : bodyPreview;
    throw Exception(
      'Gagal memuat kos. '
      'UKK: ${ukkUrl.toString()} | Legacy: ${legacyUrl.toString()} '
      '(${code ?? '-'}) ${trimmed.isEmpty ? '' : trimmed} '
      '${lastError == null ? '' : '| $lastError'}',
    );
  }

  static Future<Map<String, dynamic>> getKosDetail({
    required String token,
    required int kosId,
  }) async {
    final ukkUrl = Uri.parse(ApiConfig.societyDetailKosUrl(kosId));
    final legacyUrl = Uri.parse('${ApiConfig.baseUrl}/society/kos/$kosId');

    http.Response? res;
    Object? lastError;

    try {
      res = await _safeGet(ukkUrl, token: token);
      if (res.statusCode == 200) return _extractMap(res.body);
    } catch (e) {
      lastError = e;
    }

    try {
      res = await _safeGet(legacyUrl, token: token);
      if (res.statusCode == 200) return _extractMap(res.body);
    } catch (e) {
      lastError = e;
    }

    final code = res?.statusCode;
    final bodyPreview = (res?.body ?? '').trim();
    final trimmed = bodyPreview.length > 160 ? '${bodyPreview.substring(0, 160)}…' : bodyPreview;
    throw Exception(
      'Gagal memuat detail kos. '
      'UKK: ${ukkUrl.toString()} | Legacy: ${legacyUrl.toString()} '
      '(${code ?? '-'}) ${trimmed.isEmpty ? '' : trimmed} '
      '${lastError == null ? '' : '| $lastError'}',
    );
  }

  static Future<Map<String, dynamic>> createBooking({
    required String token,
    required int kosId,
    required String startDate,
    required String endDate,
  }) async {
    final url = Uri.parse(ApiConfig.societyBookingUrl);
    http.Response? res;

    try {
      res = await _safePost(
        url,
        token: token,
        body: jsonEncode({
          'kos_id': kosId,
          'start_date': startDate,
          'end_date': endDate,
        }),
      );
    } catch (e) {
      throw Exception('Gagal booking (request error): $e');
    }

    if (res.statusCode == 200 || res.statusCode == 201) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);

          bool? boolField(dynamic v) => (v is bool) ? v : null;
          final status = boolField(map['status']);
          final success = boolField(map['success'] ?? map['isSuccess']);

          // Many UKK APIs return HTTP 200 with {status:false, message:"..."}.
          if (status == false || success == false) {
            final msg = (map['message'] ?? map['msg'] ?? map['error'] ?? '').toString().trim();
            throw Exception(msg.isEmpty ? 'Booking ditolak oleh server.' : msg);
          }

          // Some backends nest status/message inside data.
          final data = map['data'];
          if (data is Map) {
            final dStatus = boolField(data['status']);
            final dSuccess = boolField(data['success'] ?? data['isSuccess']);
            if (dStatus == false || dSuccess == false) {
              final msg = (data['message'] ?? data['msg'] ?? map['message'] ?? '').toString().trim();
              throw Exception(msg.isEmpty ? 'Booking ditolak oleh server.' : msg);
            }
          }

          return map;
        }
      } catch (e) {
        // If JSON decode succeeded and indicates failure, surface it.
        if (e is Exception) rethrow;
      }

      // Non-JSON success response.
      return <String, dynamic>{'raw': res.body};
    }

    final bodyPreview = res.body.trim();
    final trimmed = bodyPreview.length > 200 ? '${bodyPreview.substring(0, 200)}…' : bodyPreview;
    throw Exception('Gagal booking (${res.statusCode}): $trimmed');
  }

  static Future<List<dynamic>> getBookingHistory({
    required String token,
    String status = 'all',
  }) async {
    final st = status.trim();
    final ukkCandidates = <Uri>[];
    if (st.isEmpty || st.toLowerCase() == 'all') {
      // Different UKK implementations:
      // - /society/show_bookings
      // - /society/show_bookings?status=
      // - /society/show_bookings?status=all
      ukkCandidates.add(Uri.parse(ApiConfig.societyShowBookingsUrl(status: 'all')));
      ukkCandidates.add(Uri.parse('${ApiConfig.authBaseUrl}/society/show_bookings?status='));
      ukkCandidates.add(Uri.parse('${ApiConfig.authBaseUrl}/society/show_bookings?status=all'));
    } else {
      ukkCandidates.add(Uri.parse(ApiConfig.societyShowBookingsUrl(status: st)));
    }

    final legacyUrl = Uri.parse('${ApiConfig.baseUrl}/society/bookings')
        .replace(queryParameters: {'status': st});

    http.Response? res;
    Object? lastError;

    for (final ukkUrl in ukkCandidates) {
      try {
        res = await _safeGet(ukkUrl, token: token);
        if (res.statusCode == 200) return _extractList(res.body);
      } catch (e) {
        lastError = e;
      }
    }

    try {
      res = await _safeGet(legacyUrl, token: token);
      if (res.statusCode == 200) return _extractList(res.body);
    } catch (e) {
      lastError = e;
    }

    final code = res?.statusCode;
    final bodyPreview = (res?.body ?? '').trim();
    final trimmed = bodyPreview.length > 160 ? '${bodyPreview.substring(0, 160)}…' : bodyPreview;
    throw Exception(
      'Gagal memuat history booking. '
      'UKK: ${ukkCandidates.map((e) => e.toString()).join(' | ')} | Legacy: ${legacyUrl.toString()} '
      '(${code ?? '-'}) ${trimmed.isEmpty ? '' : trimmed} '
      '${lastError == null ? '' : '| $lastError'}',
    );
  }
}
