import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

class OwnerBookingService {
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
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) return decoded;
      if (decoded is Map) {
        final data = decoded['data'];
        if (data is List) return data;
        // Sometimes APIs nest list under data.data
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
    } catch (e) {
      final preview = body.length > 140 ? '${body.substring(0, 140)}…' : body;
      throw Exception('Response bukan JSON: $e\n$preview');
    }
  }

  static dynamic _tryDecodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeNoBookings(dynamic decoded) {
    if (decoded is! Map) return false;

    String asString(dynamic v) => (v == null) ? '' : v.toString();

    final message = asString(
      decoded['message'] ??
          decoded['msg'] ??
          decoded['error'] ??
          decoded['errors'] ??
          decoded['detail'],
    ).trim();
    final status = asString(decoded['status']).trim().toLowerCase();

    bool containsNoBookingsText(String s) {
      final t = s.toLowerCase();
      return t.contains('no booking') ||
          t.contains('no bookings') ||
          t.contains('no bookings found') ||
          t.contains('tidak ada booking') ||
          t.contains('belum ada booking');
    }

    if (message.isNotEmpty && containsNoBookingsText(message)) return true;

    // Some APIs return {status: failed, data: []} without a useful message.
    final data = decoded['data'];
    if ((status == 'failed' || status == 'error') &&
        data is List &&
        data.isEmpty) {
      return true;
    }

    // Sometimes list is nested under data.data.
    if ((status == 'failed' || status == 'error') && data is Map) {
      final inner = data['data'];
      if (inner is List && inner.isEmpty) return true;
      final items = data['items'];
      if (items is List && items.isEmpty) return true;
    }

    return false;
  }

  static Uri _ukkBookingsUrl({required Map<String, String> qp}) {
    // UKK endpoint for bookings: /admin/show_bookings
    return Uri.parse(
      ApiConfig.ownerShowBookingsUrl(),
    ).replace(queryParameters: qp.isEmpty ? null : qp);
  }

  static Uri _legacyBookingsUrl({required Map<String, String> qp}) {
    return Uri.parse(
      '${ApiConfig.baseUrl}/owner/bookings',
    ).replace(queryParameters: qp.isEmpty ? null : qp);
  }

  static Future<http.Response> _safeGet(
    Uri url, {
    required String token,
  }) async {
    return http
        .get(url, headers: _headers(token))
        .timeout(const Duration(seconds: 20));
  }

  static Future<http.Response> _safePut(
    Uri url, {
    required String token,
    required Object body,
  }) async {
    return http
        .put(url, headers: _headers(token), body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
  }

  static Future<List<dynamic>> getBookings({
    required String token,
    String? tgl,
    String? month,
    String status = 'all',
  }) async {
    // UKK docs:
    // GET /admin/show_bookings?status=&tgl=YYYY-MM-DD
    // So we support:
    // - tgl: single day query
    // - month: fetch each day in month (multi requests)

    final st = status.trim();

    if (month != null &&
        month.trim().isNotEmpty &&
        (tgl == null || tgl.trim().isEmpty)) {
      final m = month.trim();
      final parsed = DateTime.tryParse('$m-01');
      if (parsed == null) {
        throw Exception('Format month tidak valid (expected YYYY-MM): $m');
      }

      final daysInMonth = DateTime(parsed.year, parsed.month + 1, 0).day;
      final results = await Future.wait(
        List.generate(daysInMonth, (i) {
          final d = DateTime(parsed.year, parsed.month, i + 1);
          final t =
              '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return getBookings(token: token, tgl: t, status: status);
        }),
      );

      final merged = <dynamic>[];
      for (final list in results) {
        merged.addAll(list);
      }
      return merged;
    }

    final qp = <String, String>{};
    final d = (tgl ?? '').trim();
    if (d.isNotEmpty) qp['tgl'] = d;
    if (st.isNotEmpty && st.toLowerCase() != 'all') qp['status'] = st;

    final ukkUrl = _ukkBookingsUrl(qp: qp);
    final legacyUrl = _legacyBookingsUrl(
      qp: {
        if (d.isNotEmpty) 'tgl': d,
        if (month != null && month.trim().isNotEmpty) 'month': month.trim(),
        if (st.isNotEmpty) 'status': st,
      },
    );

    http.Response? res;
    Object? lastError;

    // Try UKK first.
    try {
      res = await _safeGet(ukkUrl, token: token);
      if (res.statusCode == 200) return _extractList(res.body);

      final decoded = _tryDecodeJson(res.body);
      if (_looksLikeNoBookings(decoded)) return const [];
    } catch (e) {
      lastError = e;
    }

    // Fallback to legacy baseUrl.
    try {
      res = await _safeGet(legacyUrl, token: token);
      if (res.statusCode == 200) return _extractList(res.body);

      final decoded = _tryDecodeJson(res.body);
      if (_looksLikeNoBookings(decoded)) return const [];
    } catch (e) {
      lastError = e;
    }

    final code = res?.statusCode;
    final bodyPreview = (res?.body ?? '').trim();
    final trimmed = bodyPreview.length > 160
        ? '${bodyPreview.substring(0, 160)}…'
        : bodyPreview;
    throw Exception(
      'Gagal memuat bookings. '
      'UKK: ${ukkUrl.toString()} | Legacy: ${legacyUrl.toString()} '
      '(${code ?? '-'}) ${trimmed.isEmpty ? '' : trimmed} '
      '${lastError == null ? '' : '| $lastError'}',
    );
  }

  static Future<void> updateStatus({
    required String token,
    required int bookingId,
    required String status,
  }) async {
    final ukkUrl = Uri.parse(ApiConfig.ownerUpdateStatusBookingUrl(bookingId));
    final legacyUrl = Uri.parse(
      '${ApiConfig.baseUrl}/owner/bookings/$bookingId/status',
    );

    http.Response? res;
    Object? lastError;

    try {
      res = await _safePut(ukkUrl, token: token, body: {'status': status});
      final ok = res.statusCode == 200 || res.statusCode == 201;
      if (ok) return;
    } catch (e) {
      lastError = e;
    }

    try {
      res = await _safePut(legacyUrl, token: token, body: {'status': status});
      final ok = res.statusCode == 200 || res.statusCode == 201;
      if (ok) return;
    } catch (e) {
      lastError = e;
    }

    final code = res?.statusCode;
    final bodyPreview = (res?.body ?? '').trim();
    final trimmed = bodyPreview.length > 160
        ? '${bodyPreview.substring(0, 160)}…'
        : bodyPreview;
    throw Exception(
      'Gagal update status booking. '
      'UKK: ${ukkUrl.toString()} | Legacy: ${legacyUrl.toString()} '
      '(${code ?? '-'}) ${trimmed.isEmpty ? '' : trimmed} '
      '${lastError == null ? '' : '| $lastError'}',
    );
  }
}
