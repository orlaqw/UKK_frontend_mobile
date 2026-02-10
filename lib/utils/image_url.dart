import '../config/api_config.dart';

String normalizeImageUrl(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final lower = s.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return s;

  // Relative path -> prefix baseUrl
  if (s.startsWith('/')) {
    return '${ApiConfig.baseUrl}$s';
  }

  return '${ApiConfig.baseUrl}/$s';
}

/// Normalisasi URL image untuk backend UKK (learn.smktelkom-mlg.sch.id).
///
/// Banyak endpoint mengembalikan path relatif seperti `storage/...` atau `/storage/...`.
/// Fungsi ini membangun URL absolut berdasarkan root situs dari [ApiConfig.authBaseUrl],
/// misalnya `https://learn.smktelkom-mlg.sch.id/kos`.
String normalizeUkkImageUrl(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final lower = s.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return s;

  final auth = Uri.parse(ApiConfig.authBaseUrl);
  final origin = auth.origin;
  final firstSeg = auth.pathSegments.isNotEmpty ? auth.pathSegments.first : '';
  final siteBase = firstSeg.isEmpty ? origin : '$origin/$firstSeg';

  if (s.startsWith('/')) {
    // Jika sudah mengandung /kos/... cukup prefix origin.
    if (firstSeg.isNotEmpty && s.startsWith('/$firstSeg/')) {
      return '$origin$s';
    }
    return '$siteBase$s';
  }

  return '$siteBase/$s';
}
