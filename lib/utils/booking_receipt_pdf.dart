import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:koshunter6/utils/booking_pricing.dart';

class BookingReceiptPdf {
  static Future<Uint8List> build({
    required Map<String, dynamic> booking,
    required String? societyName,
    bool isOwnerReceipt = false,
  }) async {
    final doc = pw.Document();

    Map<String, dynamic> asStringKeyedMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) {
        final out = <String, dynamic>{};
        v.forEach((k, val) => out[k.toString()] = val);
        return out;
      }
      return <String, dynamic>{};
    }

    String asString(dynamic v) => (v == null) ? '' : v.toString();

    int? parseMoneyInt(dynamic v) {
      final s = asString(v).trim();
      if (s.isEmpty) return null;
      return BookingPricing.parseIntDigits(s);
    }

    DateTime? parseDate(dynamic v) {
      final s = asString(v).trim();
      if (s.isEmpty) return null;
      final direct = DateTime.tryParse(s);
      if (direct != null) {
        return DateTime(direct.year, direct.month, direct.day);
      }
      // Try YYYY-MM-DD
      final parts = s.split(RegExp(r'[-/]'));
      if (parts.length >= 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          return DateTime(y, m, d);
        }
      }
      return null;
    }

    String moneyText(int? v) {
      if (v == null) return '-';
      return BookingPricing.formatRupiahInt(v);
    }

    String firstNonEmpty(List<dynamic> values) {
      for (final v in values) {
        final s = asString(v).trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
      }
      return '';
    }

    List<String> extractFacilities(Map<String, dynamic> kosOrPayload) {
      final out = <String>[];

      void addFacility(dynamic v) {
        final s = asString(v).trim();
        if (s.isEmpty || s.toLowerCase() == 'null') return;

        // If backend returns a comma-separated string.
        if (s.contains(',') || s.contains(';')) {
          final parts = s.split(RegExp(r'[,;]'));
          for (final p in parts) {
            final t = p.trim();
            if (t.isEmpty) continue;
            if (!out.contains(t)) out.add(t);
          }
          return;
        }

        if (!out.contains(s)) out.add(s);
      }

      void addFromList(dynamic list) {
        if (list is! List) return;
        for (final it in list) {
          if (it is Map) {
            addFacility(
              it['facility_name'] ?? it['name'] ?? it['nama_fasilitas'],
            );
          } else {
            addFacility(it);
          }
        }
      }

      // Direct keys.
      for (final key in const [
        'facilities',
        'facility',
        'fasilitas',
        'facilities_kos',
        'facility_kos',
      ]) {
        final v = kosOrPayload[key];
        if (v is List) {
          addFromList(v);
        } else if (v is Map) {
          // Some APIs wrap list in {data: [...]}
          addFromList(
            v['data'] ?? v['items'] ?? v['facilities'] ?? v['facility'],
          );
        } else if (v is String) {
          addFacility(v);
        }
      }

      // Nested wrappers.
      for (final nestedKey in const ['kos', 'data', 'detail', 'result']) {
        final nested = kosOrPayload[nestedKey];
        if (nested is Map) {
          final nestedMap = asStringKeyedMap(nested);
          for (final key in const [
            'facilities',
            'facility',
            'fasilitas',
            'facilities_kos',
            'facility_kos',
          ]) {
            final v = nestedMap[key];
            if (v is List) {
              addFromList(v);
            } else if (v is Map) {
              addFromList(
                v['data'] ?? v['items'] ?? v['facilities'] ?? v['facility'],
              );
            } else if (v is String) {
              addFacility(v);
            }
          }
        }
      }

      return out;
    }

    pw.Widget infoRow(String label, String value, {bool boldLabel = true}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontWeight: boldLabel
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(value.trim().isEmpty ? '-' : value.trim()),
            ),
          ],
        ),
      );
    }

    final bookingMap = asStringKeyedMap(booking);
    final kos = asStringKeyedMap(bookingMap['kos']);
    final user = asStringKeyedMap(bookingMap['user']);
    final society = asStringKeyedMap(bookingMap['society']);

    final kosIdText = firstNonEmpty([kos['id'], bookingMap['kos_id']]);
    final societyIdText = firstNonEmpty([
      user['id'],
      society['id'],
      bookingMap['user_id'],
      bookingMap['id_user'],
      bookingMap['society_id'],
      bookingMap['id_society'],
    ]);
    final kosNameText = firstNonEmpty([
      kos['name'],
      kos['nama_kos'],
      bookingMap['kos_name'],
      bookingMap['name'],
    ]);
    final addressText = firstNonEmpty([
      kos['address'],
      kos['alamat'],
      bookingMap['address'],
      bookingMap['alamat'],
    ]);

    final typeText = firstNonEmpty([
      kos['gender'],
      kos['kos_gender'],
      kos['jenis_kos'],
      kos['type'],
      kos['kategori'],
      bookingMap['gender'],
      bookingMap['type'],
    ]);

    final monthlyInt = parseMoneyInt(
      firstNonEmpty([
        kos['price_per_month'],
        kos['pricePerMonth'],
        kos['monthly_price'],
        kos['price'],
        bookingMap['price_per_month'],
        bookingMap['price'],
      ]),
    );
    final dailyInt = (monthlyInt == null) ? null : (monthlyInt / 30.0).round();

    final startText = firstNonEmpty([
      bookingMap['start_date'],
      bookingMap['startDate'],
      bookingMap['tanggal_mulai'],
    ]);
    final endText = firstNonEmpty([
      bookingMap['end_date'],
      bookingMap['endDate'],
      bookingMap['tanggal_selesai'],
    ]);
    final statusText = firstNonEmpty([
      bookingMap['status'],
      bookingMap['booking_status'],
    ]);

    final startDate = parseDate(startText);
    final endDate = parseDate(endText);
    final durationDays = (startDate != null && endDate != null)
        ? BookingPricing.durationDaysInclusive(startDate, endDate)
        : null;

    final totalInt =
        parseMoneyInt(
          firstNonEmpty([
            bookingMap['total_price'],
            bookingMap['total_cost'],
            bookingMap['total_biaya'],
            bookingMap['total'],
          ]),
        ) ??
        ((monthlyInt != null && durationDays != null)
            ? BookingPricing.proRatedTotal(
                monthlyPrice: monthlyInt,
                days: durationDays,
              )
            : null);

    final facilities = <String>[]
      ..addAll(extractFacilities(kos))
      ..addAll(extractFacilities(bookingMap));
    final facilitiesText = facilities.isEmpty ? '-' : facilities.join(', ');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Bukti Pemesanan Kos',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'KOS Hunter',
                  style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 18),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 14),
                if (!isOwnerReceipt) ...[
                  infoRow('Nama Penyewa', (societyName ?? '').trim()),
                  infoRow('Nama Kos', kosNameText),
                  infoRow('Harga / bulan', moneyText(monthlyInt)),
                  infoRow(
                    'Harga / hari',
                    dailyInt == null ? '-' : '${moneyText(dailyInt)} (prorata)',
                  ),
                  infoRow('Tanggal Mulai', startText),
                  infoRow('Tanggal Selesai', endText),
                  infoRow('Status', statusText),
                  infoRow(
                    'Durasi',
                    durationDays == null ? '-' : '$durationDays hari',
                  ),
                  infoRow('Total Biaya', moneyText(totalInt)),
                ] else ...[
                  infoRow('Nama Kos', kosNameText),
                  infoRow('Harga / bulan', moneyText(monthlyInt)),
                  infoRow(
                    'Harga / hari',
                    dailyInt == null ? '-' : '${moneyText(dailyInt)} (prorata)',
                  ),
                  infoRow('Tanggal Mulai', startText),
                  infoRow('Tanggal Selesai', endText),
                  infoRow('Status', statusText),
                  infoRow(
                    'Durasi',
                    durationDays == null ? '-' : '$durationDays hari',
                  ),
                  infoRow('Total Biaya', moneyText(totalInt)),
                  infoRow('ID Society', societyIdText),
                  pw.SizedBox(height: 18),
                  pw.Text(
                    'Detail Kos',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  infoRow('ID Kos', kosIdText),
                  infoRow('Tipe', typeText.isEmpty ? '-' : typeText),
                ],
                if (!isOwnerReceipt) ...[
                  pw.SizedBox(height: 18),
                  pw.Text(
                    'Detail Kos',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  infoRow('ID Kos', kosIdText),
                  infoRow('Alamat', addressText),
                  infoRow('Tipe', typeText.isEmpty ? '-' : typeText),
                  infoRow('Fasilitas', facilitiesText, boldLabel: true),
                ],
                pw.SizedBox(height: 18),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Catatan: Bukti ini dihasilkan dari aplikasi.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }
}
