import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    const raw = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );

    // 10.0.2.2 hanya valid untuk Android emulator.
    // Di Flutter Web, ini harus diarahkan ke localhost (jika backend berjalan lokal).
    if (kIsWeb && raw.contains('10.0.2.2')) {
      return raw.replaceFirst('10.0.2.2', 'localhost');
    }

    return raw;
  }

  // Auth endpoints (UKK KOS backend)
  // Example: https://learn.smktelkom-mlg.sch.id/kos/api/login
  static const String authBaseUrl = String.fromEnvironment(
    'AUTH_BASE_URL',
    defaultValue: 'https://learn.smktelkom-mlg.sch.id/kos/api',
  );

  static String get authLoginUrl => '$authBaseUrl/login';
  static String get authRegisterUrl => '$authBaseUrl/register';

  // Reviews (UKK KOS backend)
  // Owner/admin review endpoints require Authorization + MakerID.
  static String ownerShowReviewsUrl(int kosId) =>
      '$authBaseUrl/admin/show_reviews/$kosId';
  static String ownerStoreReviewsUrl(int kosId) =>
      '$authBaseUrl/admin/store_reviews/$kosId';
  static String deleteReviewUrl(int reviewId) =>
      '$authBaseUrl/society/delete_review/$reviewId';

  // Master Kos (UKK KOS backend)
  static String ownerShowKosUrl({String? search}) {
    final q = (search ?? '').trim();
    if (q.isEmpty) return '$authBaseUrl/admin/show_kos';
    return '$authBaseUrl/admin/show_kos?search=$q';
  }

  static String ownerDetailKosUrl(int kosId) =>
      '$authBaseUrl/admin/detail_kos/$kosId';
  static String get ownerStoreKosUrl => '$authBaseUrl/admin/store_kos';
  static String ownerUpdateKosUrl(int kosId) =>
      '$authBaseUrl/admin/update_kos/$kosId';
  static String ownerDeleteKosUrl(int kosId) =>
      '$authBaseUrl/delete_kos/$kosId';

  // Facilities (UKK KOS backend)
  // Umumnya endpoint facilities untuk owner ada di prefix '/admin'.
  static String ownerShowFacilitiesUrl(int kosId) =>
      '$authBaseUrl/admin/show_facilities/$kosId';
  static String ownerStoreFacilityUrl(int kosId) =>
      '$authBaseUrl/admin/store_facility/$kosId';
  static String ownerUpdateFacilityUrl(int facilityId) =>
      '$authBaseUrl/admin/update_facility/$facilityId';
  static String ownerDetailFacilityUrl(int facilityId) =>
      '$authBaseUrl/admin/detail_facility/$facilityId';
  static String ownerDeleteFacilityUrl(int facilityId) =>
      '$authBaseUrl/admin/delete_facility/$facilityId';

  // Image Kos (UKK KOS backend)
  static String ownerShowImagesUrl(int kosId) =>
      '$authBaseUrl/admin/show_image/$kosId';
  static String ownerUploadImageUrl(int kosId) =>
      '$authBaseUrl/admin/upload_image/$kosId';
  static String ownerUpdateImageUrl(int imageId) =>
      '$authBaseUrl/admin/update_image/$imageId';
  static String ownerDetailImageUrl(int imageId) =>
      '$authBaseUrl/admin/detail_image/$imageId';
  static String ownerDeleteImageUrl(int imageId) =>
      '$authBaseUrl/admin/delete_image/$imageId';

  // Bookings (UKK KOS backend)
  // List bookings for owner/admin view
  static String ownerShowBookingsUrl({String? status, String? tgl}) {
    final qp = <String, String>{};
    final st = (status ?? '').trim();
    if (st.isNotEmpty && st.toLowerCase() != 'all') qp['status'] = st;
    final d = (tgl ?? '').trim();
    if (d.isNotEmpty) qp['tgl'] = d;

    final uri = Uri.parse('$authBaseUrl/admin/show_bookings');
    return uri.replace(queryParameters: qp.isEmpty ? null : qp).toString();
  }

  static String ownerUpdateStatusBookingUrl(int bookingId) =>
      '$authBaseUrl/admin/update_status_booking/$bookingId';

  // Society (UKK KOS backend)
  static String societyShowKosUrl({String? search}) {
    final q = (search ?? '').trim();
    if (q.isEmpty) return '$authBaseUrl/society/show_kos?search=';
    return '$authBaseUrl/society/show_kos?search=$q';
  }

  static String societyDetailKosUrl(int kosId) =>
      '$authBaseUrl/society/detail_kos/$kosId';
  static String get societyBookingUrl => '$authBaseUrl/society/booking';
  static String societyCetakNotaUrl(int bookingId) =>
      '$authBaseUrl/society/cetak_nota/$bookingId';

  // Society Reviews (UKK KOS backend)
  static String societyShowReviewsUrl(int kosId) =>
      '$authBaseUrl/society/show_reviews/$kosId';
  static String societyStoreReviewsUrl(int kosId) =>
      '$authBaseUrl/society/store_reviews/$kosId';

  static String societyShowBookingsUrl({String? status}) {
    final st = (status ?? '').trim();
    if (st.isEmpty || st.toLowerCase() == 'all') {
      // Some backends treat `status=` as an empty-status filter.
      // For "all", omit the query parameter.
      return '$authBaseUrl/society/show_bookings';
    }
    return '$authBaseUrl/society/show_bookings?status=$st';
  }

  static String get societyUpdateProfileUrl =>
      '$authBaseUrl/society/update_profile';

  static const String makerId = String.fromEnvironment(
    'MAKER_ID',
    defaultValue: '1',
  );

  // Reviews (society)
  static String get showReviewsSociety => '$baseUrl/society/reviews';
  static String get storeReviewsSociety => '$baseUrl/society/reviews';

  // Reviews (owner)
  static String get showReviewsOwner => '$baseUrl/owner/reviews';
  static String get storeReviewsOwner => '$baseUrl/owner/reviews';

  // Fallback / generic review endpoints
  static String get review => '$baseUrl/review';
  static String get deleteReview => '$baseUrl/review';

  // Facilities (owner)
  static String get showFacilities => '$baseUrl/owner/facilities';
  static String get addFacility => '$baseUrl/owner/facilities';
  static String get updateFacility => '$baseUrl/owner/facilities';
  static String get detailFacility => '$baseUrl/owner/facilities';
  static String get deleteFacility => '$baseUrl/owner/facilities';
}
