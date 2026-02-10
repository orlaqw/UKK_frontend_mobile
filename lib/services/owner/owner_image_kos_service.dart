import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';

class OwnerImageKosService {
  static String _authValue(String token) {
    final t = token.trim();
    if (t.toLowerCase().startsWith('bearer ')) return t;
    return 'Bearer $t';
  }

  static Map<String, String> _headers(String token) {
    return {'MakerID': ApiConfig.makerId, 'Authorization': _authValue(token)};
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final data = decoded['data'] ?? decoded['images'] ?? decoded['result'];
      if (data is List) return data;
      if (data is Map) {
        final inner =
            data['data'] ?? data['items'] ?? data['images'] ?? data['result'];
        if (inner is List) return inner;
      }
    }
    return const [];
  }

  static String _extractUrl(dynamic item) {
    if (item == null) return '';
    if (item is String) return item.trim();

    if (item is Map) {
      for (final key in const [
        'image_url',
        'url',
        'image',
        'file',
        'path',
        'cover_url',
        'thumbnail_url',
        'thumbnail',
        'cover',
        'foto',
        'gambar',
      ]) {
        final raw = (item[key] ?? '').toString().trim();
        if (raw.isNotEmpty) return raw;
      }

      // Some responses wrap the object.
      final data = item['data'] ?? item['result'];
      if (data is Map || data is String) {
        return _extractUrl(data);
      }
    }

    return '';
  }

  static int _extractImageId(dynamic item) {
    if (item is! Map) return 0;
    final v = item['id'] ?? item['image_id'] ?? item['id_image'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static Exception _httpError(String action, Uri url, http.Response res) {
    final body = res.body;
    final looksHtml =
        body.trimLeft().startsWith('<!DOCTYPE html') ||
        body.trimLeft().startsWith('<html');
    final msg = looksHtml
        ? 'Respon HTML (mungkin endpoint salah / token invalid)'
        : body;
    return Exception('$action gagal (${res.statusCode})\n$url\n$msg');
  }

  static Future<http.MultipartFile> _multipartFileFromXFile({
    required String fieldName,
    required XFile file,
  }) async {
    final name = file.name.trim().isNotEmpty ? file.name.trim() : 'upload';
    final path = file.path.trim();

    // `MultipartFile.fromPath` relies on `dart:io`, which is unavailable on Web.
    // On Web we must send the bytes.
    if (!kIsWeb && path.isNotEmpty) {
      return http.MultipartFile.fromPath(fieldName, path, filename: name);
    }

    final bytes = await file.readAsBytes();
    return http.MultipartFile.fromBytes(fieldName, bytes, filename: name);
  }

  static Future<String?> getFirstImageUrl({
    required String token,
    required int kosId,
  }) async {
    try {
      final images = await getImages(token: token, kosId: kosId);
      // Use the first uploaded image as cover.
      // If IDs exist, assume lower ID = earlier upload.
      String? bestUrl;
      int bestId = 0;

      for (final it in images) {
        final raw = _extractUrl(it);
        if (raw.isEmpty) continue;

        final id = _extractImageId(it);
        if (id > 0) {
          if (bestId == 0 || id < bestId) {
            bestId = id;
            bestUrl = raw;
          }
        } else {
          // Keep list order as fallback.
          bestUrl ??= raw;
        }
      }

      return bestUrl;
    } catch (_) {
      return null;
    }
  }

  static Future<List<dynamic>> getImages({
    required String token,
    required int kosId,
  }) async {
    // UKK endpoint
    final url = Uri.parse(ApiConfig.ownerShowImagesUrl(kosId));
    final res = await http.get(
      url,
      headers: {'Content-Type': 'application/json', ..._headers(token)},
    );

    if (res.statusCode == 200) {
      if (res.body.trim().isEmpty) return const [];
      final decoded = jsonDecode(res.body);
      return _extractList(decoded);
    }

    // Fallback legacy endpoint
    final fallback = Uri.parse('${ApiConfig.baseUrl}/owner/kos/$kosId/images');
    final res2 = await http.get(
      fallback,
      headers: {'Content-Type': 'application/json', ..._headers(token)},
    );
    if (res2.statusCode != 200) return const [];
    if (res2.body.trim().isEmpty) return const [];
    final decoded2 = jsonDecode(res2.body);
    return _extractList(decoded2);
  }

  static Future<void> uploadImage({
    required String token,
    required int kosId,
    required XFile file,
  }) async {
    final url = Uri.parse(ApiConfig.ownerUploadImageUrl(kosId));
    final req = http.MultipartRequest('POST', url);
    req.headers.addAll(_headers(token));
    // UKK docs: field name is "file"
    req.files.add(await _multipartFileFromXFile(fieldName: 'file', file: file));
    final res = await req.send();
    if (res.statusCode == 200 || res.statusCode == 201) return;

    final body = await res.stream.bytesToString();
    throw Exception('Upload gagal (${res.statusCode})\n$url\n$body');
  }

  static Future<void> updateImage({
    required String token,
    required int imageId,
    required XFile file,
  }) async {
    final url = Uri.parse(ApiConfig.ownerUpdateImageUrl(imageId));
    final req = http.MultipartRequest('POST', url);
    req.headers.addAll(_headers(token));
    req.files.add(await _multipartFileFromXFile(fieldName: 'file', file: file));
    final res = await req.send();
    if (res.statusCode == 200 || res.statusCode == 201) return;

    final body = await res.stream.bytesToString();
    throw Exception('Update gagal (${res.statusCode})\n$url\n$body');
  }

  static Future<void> deleteImage({
    required String token,
    required int imageId,
  }) async {
    final url = Uri.parse(ApiConfig.ownerDeleteImageUrl(imageId));
    final res = await http.delete(url, headers: _headers(token));
    if (res.statusCode == 200 || res.statusCode == 204) return;

    // fallback legacy
    final fallback = Uri.parse('${ApiConfig.baseUrl}/owner/images/$imageId');
    final res2 = await http.delete(fallback, headers: _headers(token));
    if (res2.statusCode == 200 || res2.statusCode == 204) return;
    throw _httpError('Hapus image', url, res);
  }

  static Future<Map<String, dynamic>> detailImage({
    required String token,
    required int imageId,
  }) async {
    final url = Uri.parse(ApiConfig.ownerDetailImageUrl(imageId));
    final res = await http.get(
      url,
      headers: {'Content-Type': 'application/json', ..._headers(token)},
    );

    if (res.statusCode == 200) {
      if (res.body.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final data = decoded['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
        return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{'raw': res.body};
    }

    // fallback legacy
    final fallback = Uri.parse('${ApiConfig.baseUrl}/owner/images/$imageId');
    final res2 = await http.get(
      fallback,
      headers: {'Content-Type': 'application/json', ..._headers(token)},
    );
    if (res2.statusCode != 200) {
      throw _httpError('Detail image', url, res);
    }

    if (res2.body.trim().isEmpty) return <String, dynamic>{};
    final decoded2 = jsonDecode(res2.body);
    if (decoded2 is Map) {
      final data = decoded2['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(decoded2);
    }
    return <String, dynamic>{'raw': res2.body};
  }
}
