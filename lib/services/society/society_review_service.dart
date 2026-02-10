import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

class SocietyReviewService {
  static final RegExp _replyMarker = RegExp(r'\[\[reply_to:(\d+)\]\]\s*(.*)$');

  static String _authValue(String token) {
    final t = token.trim();
    if (t.toLowerCase().startsWith('bearer ')) return t;
    return 'Bearer $t';
  }

  static int? _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static String _asString(dynamic v) => (v == null) ? '' : v.toString();

  static String _reviewTextFromItem(dynamic item) {
    if (item is Map) {
      return _asString(
        item['review'] ??
            item['ulasan'] ??
            item['comment'] ??
            item['message'] ??
            item['content'],
      );
    }
    return _asString(item);
  }

  static int? _reviewIdFromItem(dynamic item) {
    if (item is Map) {
      return _toInt(item['id'] ?? item['review_id'] ?? item['id_review']);
    }
    return null;
  }

  static DateTime? _createdAtFromItem(dynamic item) {
    if (item is! Map) return null;
    final raw =
        item['created_at'] ?? item['createdAt'] ?? item['date'] ?? item['tanggal'];
    final s = _asString(raw).trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
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
    final latestReplyByTargetId =
        <int, ({String text, DateTime? createdAt, int markerId})>{};

    for (var i = 0; i < raw.length; i++) {
      final it = raw[i];
      if (it is! Map) continue;

      // Build a candidate string that includes review-like and reply-like
      // fields so marker replies are detected regardless of which field
      // the backend stored the marker in.
      final candidates = <String>[
        _asString(it['review']),
        _asString(it['ulasan']),
        _asString(it['comment']),
        _asString(it['message']),
        _asString(it['content']),
        _asString(it['reply']),
        _asString(it['response']),
        _asString(it['balasan']),
        _asString(it['tanggapan']),
        _asString(it['owner_reply']),
        _asString(it['admin_reply']),
      ];
      final joined = candidates.where((s) => s.trim().isNotEmpty).join(' ').trim();
      final m = joined.isEmpty ? null : _replyMarker.firstMatch(joined);
      if (m == null) continue;

      final targetId = int.tryParse(m.group(1) ?? '');
      if (targetId == null || targetId == 0) continue;

      var replyText = (m.group(2) ?? '').trim();
      if (replyText.isEmpty) {
        // If regex group is empty, attempt to read reply-like fields directly
        // (some backends place the reply text into a separate column).
        for (final key in [
          'reply',
          'response',
          'balasan',
          'tanggapan',
          'owner_reply',
          'admin_reply',
          'message',
          'content',
        ]) {
          final cand = _asString(it[key]).trim();
          if (cand.isNotEmpty) {
            replyText = cand;
            break;
          }
        }
        if (replyText.isEmpty) {
          toRemove.add(i);
          continue;
        }
      }

      final markerId = _reviewIdFromItem(it) ?? 0;
      final createdAt = _createdAtFromItem(it);

      final prev = latestReplyByTargetId[targetId];
      if (prev == null) {
        latestReplyByTargetId[targetId] = (
          text: replyText,
          createdAt: createdAt,
          markerId: markerId,
        );
      } else {
        final prevAt = prev.createdAt;
        final useNew = (createdAt != null && prevAt != null)
            ? createdAt.isAfter(prevAt)
            : (createdAt != null && prevAt == null)
                ? true
                : (createdAt == null && prevAt != null)
                    ? false
                    : markerId >= prev.markerId;

        if (useNew) {
          latestReplyByTargetId[targetId] = (
            text: replyText,
            createdAt: createdAt,
            markerId: markerId,
          );
        }
      }

      // Hide marker entries in society UI; replies should appear in the original card.
      toRemove.add(i);
    }

    for (final entry in latestReplyByTargetId.entries) {
      final targetId = entry.key;
      final replyText = entry.value.text;
      final targetIndex = idToIndex[targetId];
      if (targetIndex == null) continue;

      final target = raw[targetIndex];
      if (target is! Map) continue;

      // Overwrite reply fields so the latest owner reply is shown.
      target['reply'] = replyText;
      target['owner_reply'] = replyText;
      target['admin_reply'] = replyText;
      target['response'] = replyText;
      target['balasan'] = replyText;
      target['tanggapan'] = replyText;
    }

    if (toRemove.isEmpty) return raw;

    final merged = <dynamic>[];
    for (var i = 0; i < raw.length; i++) {
      if (!toRemove.contains(i)) merged.add(raw[i]);
    }
    return merged;
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

  static bool _looksLikeLogicalSuccess(dynamic decoded) {
    if (decoded is! Map) return true;
    final v = decoded['status'] ?? decoded['success'] ?? decoded['ok'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return true;
    if (s == 'true' || s == '1' || s == 'ok' || s == 'success') return true;
    if (s == 'false' || s == '0' || s == 'failed' || s == 'error') return false;
    return true;
  }

  static String _messageFromDecoded(dynamic decoded) {
    if (decoded is! Map) return '';
    final msg = decoded['message'] ?? decoded['msg'] ?? decoded['error'];
    return (msg ?? '').toString().trim();
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) return data;

      if (data is Map) {
        final nested = data['data'];
        if (nested is List) return nested;
        final reviews = data['reviews'];
        if (reviews is List) return reviews;
      }

      final reviews = decoded['reviews'];
      if (reviews is List) return reviews;

      final items = decoded['items'];
      if (items is List) return items;
    }
    return const [];
  }

  static Future<List<dynamic>> getReviews({
    required String token,
    required int kosId,
  }) async {
    final candidates = <Uri>[
      Uri.parse(ApiConfig.societyShowReviewsUrl(kosId)),
      // legacy fallbacks
      Uri.parse('${ApiConfig.showReviewsSociety}/$kosId'),
      Uri.parse('${ApiConfig.showReviewsOwner}/$kosId'),
    ];

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      http.Response res;
      try {
        res = await http
            .get(url, headers: _headers(token))
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        continue;
      }
      lastRes = res;

      // Some endpoints use 404 to mean “no reviews yet”.
      if (res.statusCode == 404) return const [];

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final list = List<dynamic>.from(_extractList(decoded));
        if (list.isEmpty) return const [];
        return _mergeReplyMarkerIntoOriginal(list);
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        // token invalid / forbidden → treat as empty in UI, page handles re-login.
        return const [];
      }
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.societyShowReviewsUrl(kosId));
    if (res == null) return const [];
    throw _error('Ambil review', url, res);
  }

  static Future<void> addReview({
    required String token,
    required int kosId,
    required String review,
  }) async {
    final candidates = <Uri>[
      Uri.parse(ApiConfig.societyStoreReviewsUrl(kosId)),
      // legacy
      Uri.parse('${ApiConfig.storeReviewsSociety}/$kosId'),
    ];

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      http.Response res;
      try {
        res = await http
            .post(
              url,
              headers: _headers(token),
              body: jsonEncode({'review': review}),
            )
            .timeout(const Duration(seconds: 25));
      } catch (_) {
        continue;
      }
      lastRes = res;

      final ok = res.statusCode == 200 ||
          res.statusCode == 201 ||
          res.statusCode == 204;
      if (ok) return;
      if (res.statusCode == 401 || res.statusCode == 403) continue;
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.societyStoreReviewsUrl(kosId));
    if (res == null) throw Exception('Tambah review gagal\n$url');
    throw _error('Tambah review', url, res);
  }

  static Future<void> deleteReview({
    required String token,
    required int reviewId,
  }) async {
    final candidates = <Uri>[
      Uri.parse(ApiConfig.deleteReviewUrl(reviewId)),
      // legacy
      Uri.parse('${ApiConfig.deleteReview}/$reviewId'),
    ];

    http.Response? lastRes;
    Uri? lastUrl;

    for (final url in candidates) {
      lastUrl = url;
      http.Response res;
      try {
        res = await http
            .delete(url, headers: _headers(token))
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        continue;
      }
      lastRes = res;

      final okHttp =
          res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 204;
      if (okHttp) {
        if (res.statusCode == 204 || res.body.trim().isEmpty) return;
        try {
          final decoded = jsonDecode(res.body);
          if (_looksLikeLogicalSuccess(decoded)) return;
          final msg = _messageFromDecoded(decoded);
          throw Exception(msg.isEmpty ? 'Hapus review ditolak oleh server' : msg);
        } catch (e) {
          // If body isn't JSON, treat 200 as OK.
          if (e is FormatException) return;
          rethrow;
        }
      }
      if (res.statusCode == 401 || res.statusCode == 403) continue;
    }

    final res = lastRes;
    final url = lastUrl ?? Uri.parse(ApiConfig.deleteReviewUrl(reviewId));
    if (res == null) throw Exception('Hapus review gagal\n$url');
    throw _error('Hapus review', url, res);
  }
}
