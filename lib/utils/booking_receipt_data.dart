import 'package:koshunter6/services/owner/owner_kos_service.dart';
import 'package:koshunter6/services/owner/owner_facility_service.dart';
import 'package:koshunter6/services/society/booking_service.dart';

class BookingReceiptData {
  static Map<String, dynamic> normalizeBooking(dynamic raw) {
    if (raw is Map) {
      final out = <String, dynamic>{};
      raw.forEach((key, value) {
        out[key.toString()] = value;
      });
      return out;
    }
    return <String, dynamic>{'raw': raw?.toString()};
  }

  static Future<Map<String, dynamic>> enrich({
    required dynamic booking,
    required String token,
    required bool isOwner,
  }) async {
    final base = normalizeBooking(booking);

    int? toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    }

    Map<String, dynamic>? asStringKeyedMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) {
        final out = <String, dynamic>{};
        v.forEach((k, val) => out[k.toString()] = val);
        return out;
      }
      return null;
    }

    final existingKos = asStringKeyedMap(base['kos']) ?? <String, dynamic>{};

    int? pickKosId() {
      // Booking payloads vary by endpoint; try common keys.
      final direct =
          toInt(base['kos_id']) ??
          toInt(base['id_kos']) ??
          toInt(base['kosId']) ??
          toInt(base['idKos']);
      if (direct != null) return direct;

      final fromKos =
          toInt(existingKos['id']) ??
          toInt(existingKos['kos_id']) ??
          toInt(existingKos['id_kos']);
      return fromKos;
    }

    final kosId = pickKosId();
    if (kosId == null || kosId <= 0) return base;

    bool isEmptyValue(dynamic v) {
      if (v == null) return true;
      if (v is String) {
        final s = v.trim().toLowerCase();
        return s.isEmpty || s == 'null';
      }
      if (v is List) return v.isEmpty;
      if (v is Map) return v.isEmpty;
      return false;
    }

    try {
        final detail = isOwner
          ? await OwnerKosService.detailKos(token: token, kosId: kosId)
          : await BookingService.getKosDetail(token: token, kosId: kosId);

      // Start with detail (it contains facilities/address/type), then overlay existing
      // only when existing provides a meaningful value (e.g., price/name from history).
      final mergedKos = <String, dynamic>{...detail};
      existingKos.forEach((k, v) {
        if (!isEmptyValue(v)) {
          mergedKos[k] = v;
        }
      });

      // UKK detail_kos biasanya sudah membawa fasilitas di 'kos_facilities'.
      // Untuk konsistensi, expose juga sebagai 'facilities' bila kosong.
      final facilitiesFromDetail =
          mergedKos['kos_facilities'] ??
          mergedKos['facilities'] ??
          mergedKos['facility'] ??
          mergedKos['fasilitas'] ??
          mergedKos['facilities_kos'] ??
          mergedKos['facility_kos'];
      if (!isEmptyValue(facilitiesFromDetail) && isEmptyValue(mergedKos['facilities'])) {
        mergedKos['facilities'] = facilitiesFromDetail;
      }

      // Owner detail endpoint sering tidak include fasilitas; fetch dari show_facilities.
      if (isOwner && isEmptyValue(mergedKos['facilities'])) {
        try {
          final facilities = await OwnerFacilityService.getFacilities(
            token: token,
            kosId: kosId,
          );
          if (!isEmptyValue(facilities)) {
            mergedKos['facilities'] = facilities;
          }
        } catch (_) {
          // best effort: nota tetap bisa dibuat tanpa fasilitas
        }
      }

      base['kos_id'] = kosId;
      base['kos'] = mergedKos;
      return base;
    } catch (_) {
      // If the detail fetch fails, keep the original booking map.
      base['kos_id'] = kosId;
      if (base['kos'] == null) base['kos'] = existingKos;
      return base;
    }
  }
}
