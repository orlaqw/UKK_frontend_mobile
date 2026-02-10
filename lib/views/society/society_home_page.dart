import 'package:flutter/material.dart';
import 'dart:convert';
import '../../utils/booking_pricing.dart';
import 'package:koshunter6/services/auth_service.dart';
import 'package:koshunter6/services/society/booking_service.dart';
import 'package:koshunter6/services/society/society_image_kos_service.dart';
import 'package:koshunter6/utils/image_url.dart';
import 'package:koshunter6/views/society/bookings/booking_receipt_preview_page.dart';
import 'package:koshunter6/views/society/bookings/kos_list_page.dart';
import 'package:koshunter6/views/society/reviews/society_all_reviews_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koshunter6/widgets/app_gradient_scaffold.dart';
import 'package:koshunter6/widgets/booking_notification_dialog.dart';

class SocietyHomePage extends StatefulWidget {
  const SocietyHomePage({super.key});

  @override
  State<SocietyHomePage> createState() => _SocietyHomePageState();
}

class _SocietyHomePageState extends State<SocietyHomePage> {
  static const Color _accent = Color(0xFF7D86BF);

  late Future<String?> _userNameFuture;
  late Future<_SocietyHomeData> _homeFuture;
  final Set<String> _promptedBookingKeysThisSession = {};
  final Set<String> _promptedRejectedKeysThisSession = {};
  final Set<String> _promptedAcceptedKeysThisSession = {};
  bool _endPromptScheduled = false;
  bool _endPromptShowing = false;
  bool _rejectPromptScheduled = false;
  bool _rejectPromptShowing = false;
  bool _acceptPromptScheduled = false;
  bool _acceptPromptShowing = false;

  final Map<int, Future<String?>> _thumbFutureByKosId = {};

  Future<String?> _thumbFuture({required int kosId, required String token}) {
    return _thumbFutureByKosId.putIfAbsent(
      kosId,
      () => SocietyImageKosService.getFirstImageUrl(token: token, kosId: kosId),
    );
  }

  List<_PopularKosItem> _popularKosFromBookings(List<_BookingItem> bookings) {
    final counts = <int, _PopularKosItem>{};

    bool include(String status) {
      final s = status.trim().toLowerCase();
      if (s.isEmpty) return true;
      // Jangan hitung booking yang jelas batal/ditolak.
      if (s.contains('cancel') || s.contains('batal')) return false;
      if (s.contains('reject') || s.contains('tolak')) return false;
      return true;
    }

    for (final b in bookings) {
      final kosId = b.kosId;
      if (kosId == null || kosId == 0) continue;
      if (!include(b.status)) continue;
      final existing = counts[kosId];
      if (existing == null) {
        counts[kosId] = _PopularKosItem(
          kosId: kosId,
          kosName: b.kosName,
          imageRawUrl: (b.imageRawUrl ?? '').trim().isEmpty
              ? null
              : b.imageRawUrl,
          count: 1,
        );
      } else {
        counts[kosId] = existing.copyWith(
          count: existing.count + 1,
          kosName: existing.kosName.isNotEmpty ? existing.kosName : b.kosName,
          imageRawUrl: (existing.imageRawUrl ?? '').trim().isNotEmpty
              ? existing.imageRawUrl
              : ((b.imageRawUrl ?? '').trim().isEmpty ? null : b.imageRawUrl),
        );
      }
    }

    final list = counts.values.toList();
    list.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return a.kosName.toLowerCase().compareTo(b.kosName.toLowerCase());
    });

    return list.take(5).toList();
  }

  @override
  void initState() {
    super.initState();
    _userNameFuture = AuthService.getUserName();

    _homeFuture = _loadHome();
    _scheduleHomePrompts(_homeFuture, once: true);
  }

  void _scheduleHomePrompts(
    Future<_SocietyHomeData> future, {
    required bool once,
  }) {
    future
        .then((data) {
          if (!mounted) return;
          if (once &&
              _endPromptScheduled &&
              _rejectPromptScheduled &&
              _acceptPromptScheduled) {
            return;
          }
          if (once) {
            _endPromptScheduled = true;
            _rejectPromptScheduled = true;
            _acceptPromptScheduled = true;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            () async {
              await _maybePromptAcceptedBooking(data);
              await _maybePromptRejectedBooking(data);
              await _maybePromptEndedBooking(data);
            }();
          });
        })
        .catchError((_) {
          // Ignore, error akan ditangani oleh FutureBuilder.
        });
  }

  Future<void> _refreshHome() async {
    final next = _loadHome();
    setState(() {
      _homeFuture = next;
    });
    _scheduleHomePrompts(next, once: false);
    await next;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _priceFromKosMap(Map kos) {
    final candidates = <dynamic>[
      kos['price_per_month'],
      kos['pricePerMonth'],
      kos['monthly_price'],
      kos['price'],
      kos['rent_price'],
      kos['harga_per_bulan'],
      kos['harga'],
      kos['biaya'],
    ];

    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return '';
  }

  DateTime? _parseDate(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty) return null;
    // backend biasanya pakai YYYY-MM-DD
    return DateTime.tryParse(s);
  }

  DateTime? _parseDateTime(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  bool _looksLikeInvalidToken(dynamic error) {
    final s = error.toString().toLowerCase();
    return s.contains('401') ||
        (s.contains('token') &&
            (s.contains('invalid') || s.contains('tidak ditemukan')));
  }

  int _compareBookingRecency(_BookingItem a, _BookingItem b) {
    final aUpdated = a.updatedAt;
    final bUpdated = b.updatedAt;
    if (aUpdated != null || bUpdated != null) {
      final ad = aUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = bUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
      final c = bd.compareTo(ad);
      if (c != 0) return c;
    }

    final aCreated = a.createdAt;
    final bCreated = b.createdAt;
    if (aCreated != null || bCreated != null) {
      final ad = aCreated ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = bCreated ?? DateTime.fromMillisecondsSinceEpoch(0);
      final c = bd.compareTo(ad);
      if (c != 0) return c;
    }

    final aId = a.bookingId ?? 0;
    final bId = b.bookingId ?? 0;
    final byId = bId.compareTo(aId);
    if (byId != 0) return byId;

    final ad = a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bd = b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byStart = bd.compareTo(ad);
    if (byStart != 0) return byStart;

    final ae = a.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final be = b.endDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    return be.compareTo(ae);
  }

  List<_BookingItem> _dedupeBookings(List<_BookingItem> input) {
    final byKey = <String, _BookingItem>{};

    for (final b in input) {
      // Gunakan composite key (kos+periode) agar duplikat backend dengan bookingId berbeda
      // tidak memunculkan prompt berulang.
      final key = b.compositeKey;

      final existing = byKey[key];
      // If equal recency (compare==0), prefer the later item in the list.
      if (existing == null || _compareBookingRecency(b, existing) <= 0) {
        // existing lebih baru jika compare < 0, jadi kita ambil yang lebih baru.
        byKey[key] = b;
      }
    }

    final out = byKey.values.toList();
    out.sort(_compareBookingRecency);
    return out;
  }

  Future<_SocietyHomeData> _loadHome() async {
    final token = await AuthService.getToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Token tidak ditemukan');
    }

    // Local hint to prioritize just-created booking.
    int? hintedKosId;
    String hintedStart = '';
    String hintedEnd = '';
    DateTime? hintedCreatedAt;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHint =
          (prefs.getString('society_last_created_booking_hint_v1') ?? '')
              .trim();
      if (rawHint.isNotEmpty) {
        final decoded = jsonDecode(rawHint);
        if (decoded is Map) {
          hintedKosId = _toInt(
            decoded['kos_id'] ?? decoded['id_kos'] ?? decoded['kosId'],
          );
          hintedStart = _asString(decoded['start_date']).trim();
          hintedEnd = _asString(decoded['end_date']).trim();
          hintedCreatedAt = _parseDateTime(decoded['created_at_local']);
        }
      }
    } catch (_) {
      // ignore
    }

    final raw = await BookingService.getBookingHistory(
      token: token,
      status: 'all',
    );

    // Fallback resolver: beberapa backend tidak mengirim kos_id dengan benar.
    // Kita coba petakan nama kos -> id dari list kos society.
    final kosList = await BookingService.showKos(token: token);
    final kosIds = <int>{};
    final kosIdByName = <String, int>{};
    final kosPriceById = <int, String>{};
    for (final k in kosList) {
      if (k is! Map) continue;
      final id = _toInt(k['id']);
      if (id == null || id == 0) continue;
      kosIds.add(id);
      final price = _priceFromKosMap(k).trim();
      if (price.isNotEmpty) kosPriceById[id] = price;
      final name = _asString(k['name'] ?? k['nama_kos'] ?? k['nama']).trim();
      if (name.isNotEmpty) {
        kosIdByName[name.toLowerCase()] = id;
      }
    }
    final items = <_BookingItem>[];

    for (final it in raw) {
      if (it is! Map) continue;
      final bookingMap = (it['booking'] is Map) ? (it['booking'] as Map) : null;

      final bookingId = _toInt(
        it['id'] ??
            it['booking_id'] ??
            it['id_booking'] ??
            it['bookingId'] ??
            it['idBooking'] ??
            bookingMap?['id'] ??
            bookingMap?['booking_id'] ??
            bookingMap?['id_booking'] ??
            bookingMap?['bookingId'] ??
            bookingMap?['idBooking'],
      );

      final kosRaw = it['kos'] ?? bookingMap?['kos'];
      final kosMap = (kosRaw is Map) ? kosRaw : null;

      // Beberapa response booking memakai nama field yang tidak konsisten.
      // Prioritas: kos.id (jika ada) -> kos_id / id_kos -> kos (jika berupa angka).
      final kosIdFromKos = _toInt(kosMap?['id']);
      final kosIdFromFields = _toInt(
        it['kos_id'] ?? it['id_kos'] ?? it['kosId'] ?? it['idKos'],
      );
      final kosIdFromKosRaw = _toInt(kosRaw);

      var kosId = kosIdFromKos ?? kosIdFromFields ?? kosIdFromKosRaw;
      final kosName = _asString(
        kosMap?['name'] ??
            kosMap?['nama_kos'] ??
            kosMap?['nama'] ??
            it['kos_name'] ??
            it['nama_kos'] ??
            it['name'] ??
            'Kos',
      ).trim();

      final imageRaw = _asString(
        kosMap?['image_url'] ??
            kosMap?['cover_url'] ??
            kosMap?['thumbnail_url'] ??
            kosMap?['image'] ??
            kosMap?['cover'] ??
            kosMap?['thumbnail'] ??
            kosMap?['photo'] ??
            kosMap?['gambar'] ??
            it['image_url'] ??
            it['cover_url'] ??
            it['thumbnail_url'],
      ).trim();

      // Jika kosId tidak valid / tidak ada di list kos, coba cari via nama kos.
      if (kosId == null || !kosIds.contains(kosId)) {
        final resolved = kosIdByName[kosName.toLowerCase()];
        if (resolved != null) kosId = resolved;
      }

      final kosPrice = () {
        final direct = _priceFromKosMap(kosMap ?? const {}).trim();
        if (direct.isNotEmpty) return direct;
        final kid = kosId;
        if (kid != null) return (kosPriceById[kid] ?? '').trim();
        return '';
      }();

      final startRaw = _asString(
        it['start_date'] ??
            it['tanggal_mulai'] ??
            bookingMap?['start_date'] ??
            bookingMap?['tanggal_mulai'],
      ).trim();
      final endRaw = _asString(
        it['end_date'] ??
            it['tanggal_selesai'] ??
            bookingMap?['end_date'] ??
            bookingMap?['tanggal_selesai'],
      ).trim();
      final start = _parseDate(startRaw);
      final end = _parseDate(endRaw);
      final status = _asString(
        it['status'] ??
            it['booking_status'] ??
            bookingMap?['status'] ??
            bookingMap?['booking_status'] ??
            '',
      ).trim();

      final updatedAt = _parseDateTime(
        it['updated_at'] ??
            it['updatedAt'] ??
            it['updated'] ??
            it['tanggal_update'] ??
            bookingMap?['updated_at'] ??
            bookingMap?['updatedAt'] ??
            bookingMap?['updated'],
      );
      final createdAt = _parseDateTime(
        it['created_at'] ??
            it['createdAt'] ??
            it['created'] ??
            it['tanggal_buat'] ??
            bookingMap?['created_at'] ??
            bookingMap?['createdAt'] ??
            bookingMap?['created'],
      );

      // If this matches the last created booking in this device, boost recency.
      final matchesHint =
          hintedCreatedAt != null &&
          hintedKosId != null &&
          hintedKosId != 0 &&
          kosId != null &&
          kosId == hintedKosId &&
          hintedStart.isNotEmpty &&
          hintedEnd.isNotEmpty &&
          startRaw == hintedStart &&
          endRaw == hintedEnd;

      final boostedUpdatedAt = matchesHint ? hintedCreatedAt : updatedAt;
      final boostedCreatedAt = matchesHint ? hintedCreatedAt : createdAt;

      items.add(
        _BookingItem(
          bookingId: bookingId,
          kosId: kosId,
          kosName: kosName.isEmpty ? 'Kos' : kosName,
          imageRawUrl: imageRaw.isEmpty ? null : imageRaw,
          priceRaw: kosPrice,
          startDateRaw: startRaw,
          endDateRaw: endRaw,
          startDate: start,
          endDate: end,
          status: status,
          updatedAt: boostedUpdatedAt,
          createdAt: boostedCreatedAt,
        ),
      );
    }

    final uniqueItems = _dedupeBookings(items);
    return _SocietyHomeData(token: token, bookings: uniqueItems);
  }

  bool _isTerminalStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('done') ||
        s.contains('finish') ||
        s.contains('selesai') ||
        s.contains('complete') ||
        s.contains('cancel') ||
        s.contains('batal') ||
        s.contains('reject') ||
        s.contains('tolak');
  }

  bool _isPendingStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return true;
    return s.contains('pending') ||
        s.contains('wait') ||
        s.contains('menunggu') ||
        s.contains('request') ||
        s.contains('diajukan');
  }

  bool _isRejectedStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('reject') || s.contains('tolak');
  }

  bool _isAcceptedStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('accept') ||
        s.contains('accepted') ||
        s.contains('approve') ||
        s.contains('approved') ||
        s.contains('disetujui') ||
        s.contains('terima') ||
        s.contains('diterima');
  }

  bool _isPendingRequestStatus(String status) {
    if (!_isPendingStatus(status)) return false;
    if (_isAcceptedStatus(status)) return false;
    if (_isRejectedStatus(status)) return false;
    if (_isTerminalStatus(status)) return false;
    return true;
  }

  bool _isActiveBooking(_BookingItem b) {
    if (b.kosId == null || b.kosId == 0) return false;
    if (b.startDate == null || b.endDate == null) return false;
    if (_isTerminalStatus(b.status)) return false;
    // Booking aktif hanya yang sudah disetujui/diterima.
    // Ini otomatis menyembunyikan booking yang ditolak dari section "Booking Aktif".
    if (!_isAcceptedStatus(b.status)) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      b.startDate!.year,
      b.startDate!.month,
      b.startDate!.day,
    );
    final end = DateTime(b.endDate!.year, b.endDate!.month, b.endDate!.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  bool _isEndedBooking(_BookingItem b) {
    if (_isPendingStatus(b.status)) return false;
    if (b.endDate == null) return false;
    if (_isTerminalStatus(b.status)) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(b.endDate!.year, b.endDate!.month, b.endDate!.day);
    return today.isAfter(end);
  }

  Future<bool> _isAcceptPromptDismissed({required int bookingId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(
          'society_booking_accept_prompt_dismissed_$bookingId',
        ) ??
        false;
  }

  Future<void> _setAcceptPromptDismissed({required int bookingId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'society_booking_accept_prompt_dismissed_$bookingId',
      true,
    );
  }

  String _acceptPromptCompositeKey(_BookingItem b) {
    return 'society_booking_accept_prompt_dismissed_${b.compositeKey}';
  }

  String _acceptPromptLegacyCompositeKey(_BookingItem b) {
    return 'society_booking_accept_prompt_dismissed_k${b.kosId}_${b.startDateText}_${b.endDateText}';
  }

  Future<bool> _isAcceptPromptDismissedForBooking(_BookingItem b) async {
    final prefs = await SharedPreferences.getInstance();
    final compositeKey = _acceptPromptCompositeKey(b);
    final compositeDismissed = prefs.getBool(compositeKey) ?? false;
    if (compositeDismissed) return true;

    final legacyDismissed =
        prefs.getBool(_acceptPromptLegacyCompositeKey(b)) ?? false;
    if (legacyDismissed) return true;

    final bookingId = b.bookingId;
    if (bookingId == null) return false;
    return _isAcceptPromptDismissed(bookingId: bookingId);
  }

  Future<void> _setAcceptPromptDismissedForBooking(_BookingItem b) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_acceptPromptCompositeKey(b), true);
    await prefs.setBool(_acceptPromptLegacyCompositeKey(b), true);
    final bookingId = b.bookingId;
    if (bookingId != null) {
      await _setAcceptPromptDismissed(bookingId: bookingId);
    }
  }

  Future<bool> _isEndPromptDismissed({required int bookingId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('society_booking_end_prompt_dismissed_$bookingId') ??
        false;
  }

  Future<void> _setEndPromptDismissed({required int bookingId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'society_booking_end_prompt_dismissed_$bookingId',
      true,
    );
  }

  Future<bool> _isRejectPromptDismissed({required int bookingId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(
          'society_booking_reject_prompt_dismissed_$bookingId',
        ) ??
        false;
  }

  Future<void> _setRejectPromptDismissed({required int bookingId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'society_booking_reject_prompt_dismissed_$bookingId',
      true,
    );
  }

  String _rejectPromptCompositeKey(_BookingItem b) {
    return 'society_booking_reject_prompt_dismissed_${b.compositeKey}';
  }

  String _rejectPromptLegacyCompositeKey(_BookingItem b) {
    return 'society_booking_reject_prompt_dismissed_k${b.kosId}_${b.startDateText}_${b.endDateText}';
  }

  Future<bool> _isRejectPromptDismissedForBooking(_BookingItem b) async {
    final prefs = await SharedPreferences.getInstance();
    final compositeKey = _rejectPromptCompositeKey(b);
    final compositeDismissed = prefs.getBool(compositeKey) ?? false;
    if (compositeDismissed) return true;

    final legacyDismissed =
        prefs.getBool(_rejectPromptLegacyCompositeKey(b)) ?? false;
    if (legacyDismissed) return true;

    final bookingId = b.bookingId;
    if (bookingId == null) return false;
    return _isRejectPromptDismissed(bookingId: bookingId);
  }

  Future<void> _setRejectPromptDismissedForBooking(_BookingItem b) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rejectPromptCompositeKey(b), true);
    await prefs.setBool(_rejectPromptLegacyCompositeKey(b), true);
    final bookingId = b.bookingId;
    if (bookingId != null) {
      await _setRejectPromptDismissed(bookingId: bookingId);
    }
  }

  String _endPromptCompositeKey(_BookingItem b) {
    return 'society_booking_end_prompt_dismissed_${b.compositeKey}';
  }

  String _endPromptLegacyCompositeKey(_BookingItem b) {
    return 'society_booking_end_prompt_dismissed_k${b.kosId}_${b.startDateText}_${b.endDateText}';
  }

  Future<bool> _isEndPromptDismissedForBooking(_BookingItem b) async {
    final prefs = await SharedPreferences.getInstance();

    // Prefer composite key to avoid repeated prompts when backend returns duplicates
    // with different booking IDs.
    final compositeKey = _endPromptCompositeKey(b);
    final compositeDismissed = prefs.getBool(compositeKey) ?? false;
    if (compositeDismissed) return true;

    final legacyDismissed =
        prefs.getBool(_endPromptLegacyCompositeKey(b)) ?? false;
    if (legacyDismissed) return true;

    // Backward compatibility: check older key by booking id if present.
    final bookingId = b.bookingId;
    if (bookingId == null) return false;
    return _isEndPromptDismissed(bookingId: bookingId);
  }

  Future<void> _setEndPromptDismissedForBooking(_BookingItem b) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_endPromptCompositeKey(b), true);
    await prefs.setBool(_endPromptLegacyCompositeKey(b), true);
    final bookingId = b.bookingId;
    if (bookingId != null) {
      await _setEndPromptDismissed(bookingId: bookingId);
    }
  }

  Future<void> _maybePromptEndedBooking(_SocietyHomeData data) async {
    if (_endPromptShowing || _rejectPromptShowing || _acceptPromptShowing)
      return;
    // Cari 1 booking yang sudah lewat end_date dan belum pernah diprompt
    for (final b in data.bookings) {
      final bookingId = b.bookingId;
      final kosId = b.kosId;
      if (bookingId == null || kosId == null) continue;
      final sessionKey = _endPromptCompositeKey(b);
      if (_promptedBookingKeysThisSession.contains(sessionKey)) continue;
      if (!_isEndedBooking(b)) continue;
      if (await _isEndPromptDismissedForBooking(b)) continue;

      _promptedBookingKeysThisSession.add(sessionKey);
      if (!mounted) return;

      _endPromptShowing = true;
      _EndChoice? choice;
      try {
        choice = await showDialog<_EndChoice>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => BookingNotificationDialog(
            accentColor: _accent,
            title: 'Masa kos sudah lewat',
            message:
                'Booking untuk ${b.kosName} sudah lewat tanggal selesai.\n\n'
                'Ingin melanjutkan atau akhiri booking?',
            leftLabel: 'Akhiri',
            onLeftPressed: () => Navigator.pop(ctx, _EndChoice.finish),
            rightLabel: 'Lanjutkan',
            onRightPressed: () => Navigator.pop(ctx, _EndChoice.extend),
          ),
        );
      } finally {
        _endPromptShowing = false;
      }

      if (choice == null) return;

      await _setEndPromptDismissedForBooking(b);
      if (!mounted) return;

      if (choice == _EndChoice.extend) {
        Navigator.pushNamed(
          context,
          '/booking',
          arguments: {'kosId': kosId, 'token': data.token},
        );
      } else {
        Navigator.pushNamed(
          context,
          '/booking-history',
          arguments: {'token': data.token, 'status': 'all'},
        );
      }

      return;
    }
  }

  Future<void> _maybePromptRejectedBooking(_SocietyHomeData data) async {
    if (_rejectPromptShowing || _endPromptShowing || _acceptPromptShowing)
      return;

    for (final b in data.bookings) {
      final kosId = b.kosId;
      if (kosId == null) continue;
      if (!_isRejectedStatus(b.status)) continue;

      final sessionKey = _rejectPromptCompositeKey(b);
      if (_promptedRejectedKeysThisSession.contains(sessionKey)) continue;
      if (await _isRejectPromptDismissedForBooking(b)) continue;

      _promptedRejectedKeysThisSession.add(sessionKey);
      if (!mounted) return;

      _rejectPromptShowing = true;
      bool? goHistory;
      try {
        goHistory = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => BookingNotificationDialog(
            accentColor: _accent,
            title: 'Booking ditolak',
            message:
                'Booking untuk ${b.kosName} ditolak oleh owner.\n\n'
                'Periode: ${b.startDateText} - ${b.endDateText}',
            leftLabel: 'Tutup',
            onLeftPressed: () => Navigator.pop(ctx, false),
            rightLabel: 'Lihat riwayat',
            onRightPressed: () => Navigator.pop(ctx, true),
          ),
        );
      } finally {
        _rejectPromptShowing = false;
      }

      await _setRejectPromptDismissedForBooking(b);
      if (!mounted) return;

      if (goHistory == true) {
        Navigator.pushNamed(
          context,
          '/booking-history',
          arguments: {'token': data.token, 'status': 'all'},
        );
      }

      return;
    }
  }

  Future<void> _maybePromptAcceptedBooking(_SocietyHomeData data) async {
    if (_acceptPromptShowing || _rejectPromptShowing || _endPromptShowing)
      return;

    for (final b in data.bookings) {
      final kosId = b.kosId;
      if (kosId == null) continue;
      if (!_isAcceptedStatus(b.status)) continue;
      if (_isTerminalStatus(b.status)) continue;

      final sessionKey = _acceptPromptCompositeKey(b);
      if (_promptedAcceptedKeysThisSession.contains(sessionKey)) continue;
      if (await _isAcceptPromptDismissedForBooking(b)) continue;

      _promptedAcceptedKeysThisSession.add(sessionKey);
      if (!mounted) return;

      _acceptPromptShowing = true;
      bool? goDetail;
      try {
        goDetail = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => BookingNotificationDialog(
            accentColor: _accent,
            title: 'Booking diterima',
            message:
                'Booking untuk ${b.kosName} sudah diterima oleh owner.\n\n'
                'Periode: ${b.startDateText} - ${b.endDateText}',
            leftLabel: 'Tutup',
            onLeftPressed: () => Navigator.pop(ctx, false),
            rightLabel: 'Lihat detail',
            onRightPressed: () => Navigator.pop(ctx, true),
          ),
        );
      } finally {
        _acceptPromptShowing = false;
      }

      await _setAcceptPromptDismissedForBooking(b);
      if (!mounted) return;

      if (goDetail == true) {
        Navigator.pushNamed(
          context,
          '/booking',
          arguments: {'kosId': kosId, 'token': data.token},
        );
      }

      return;
    }
  }

  String _bookingStatusLabel(_BookingItem b) {
    if (_isRejectedStatus(b.status)) return 'Ditolak';
    if (_isAcceptedStatus(b.status)) return 'Diterima';
    if (_isPendingRequestStatus(b.status)) return 'Menunggu persetujuan';
    final raw = b.status.trim();
    return raw.isEmpty ? '-' : raw;
  }

  Widget _buildBookingStatusCard(_SocietyHomeData data) {
    final cardBorder = Color.lerp(_accent, Colors.white, 0.35)!;
    final pendingBg = Color.lerp(Colors.white, _accent, 0.12)!;
    final acceptedBg = Color.lerp(Colors.white, Colors.green, 0.12)!;
    final rejectedBg = Color.lerp(Colors.white, Colors.redAccent, 0.10)!;

    final pending = data.bookings
        .where((b) => _isPendingRequestStatus(b.status))
        .toList();
    final accepted = data.bookings
        .where(
          (b) => _isAcceptedStatus(b.status) && !_isTerminalStatus(b.status),
        )
        .toList();
    final rejected = data.bookings
        .where((b) => _isRejectedStatus(b.status))
        .toList();

    // Always keep newest changes first.
    pending.sort(_compareBookingRecency);
    accepted.sort(_compareBookingRecency);
    rejected.sort(_compareBookingRecency);

    if (pending.isEmpty && accepted.isEmpty && rejected.isEmpty) {
      return const SizedBox.shrink();
    }

    final preview = <_BookingItem>[...pending, ...accepted, ...rejected];
    preview.sort(_compareBookingRecency);

    final shown = preview.take(3).toList();

    IconData leadingIcon(_BookingItem b) {
      if (_isRejectedStatus(b.status)) return Icons.cancel_outlined;
      if (_isAcceptedStatus(b.status)) return Icons.check_circle_outline;
      return Icons.hourglass_top_rounded;
    }

    Color badgeColor(_BookingItem b) {
      if (_isRejectedStatus(b.status)) return Colors.redAccent;
      if (_isAcceptedStatus(b.status)) return Colors.green;
      return Theme.of(context).colorScheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Status Booking',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _refreshHome,
                    icon: const Icon(Icons.refresh, color: _accent),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/booking-history',
                        arguments: {'token': data.token, 'status': 'all'},
                      );
                    },
                    style: TextButton.styleFrom(foregroundColor: _accent),
                    child: const Text(
                      'Lihat riwayat',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    backgroundColor: pendingBg,
                    side: BorderSide(color: cardBorder),
                    avatar: const Icon(
                      Icons.hourglass_top_rounded,
                      size: 18,
                      color: _accent,
                    ),
                    label: Text('Menunggu: ${pending.length}'),
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                  Chip(
                    backgroundColor: acceptedBg,
                    side: BorderSide(color: cardBorder),
                    avatar: const Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Colors.green,
                    ),
                    label: Text('Diterima: ${accepted.length}'),
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                    ),
                  ),
                  Chip(
                    backgroundColor: rejectedBg,
                    side: BorderSide(color: cardBorder),
                    avatar: const Icon(
                      Icons.cancel_outlined,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    label: Text('Ditolak: ${rejected.length}'),
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
              if (shown.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 16),
                ...shown.map(
                  (b) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: (b.kosId == null || b.kosId == 0)
                        ? Icon(leadingIcon(b))
                        : _BookingStatusThumb(
                            rawUrl: b.imageRawUrl,
                            token: data.token,
                            kosId: b.kosId!,
                            thumbFuture: _thumbFuture,
                            badgeIcon: leadingIcon(b),
                            badgeColor: badgeColor(b),
                          ),
                    title: Text(b.kosName),
                    subtitle: Text(() {
                      final start = b.startDate;
                      final end = b.endDate;
                      final int? days = (start == null || end == null)
                          ? null
                          : BookingPricing.durationDaysInclusive(start, end);
                      final monthly = BookingPricing.parseIntDigits(b.priceRaw);
                      final total = (monthly != null && days != null)
                          ? BookingPricing.proRatedTotal(
                              monthlyPrice: monthly,
                              days: days,
                            )
                          : null;
                      final totalText = (total == null)
                          ? ''
                          : BookingPricing.formatRupiahInt(total);

                      final base =
                          '${_bookingStatusLabel(b)}\n${b.startDateText} - ${b.endDateText}';
                      if (totalText.isEmpty) return base;
                      return '$base\nTotal: $totalText';
                    }()),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right, color: _accent),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookingReceiptPreviewPage(
                            booking: b.toReceiptBookingMap(),
                            token: data.token,
                            isOwner: false,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BookingNotificationDialog(
        accentColor: _accent,
        title: 'Konfirmasi logout',
        message: 'Yakin ingin logout?',
        leftLabel: 'Batal',
        onLeftPressed: () => Navigator.pop(ctx, false),
        rightLabel: 'Logout',
        onRightPressed: () => Navigator.pop(ctx, true),
      ),
    );

    if (confirmed != true) return;
    await AuthService.logout();
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _openUpdateProfile(BuildContext context) async {
    final result = await Navigator.pushNamed(context, '/update-profile');

    setState(() {
      _userNameFuture = AuthService.getUserName();
    });

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile berhasil diperbarui')),
      );
    }
  }

  Future<void> _openBookingHistory(BuildContext context) async {
    final token = await AuthService.getToken();
    if (!context.mounted) return;

    final t = (token ?? '').trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Token tidak ditemukan')));
      return;
    }

    Navigator.pushNamed(
      context,
      '/booking-history',
      arguments: {'token': t, 'status': 'all'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBorder = Color.lerp(_accent, Colors.white, 0.35)!;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget quickAction({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.78),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.95),
              ),
            ],
          ),
        ),
      );
    }

    final elevatedStyle = ElevatedButton.styleFrom(
      backgroundColor: _accent,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: Colors.white,
          foregroundColor: _accent,
          surfaceTintColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      child: AppGradientScaffold(
        title: 'Home Society',
        showBack: false,
        backgroundGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE9ECFF), Color(0xFF9CA6DB), Color(0xFF7D86BF)],
          stops: [0.0, 0.55, 1.0],
        ),
        actions: [
          IconButton(
            tooltip: 'Update Profile',
            icon: const Icon(Icons.person),
            onPressed: () => _openUpdateProfile(context),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
        child: RefreshIndicator(
          color: _accent,
          backgroundColor: Colors.white,
          onRefresh: _refreshHome,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              FutureBuilder<String?>(
                future: _userNameFuture,
                builder: (context, snapshot) {
                  final name = (snapshot.data ?? '').trim();
                  final displayName = name.isEmpty ? 'Society' : name;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selamat datang, $displayName',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: _accent,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: quickAction(
                            icon: Icons.book_online,
                            title: 'Booking',
                            subtitle: 'Cari & booking kos',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SocietyKosListPage(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: quickAction(
                            icon: Icons.reviews,
                            title: 'Review',
                            subtitle: 'Lihat ulasan kos',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SocietyAllReviewsPage(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: quickAction(
                        icon: Icons.history,
                        title: 'History',
                        subtitle: 'Riwayat booking',
                        onTap: () => _openBookingHistory(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<_SocietyHomeData>(
                future: _homeFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_accent),
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    if (_looksLikeInvalidToken(snapshot.error)) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Sesi kamu sudah habis.\nSilakan login ulang.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                style: elevatedStyle,
                                onPressed: () async {
                                  await AuthService.logout();
                                  if (!context.mounted) return;
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    '/login',
                                    (route) => false,
                                  );
                                },
                                child: const Text(
                                  'Login ulang',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Gagal memuat booking\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    );
                  }

                  final data = snapshot.data;
                  if (data == null) return const SizedBox.shrink();

                  final active = data.bookings.where(_isActiveBooking).toList();
                  active.sort(_compareBookingRecency);
                  final statusCard = _buildBookingStatusCard(data);
                  final hasStatusCard = statusCard is! SizedBox;

                  if (!hasStatusCard && active.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      statusCard,
                      if (active.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.72),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: const Text(
                                          'Booking Aktif',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Refresh',
                                    onPressed: _refreshHome,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      side: BorderSide(color: _accent),
                                      shape: const CircleBorder(),
                                    ),
                                    icon: const Icon(
                                      Icons.refresh,
                                      color: _accent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ...active.map(
                                (b) => Card(
                                  elevation: 0,
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: cardBorder),
                                  ),
                                  child: ListTile(
                                    leading: (b.kosId == null || b.kosId == 0)
                                        ? const Icon(Icons.home_work_outlined)
                                        : _PopularKosThumb(
                                            rawUrl: b.imageRawUrl,
                                            token: data.token,
                                            kosId: b.kosId!,
                                            thumbFuture: _thumbFuture,
                                          ),
                                    title: Text(b.kosName),
                                    subtitle: Text(() {
                                      final start = b.startDate;
                                      final end = b.endDate;
                                      final int? days =
                                          (start == null || end == null)
                                          ? null
                                          : BookingPricing.durationDaysInclusive(
                                              start,
                                              end,
                                            );
                                      final monthly =
                                          BookingPricing.parseIntDigits(
                                            b.priceRaw,
                                          );
                                      final total =
                                          (monthly != null && days != null)
                                          ? BookingPricing.proRatedTotal(
                                              monthlyPrice: monthly,
                                              days: days,
                                            )
                                          : null;
                                      final totalText = (total == null)
                                          ? ''
                                          : BookingPricing.formatRupiahInt(
                                              total,
                                            );

                                      final base =
                                          '${b.startDateText} - ${b.endDateText}';
                                      if (totalText.isEmpty) return base;
                                      return '$base\nTotal: $totalText';
                                    }()),
                                    isThreeLine: true,
                                    trailing: const Icon(
                                      Icons.chevron_right,
                                      color: _accent,
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              BookingReceiptPreviewPage(
                                                booking: b
                                                    .toReceiptBookingMap(),
                                                token: data.token,
                                                isOwner: false,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),

              // Kos populer (berdasarkan riwayat booking user ini)
              FutureBuilder<_SocietyHomeData>(
                future: _homeFuture,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  if (data == null) return const SizedBox.shrink();

                  final popular = _popularKosFromBookings(data.bookings);
                  if (popular.isEmpty) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.72),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Text(
                                    'Kos Populer',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SocietyKosListPage(),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _accent,
                                backgroundColor: Colors.white,
                                side: BorderSide(color: _accent),
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: const Text('Lihat semua'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...popular.map(
                          (p) => Card(
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: cardBorder),
                            ),
                            child: ListTile(
                              leading: _PopularKosThumb(
                                rawUrl: p.imageRawUrl,
                                token: data.token,
                                kosId: p.kosId,
                                thumbFuture: _thumbFuture,
                              ),
                              title: Text(
                                p.kosName.isEmpty ? 'Kos' : p.kosName,
                              ),
                              subtitle: Text('Dibooking ${p.count}x'),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: _accent,
                              ),
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/booking',
                                  arguments: {
                                    'kosId': p.kosId,
                                    'token': data.token,
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopularKosThumb extends StatelessWidget {
  final String? rawUrl;
  final String token;
  final int kosId;
  final Future<String?> Function({required int kosId, required String token})
  thumbFuture;

  const _PopularKosThumb({
    required this.rawUrl,
    required this.token,
    required this.kosId,
    required this.thumbFuture,
  });

  Widget _placeholder(BuildContext context, {bool broken = false}) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 52,
        color: cs.surfaceVariant,
        alignment: Alignment.center,
        child: Icon(
          broken ? Icons.broken_image_outlined : Icons.image_outlined,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _image(BuildContext context, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(context, broken: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final direct = normalizeImageUrl((rawUrl ?? '').toString());
    if (direct.isNotEmpty) return _image(context, direct);

    return FutureBuilder<String?>(
      future: thumbFuture(kosId: kosId, token: token),
      builder: (context, snap) {
        final raw = (snap.data ?? '').toString();
        final url = normalizeImageUrl(raw);
        if (url.isEmpty) return _placeholder(context);
        return _image(context, url);
      },
    );
  }
}

class _BookingStatusThumb extends StatelessWidget {
  final String? rawUrl;
  final String token;
  final int kosId;
  final Future<String?> Function({required int kosId, required String token})
  thumbFuture;
  final IconData badgeIcon;
  final Color badgeColor;

  const _BookingStatusThumb({
    required this.rawUrl,
    required this.token,
    required this.kosId,
    required this.thumbFuture,
    required this.badgeIcon,
    required this.badgeColor,
  });

  Widget _placeholder(BuildContext context, {bool broken = false}) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 52,
        color: cs.surfaceVariant,
        alignment: Alignment.center,
        child: Icon(
          broken ? Icons.broken_image_outlined : Icons.image_outlined,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _image(BuildContext context, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(context, broken: true),
      ),
    );
  }

  Widget _baseThumb(BuildContext context) {
    final direct = normalizeImageUrl((rawUrl ?? '').toString());
    if (direct.isNotEmpty) return _image(context, direct);

    return FutureBuilder<String?>(
      future: thumbFuture(kosId: kosId, token: token),
      builder: (context, snap) {
        final raw = (snap.data ?? '').toString();
        final url = normalizeImageUrl(raw);
        if (url.isEmpty) return _placeholder(context);
        return _image(context, url);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _baseThumb(context),
          Positioned(
            left: -4,
            top: -4,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: cs.surface,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Icon(badgeIcon, size: 16, color: badgeColor),
            ),
          ),
        ],
      ),
    );
  }
}

enum _EndChoice { extend, finish }

class _SocietyHomeData {
  final String token;
  final List<_BookingItem> bookings;

  const _SocietyHomeData({required this.token, required this.bookings});
}

class _BookingItem {
  final int? bookingId;
  final int? kosId;
  final String kosName;
  final String? imageRawUrl;
  final String priceRaw;
  final String startDateRaw;
  final String endDateRaw;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  const _BookingItem({
    required this.bookingId,
    required this.kosId,
    required this.kosName,
    required this.imageRawUrl,
    required this.priceRaw,
    required this.startDateRaw,
    required this.endDateRaw,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.updatedAt,
    required this.createdAt,
  });

  String get compositeKey {
    final kid = kosId;
    // Use normalized dates for stable keys across API formatting differences
    // (e.g. '2026-02-03' vs '2026-02-03T00:00:00Z').
    final s = (startDateText != '-') ? startDateText : startDateRaw.trim();
    final e = (endDateText != '-') ? endDateText : endDateRaw.trim();
    if (kid != null && kid != 0 && s.isNotEmpty && e.isNotEmpty) {
      final u = updatedAt;
      final c = createdAt;
      // If backend omits booking id, include timestamps to avoid collapsing distinct bookings
      // that share the same kos+period.
      final stamp = (u ?? c)?.toIso8601String();
      return (stamp == null || stamp.isEmpty)
          ? 'k$kid|s$s|e$e'
          : 'k$kid|s$s|e$e|t$stamp';
    }
    final id = bookingId;
    if (id != null && id != 0) return 'id$id';
    return 'n${kosName.toLowerCase()}|s$startDateText|e$endDateText';
  }

  Map<String, dynamic> toReceiptBookingMap() {
    return {
      if (bookingId != null) 'id': bookingId,
      'kos_id': kosId,
      'kos': {
        'id': kosId,
        'name': kosName,
        if (priceRaw.trim().isNotEmpty) 'price_per_month': priceRaw.trim(),
      },
      'start_date': startDateRaw.isNotEmpty ? startDateRaw : startDateText,
      'end_date': endDateRaw.isNotEmpty ? endDateRaw : endDateText,
      'status': status,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  String get startDateText {
    final d = startDate;
    if (d == null) return '-';
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String get endDateText {
    final d = endDate;
    if (d == null) return '-';
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

class _PopularKosItem {
  final int kosId;
  final String kosName;
  final String? imageRawUrl;
  final int count;

  const _PopularKosItem({
    required this.kosId,
    required this.kosName,
    required this.imageRawUrl,
    required this.count,
  });

  _PopularKosItem copyWith({
    int? kosId,
    String? kosName,
    String? imageRawUrl,
    int? count,
  }) {
    return _PopularKosItem(
      kosId: kosId ?? this.kosId,
      kosName: kosName ?? this.kosName,
      imageRawUrl: imageRawUrl ?? this.imageRawUrl,
      count: count ?? this.count,
    );
  }
}
