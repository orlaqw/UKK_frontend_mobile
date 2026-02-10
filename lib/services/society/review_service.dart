import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';

class ReviewService {
  static const Duration _timeout = Duration(seconds: 20);

  static final RegExp _replyMarker = RegExp(r'\[\[reply_to:(\d+)\]\]\s*(.*)$');

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

  static Exception _error(String action, Uri url, http.Response res) {
    final body = res.body;
    final preview = body.length > 400 ? body.substring(0, 400) : body;
    return Exception('$action gagal (${res.statusCode})\n$url\n$preview');
  }

  static Exception _timeoutError(String action, Uri url) {
    return Exception(
      '$action timeout (${_timeout.inSeconds}s)\n'
      '$url\n'
      'Cek koneksi internet atau server sedang lambat/down.',
    );
  }

  static bool _isReviewLikeMap(Map<dynamic, dynamic> m) {
    final keys = m.keys.map((e) => e.toString()).toSet();
    if (keys.contains('review') ||
        keys.contains('ulasan') ||
        keys.contains('comment') ||
        keys.contains('message') ||
        keys.contains('content')) {
      return true;
    }
    // Response kadang hanya berisi reply tanpa review di object tertentu.
    if (keys.contains('reply') ||
        keys.contains('owner_reply') ||
        keys.contains('admin_reply') ||
        keys.contains('response') ||
        keys.contains('balasan') ||
        keys.contains('tanggapan')) {
      return true;
    }
    return false;
  }

  static List<dynamic>? _findReviewList(
    dynamic node, {
    String? parentKey,
    int depth = 0,
  }) {
    if (depth > 6) return null;

    if (node is List) {
      if (node.isEmpty) return null;

      final mapItems = node.whereType<Map>().toList();
      if (mapItems.isNotEmpty) {
        final hits = mapItems.where(_isReviewLikeMap).length;
        if (hits > 0) return node;
      }

      // kalau list primitive, hanya anggap review jika key meyakinkan
      if (node.every((e) => e is String || e is num)) {
        final k = (parentKey ?? '').toLowerCase();
        if (k.contains('review') || k.contains('ulasan')) return node;
      }

      for (final item in node) {
        final found = _findReviewList(
          item,
          parentKey: parentKey,
          depth: depth + 1,
        );
        if (found != null) return found;
      }
      return null;
    }

    if (node is Map) {
      // Prioritas key yang cocok
      for (final entry in node.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if (v is List) {
          final lower = k.toLowerCase();
          if (lower.contains('review') ||
              lower.contains('ulasan') ||
              lower.contains('comment')) {
            final found = _findReviewList(
              v,
              parentKey: k,
              depth: depth + 1,
            );
            if (found != null) return found;
          }
        }
      }

      for (final entry in node.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        final found = _findReviewList(
          v,
          parentKey: k,
          depth: depth + 1,
        );
        if (found != null) return found;
      }
      return null;
    }

    return null;
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) return data;
      if (data is Map) {
        final nestedData = data['data'];
        if (nestedData is List) return nestedData;
        final nestedReviews = data['reviews'];
        if (nestedReviews is List) return nestedReviews;

        final found = _findReviewList(data, parentKey: 'data');
        if (found != null) return found;
      }

      final reviews = decoded['reviews'];
      if (reviews is List) return reviews;

      // Beberapa backend mengembalikan list review di key lain.
      final items = decoded['items'];
      if (items is List) return items;

      final found = _findReviewList(decoded, parentKey: 'root');
      if (found != null) return found;
    }
    return const [];
  }

  static int? _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static String _asString(dynamic v) => (v == null) ? '' : v.toString();

  static String _reviewTextFromItem(dynamic item) {
    if (item is Map) {
      return _asString(item['review'] ?? item['ulasan'] ?? item['comment'] ?? item['message'] ?? item['content']);
    }
    return _asString(item);
  }

  static int? _reviewIdFromItem(dynamic item) {
    if (item is Map) {
      return _toInt(item['id'] ?? item['review_id'] ?? item['id_review']);
    }
    return null;
  }

  static List<dynamic> _mergeReplyMarkerIntoOriginal(List<dynamic> raw) {
    if (raw.isEmpty) return raw;

    // Build id -> map item index.
    final idToIndex = <int, int>{};
    for (var i = 0; i < raw.length; i++) {
      final it = raw[i];
      if (it is! Map) continue;
      final id = _reviewIdFromItem(it);
      if (id != null && id != 0) {
        idToIndex.putIfAbsent(id, () => i);
      }
    }

    final toRemove = <int>{};

    for (var i = 0; i < raw.length; i++) {
      final it = raw[i];
      if (it is! Map) continue;

      final text = _reviewTextFromItem(it);
      final m = _replyMarker.firstMatch(text);
      if (m == null) continue;

      final targetId = int.tryParse(m.group(1) ?? '');
      if (targetId == null || targetId == 0) continue;

      final replyText = (m.group(2) ?? '').trim();
      final targetIndex = idToIndex[targetId];

      if (targetIndex != null) {
        final target = raw[targetIndex];
        if (target is Map) {
          // Isi beberapa field reply yang biasa dipakai UI.
          final existing = _asString(target['reply'] ?? target['owner_reply'] ?? target['admin_reply'] ?? target['response'] ?? target['balasan'] ?? target['tanggapan']).trim();
          if (existing.isEmpty && replyText.isNotEmpty) {
            target['reply'] = replyText;
            target['owner_reply'] = replyText;
            target['admin_reply'] = replyText;
            target['response'] = replyText;
            target['balasan'] = replyText;
            target['tanggapan'] = replyText;
          }
        }
        toRemove.add(i);
      } else {
        // Tidak menemukan review asal: setidaknya buang marker agar tidak mengganggu UI.
        if (replyText.isNotEmpty) {
          it['review'] = replyText;
        }
      }
    }

    if (toRemove.isEmpty) return raw;

    final merged = <dynamic>[];
    for (var i = 0; i < raw.length; i++) {
      if (!toRemove.contains(i)) merged.add(raw[i]);
    }
    return merged;
  }

  static Future<List<dynamic>> getReviews({
    required String token,
    required int kosId,
  }) async {
    final baseSociety = Uri.parse(ApiConfig.showReviewsSociety);
    final baseReview = Uri.parse(ApiConfig.review);
    final baseOwner = Uri.parse(ApiConfig.showReviewsOwner);

    final candidates = <Uri>{
      // Most common: /resource/{id}
      Uri.parse('${ApiConfig.showReviewsSociety}/$kosId'),
      Uri.parse('${ApiConfig.review}/$kosId'),
      // Query params variants
      baseSociety.replace(queryParameters: {'kos_id': '$kosId'}),
      baseSociety.replace(queryParameters: {'id': '$kosId'}),
      baseReview.replace(queryParameters: {'kos_id': '$kosId'}),
      baseReview.replace(queryParameters: {'id': '$kosId'}),
      // Fallback: beberapa deployment hanya expose balasan di jalur admin
      // (jika token society ditolak, akan 401/403 dan kita lanjut coba kandidat lain)
      Uri.parse('${ApiConfig.showReviewsOwner}/$kosId'),
      baseOwner.replace(queryParameters: {'kos_id': '$kosId'}),
      baseOwner.replace(queryParameters: {'id': '$kosId'}),
    };

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      try {
        final res = await http
            .get(url, headers: _headers(token))
            .timeout(_timeout);
        lastRes = res;

        // Sebagian endpoint mengembalikan 404 saat data kosong.
        if (res.statusCode == 404) {
          continue;
        }

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final list = _extractList(decoded);
          // List kosong pada 200 adalah kondisi valid: berarti belum ada review.
          // Jangan lanjut mencoba endpoint lain karena bisa memperlambat UI
          // (terutama saat halaman menggabungkan review dari banyak kos).
          return _mergeReplyMarkerIntoOriginal(List<dynamic>.from(list));
        }

        // 401/403/500 dsb: coba kandidat lain
        continue;
      } on TimeoutException {
        // timeout pada satu endpoint -> coba yang lain
        continue;
      }
    }

    // Jika semuanya gagal tapi hanya karena no data / forbidden, kembalikan kosong.
    if ((lastRes?.statusCode ?? 0) == 404) return const [];
    if ((lastRes?.statusCode ?? 0) == 401) return const [];
    if ((lastRes?.statusCode ?? 0) == 403) return const [];

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.showReviewsSociety);
    if (res == null) return const [];
    throw _error('Ambil review', url, res);
  }

  static Future<void> submitReview({
    required String token,
    required int kosId,
    required String review,
  }) async {
    final url = Uri.parse('${ApiConfig.storeReviewsSociety}/$kosId');
    http.Response res;
    try {
      res = await http
          .post(
            url,
            headers: _headers(token),
            body: jsonEncode({'review': review}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw _timeoutError('Kirim review', url);
    }

    final ok = res.statusCode == 200 || res.statusCode == 201;
    if (ok) return;

    throw _error('Kirim review', url, res);
  }

  static Future<void> deleteReview({
    required String token,
    required int reviewId,
  }) async {
    final url = Uri.parse('${ApiConfig.deleteReview}/$reviewId');
    http.Response res;
    try {
      res = await http.delete(url, headers: _headers(token)).timeout(_timeout);
    } on TimeoutException {
      throw _timeoutError('Hapus review', url);
    }

    final ok = res.statusCode == 200 || res.statusCode == 204;
    if (ok) return;

    throw _error('Hapus review', url, res);
  }
}
