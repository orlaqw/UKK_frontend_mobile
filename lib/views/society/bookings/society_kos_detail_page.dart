import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:koshunter6/services/society/booking_service.dart';
import 'package:koshunter6/services/society/society_image_kos_service.dart';
import 'package:koshunter6/services/society/society_review_service.dart';
import 'package:koshunter6/utils/booking_pricing.dart';
import 'package:koshunter6/utils/deleted_review_store.dart';
import 'package:koshunter6/utils/image_url.dart';
import 'package:koshunter6/utils/network_error_hint.dart';
import 'package:koshunter6/views/society/bookings/booking_receipt_preview_page.dart';
import 'package:koshunter6/views/society/reviews/reviews_page.dart';
import 'package:koshunter6/widgets/booking_notification_dialog.dart';
import 'package:koshunter6/widgets/kos_image_carousel.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _AfterBookingAction { home, history, receipt }

class SocietyKosDetailPage extends StatefulWidget {
  final String token;
  final int kosId;
  final String? kosName;
  final List<String> initialImageUrls;

  const SocietyKosDetailPage({
    super.key,
    required this.token,
    required this.kosId,
    this.kosName,
    this.initialImageUrls = const [],
  });

  @override
  State<SocietyKosDetailPage> createState() => _SocietyKosDetailPageState();
}

class _SocietyKosDetailPageState extends State<SocietyKosDetailPage> {
  // Keep palette consistent with Society pages.
  static const Color _accent = Color(0xFF7D86BF);
  // static const Color _accentMid = Color(0xFF9CA6DB);
  static const Color _accentLight = Color(0xFFE9ECFF);

  late Future<Map<String, dynamic>> _detailFuture;
  late Future<List<dynamic>> _imagesFuture;
  late Future<List<String>> _facilitiesFuture;
  late Future<List<dynamic>> _reviewsFuture;

  final GlobalKey _galleryKey = GlobalKey();
  final GlobalKey _reviewsKey = GlobalKey();
  final GlobalKey _facilitiesKey = GlobalKey();

  Set<int> _locallyDeletedReviewIds = const {};

  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _bookingSubmitting = false;

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  int _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _imageUrlFromItem(dynamic item) {
    if (item is String) return item;
    if (item is Map) {
      final v =
          item['image_url'] ??
          item['url'] ??
          item['image'] ??
          item['file'] ??
          item['path'];
      return _asString(v);
    }
    return '';
  }

  List<String> _urlsFromItems(List<dynamic> items) {
    final out = <String>[];
    for (final it in items) {
      final url = normalizeUkkImageUrl(_imageUrlFromItem(it));
      if (url.trim().isEmpty) continue;
      if (!out.contains(url)) out.add(url);
    }
    return out;
  }

  List<String> _mergeUrls(List<String> a, List<String> b) {
    final out = <String>[];
    for (final s in a) {
      final v = normalizeUkkImageUrl(s);
      if (v.trim().isEmpty) continue;
      if (!out.contains(v)) out.add(v);
    }
    for (final s in b) {
      final v = normalizeUkkImageUrl(s);
      if (v.trim().isEmpty) continue;
      if (!out.contains(v)) out.add(v);
    }
    return out;
  }

  void _refresh() {
    setState(() {
      _detailFuture = BookingService.getKosDetail(
        token: widget.token,
        kosId: widget.kosId,
      );
      _imagesFuture = SocietyImageKosService.getImages(
        token: widget.token,
        kosId: widget.kosId,
      );
      _facilitiesFuture = _detailFuture.then(_extractFacilityNamesFromDetail);
      _reviewsFuture = SocietyReviewService.getReviews(
        token: widget.token,
        kosId: widget.kosId,
      );
    });
  }

  Future<void> _loadLocallyDeletedReviewIds() async {
    final ids = await DeletedReviewStore.getDeletedReviewIds();
    if (!mounted) return;
    setState(() => _locallyDeletedReviewIds = ids);
  }

  int? _toIntOrNull(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  int? _reviewIdFromItem(dynamic item) {
    if (item is Map) {
      return _toIntOrNull(item['id'] ?? item['review_id'] ?? item['id_review']);
    }
    return null;
  }

  String _reviewTextFromItem(dynamic item) {
    if (item is Map) {
      final v = item['review'] ??
          item['comment'] ??
          item['message'] ??
          item['content'] ??
          item['ulasan'];
      return _asString(v).trim();
    }
    return _asString(item).trim();
  }

  bool _isDeletedReviewItem(dynamic item) {
    if (item is! Map) return false;
    final deletedAt = item['deleted_at'] ?? item['deletedAt'];
    if (deletedAt != null && _asString(deletedAt).trim().isNotEmpty) {
      return true;
    }

    final deleted = item['is_deleted'] ?? item['isDeleted'] ?? item['deleted'];
    if (deleted is bool) return deleted;
    if (deleted is num) return deleted != 0;
    final deletedStr = _asString(deleted).trim().toLowerCase();
    if (deletedStr == 'true' || deletedStr == '1' || deletedStr == 'yes') {
      return true;
    }

    return false;
  }

  List<String> _extractFacilityNamesFromDetail(Map<String, dynamic> detail) {
    final out = <String>[];

    void addFacility(dynamic v) {
      final s = _asString(v).trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return;
      if (!out.contains(s)) out.add(s);
    }

    final raw =
        detail['kos_facilities'] ??
        detail['facilities'] ??
        detail['facility'] ??
        detail['fasilitas'] ??
        detail['facilities_kos'] ??
        detail['facility_kos'];

    if (raw is List) {
      for (final it in raw) {
        if (it is Map) {
          addFacility(it['facility_name'] ?? it['name'] ?? it['nama_fasilitas']);
        } else {
          addFacility(it);
        }
      }
    }

    return out;
  }

  // List<String> _extractFacilityNamesFromItems(List<dynamic> items) {
  //   final out = <String>[];

  //   void addFacility(dynamic v) {
  //     final s = _asString(v).trim();
  //     if (s.isEmpty || s.toLowerCase() == 'null') return;
  //     if (!out.contains(s)) out.add(s);
  //   }

  //   for (final it in items) {
  //     if (it is Map) {
  //       addFacility(it['facility_name'] ?? it['name'] ?? it['nama_fasilitas']);
  //     } else {
  //       addFacility(it);
  //     }
  //   }

  //   return out;
  // }

  List<String> _mergeFacilities(List<String> a, List<String> b) {
    final out = <String>[];
    for (final s in a) {
      final v = _asString(s).trim();
      if (v.isEmpty) continue;
      if (!out.contains(v)) out.add(v);
    }
    for (final s in b) {
      final v = _asString(s).trim();
      if (v.isEmpty) continue;
      if (!out.contains(v)) out.add(v);
    }
    return out;
  }

  Future<void> _scrollToGallery() async {
    final ctx = _galleryKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  Future<void> _scrollToFacilities() async {
    final ctx = _facilitiesKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  String _formatYmd(DateTime d) {
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${pad(d.month)}-${pad(d.day)}';
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final initial = _startDate ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    final normalized = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _startDate = normalized;
      _startCtrl.text = _formatYmd(normalized);
      if (_endDate != null && _endDate!.isBefore(normalized)) {
        _endDate = normalized;
        _endCtrl.text = _formatYmd(normalized);
      }
    });
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final min = _startDate ?? DateTime(now.year, now.month, now.day);
    final initial = _endDate ?? min;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: min,
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    final normalized = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _endDate = normalized;
      _endCtrl.text = _formatYmd(normalized);
    });
  }

  String _genderLabelFromKos(Map kos) {
    final raw =
        kos['gender'] ??
        kos['kos_gender'] ??
        kos['gender_kos'] ??
        kos['jenis_kos'] ??
        kos['type'] ??
        kos['kategori'] ??
        kos['category'] ??
        kos['for_gender'];
    final s = _asString(raw).trim().toLowerCase();
    if (s.isEmpty) return '';

    if (s == 'l' || s == 'lk' || s == 'male' || s.contains('putra')) {
      return 'Putra';
    }
    if (s == 'p' || s == 'pr' || s == 'female' || s.contains('putri')) {
      return 'Putri';
    }
    if (s == 'all' || s.contains('campur') || s.contains('mix')) {
      return 'Campur';
    }
    if (s.contains('pria')) return 'Putra';
    if (s.contains('wanita')) return 'Putri';
    return s[0].toUpperCase() + s.substring(1);
  }

  List<String> _extractImageUrls(Map<String, dynamic> kos) {
    final out = <String>[];

    void addUrl(dynamic raw) {
      final s = normalizeUkkImageUrl(_asString(raw).trim());
      if (s.isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    void addFromValue(dynamic v) {
      if (v is List) {
        for (final it in v) {
          if (it is Map) {
            addUrl(
              it['image_url'] ??
                  it['url'] ??
                  it['image'] ??
                  it['file'] ??
                  it['path'],
            );
          } else {
            addUrl(it);
          }
        }
        return;
      }
      if (v is Map) {
        addUrl(
          v['image_url'] ?? v['url'] ?? v['image'] ?? v['file'] ?? v['path'],
        );
        return;
      }
      addUrl(v);
    }

    for (final key in const [
      'images',
      'image',
      'image_kos',
      'images_kos',
      'kos_image',
      'kos_images',
      'gallery',
      'photos',
      'image_urls',
      'images_url',
    ]) {
      final v = kos[key];
      if (v != null) addFromValue(v);
    }

    // Sometimes detail endpoint returns nested objects.
    for (final nestedKey in const ['kos', 'data', 'detail', 'result']) {
      final v = kos[nestedKey];
      if (v is Map) {
        for (final key in const [
          'images',
          'image',
          'image_kos',
          'images_kos',
          'kos_image',
          'kos_images',
          'gallery',
          'photos',
          'image_urls',
          'images_url',
        ]) {
          final nested = v[key];
          if (nested != null) addFromValue(nested);
        }
      }
    }

    for (final key in const [
      'image_url',
      'cover_url',
      'thumbnail_url',
      'image',
      'cover',
      'thumbnail',
      'photo',
      'gambar',
      'file',
      'path',
    ]) {
      if (kos.containsKey(key)) addUrl(kos[key]);
    }

    return out;
  }

  List<String> _extractFacilities(Map<String, dynamic> kos) {
    final out = <String>[];

    void addFacility(dynamic v) {
      final s = _asString(v).trim();
      if (s.isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    for (final key in const [
      'facilities',
      'facility',
      'fasilitas',
      'facilities_kos',
      'facility_kos',
    ]) {
      final v = kos[key];
      if (v is List) {
        for (final it in v) {
          if (it is Map) {
            addFacility(
              it['facility_name'] ?? it['name'] ?? it['nama_fasilitas'],
            );
          } else {
            addFacility(it);
          }
        }
      }
    }

    // Sometimes facilities are nested under kos/detail.
    for (final nestedKey in const ['kos', 'data', 'detail']) {
      final v = kos[nestedKey];
      if (v is Map) {
        for (final key in const [
          'facilities',
          'facility',
          'fasilitas',
          'facilities_kos',
          'facility_kos',
        ]) {
          final list = v[key];
          if (list is List) {
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
        }
      }
    }

    return out;
  }

  Widget _infoChip(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final softLavender = Color.lerp(Colors.white, _accentLight, 0.65)!;
    final chipSide = BorderSide(color: _accent.withOpacity(0.85));
    final chipShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: chipSide,
    );
    return Chip(
      backgroundColor: softLavender,
      shape: chipShape,
      avatar: Icon(icon, size: 18, color: _accent),
      label: Text(text),
    );
  }

  Widget _facilityCard(BuildContext context, String name) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withOpacity(0.85)),
      ),
      child: Center(
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _detailFuture = BookingService.getKosDetail(
      token: widget.token,
      kosId: widget.kosId,
    );
    _imagesFuture = SocietyImageKosService.getImages(
      token: widget.token,
      kosId: widget.kosId,
    );
    _facilitiesFuture = _detailFuture.then(_extractFacilityNamesFromDetail);
    _reviewsFuture = SocietyReviewService.getReviews(
      token: widget.token,
      kosId: widget.kosId,
    );
    _loadLocallyDeletedReviewIds();
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _openReviews({
    required int kosId,
    required String kosName,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReviewPage(token: widget.token, kosId: kosId, kosName: kosName),
      ),
    );
  }

  Future<void> _submitBooking({
    required int kosId,
    required String kosName,
  }) async {
    if (_bookingSubmitting) return;

    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih tanggal mulai & selesai dulu')),
      );
      return;
    }

    setState(() => _bookingSubmitting = true);
    try {
      final res = await BookingService.createBooking(
        token: widget.token,
        kosId: kosId,
        startDate: _formatYmd(start),
        endDate: _formatYmd(end),
      );

      // Hint for Society Home sorting: some backends return bookings without
      // reliable id/timestamps or in ascending order.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'society_last_created_booking_hint_v1',
          jsonEncode({
            'kos_id': kosId,
            'start_date': _formatYmd(start),
            'end_date': _formatYmd(end),
            'created_at_local': DateTime.now().toIso8601String(),
          }),
        );
      } catch (_) {
        // ignore
      }

      if (!mounted) return;

      Map booking = {};
      final data = res['data'];
      if (data is Map) {
        booking = Map<String, dynamic>.from(data);
      } else if (res['booking'] is Map) {
        booking = Map<String, dynamic>.from(res['booking'] as Map);
      } else {
        booking = res;
      }

      final action = await showDialog<_AfterBookingAction>(
        context: context,
        builder: (dctx) {
          if (booking.isNotEmpty) {
            return BookingNotificationDialog(
              accentColor: _accent,
              title: 'Booking berhasil',
              message: 'Booking untuk "$kosName" sudah dibuat.',
              leftLabel: 'Tutup',
              onLeftPressed: () =>
                  Navigator.pop(dctx, _AfterBookingAction.home),
              middleLabel: 'Riwayat',
              onMiddlePressed: () =>
                  Navigator.pop(dctx, _AfterBookingAction.history),
              rightLabel: 'Lihat bukti',
              onRightPressed: () =>
                  Navigator.pop(dctx, _AfterBookingAction.receipt),
            );
          }

          return BookingNotificationDialog(
            accentColor: _accent,
            title: 'Booking berhasil',
            message: 'Booking untuk "$kosName" sudah dibuat.',
            leftLabel: 'Tutup',
            onLeftPressed: () =>
                Navigator.pop(dctx, _AfterBookingAction.home),
            rightLabel: 'Riwayat',
            onRightPressed: () =>
                Navigator.pop(dctx, _AfterBookingAction.history),
          );
        },
      );

      if (!mounted) return;

      switch (action ?? _AfterBookingAction.home) {
        case _AfterBookingAction.history:
          Navigator.pushNamed(
            context,
            '/booking-history',
            arguments: {'token': widget.token, 'status': 'all'},
          );
          return;
        case _AfterBookingAction.receipt:
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookingReceiptPreviewPage(
                booking: booking,
                token: widget.token,
                isOwner: false,
              ),
            ),
          );
          return;
        case _AfterBookingAction.home:
          // Recreate SocietyHomePage so it reloads bookings without manual refresh.
          Navigator.pushNamedAndRemoveUntil(context, '/society', (_) => false);
          return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _bookingSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget outlinedAppBarTitle(String text) {
      return Stack(
        children: [
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.6
                ..color = _accent.withOpacity(0.95),
            ),
          ),
          const SizedBox(height: 0),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      );
    }

    Widget outlinedAppBarIcon(IconData icon, {double size = 24}) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: size + 3.5, color: _accent.withOpacity(0.95)),
          Icon(icon, size: size, color: Colors.white),
        ],
      );
    }

    final softLavender = Color.lerp(Colors.white, _accentLight, 0.65)!;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    InputDecoration dateFieldDecoration(String hint) {
      return InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: _accent.withOpacity(0.85), width: 1.6),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, _accentLight, _accent],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _detailFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Gagal memuat detail kos\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final kos = snapshot.data ?? <String, dynamic>{};
            final id = _toInt(kos['id'] ?? widget.kosId);

            final name = _asString(kos['name']).trim().isNotEmpty
                ? _asString(kos['name']).trim()
                : (_asString(kos['nama_kos']).trim().isNotEmpty
                      ? _asString(kos['nama_kos']).trim()
                      : (widget.kosName ?? 'Kos'));

            final address = _asString(kos['address']).trim().isNotEmpty
                ? _asString(kos['address']).trim()
                : (_asString(kos['alamat']).trim().isNotEmpty
                      ? _asString(kos['alamat']).trim()
                      : '-');

            final priceRaw = _asString(
              kos['price_per_month'] ??
                  kos['monthly_price'] ??
                  kos['price'] ??
                  kos['harga'],
            ).trim();

            final monthlyInt = BookingPricing.parseIntDigits(priceRaw);
            final monthlyText = (monthlyInt != null)
                ? BookingPricing.formatRupiahInt(monthlyInt)
                : (priceRaw.isEmpty ? '' : 'Rp $priceRaw');

            final dailyInt = (monthlyInt != null)
                ? BookingPricing.proRatedTotal(
                    monthlyPrice: monthlyInt,
                    days: 1,
                  )
                : null;
            final dailyText = (dailyInt != null)
                ? BookingPricing.formatRupiahInt(dailyInt)
                : '';

            final genderLabel = _genderLabelFromKos(kos);
            final imagesFromDetail = _extractImageUrls(kos);
            final facilities = _extractFacilities(kos);

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 240,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  foregroundColor: Colors.white,
                  centerTitle: true,
                  leading: IconButton(
                    tooltip: 'Kembali',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: outlinedAppBarIcon(Icons.arrow_back),
                  ),
                  title: outlinedAppBarTitle(name),
                  actions: [
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _refresh,
                      icon: outlinedAppBarIcon(Icons.refresh),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: FutureBuilder<List<dynamic>>(
                      future: _imagesFuture,
                      builder: (context, imgSnap) {
                        final fetchedUrls = _urlsFromItems(
                          imgSnap.data ?? const [],
                        );
                        final merged = _mergeUrls(
                          widget.initialImageUrls,
                          fetchedUrls,
                        );
                        final coverUrl = merged.isNotEmpty
                            ? merged.first
                            : (imagesFromDetail.isEmpty
                                  ? ''
                                  : imagesFromDetail.first);

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            if (coverUrl.isNotEmpty)
                              Image.network(
                                coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade300,
                                  child: const Icon(
                                    Icons.broken_image,
                                    size: 56,
                                  ),
                                ),
                              )
                            else
                              Container(
                                color: Colors.grey.shade300,
                                child: const Icon(
                                  Icons.home_work_outlined,
                                  size: 56,
                                ),
                              ),
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black26,
                                    Colors.transparent,
                                    Colors.black54,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      child: Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withOpacity(0.06),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('Alamat: $address'),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (monthlyText.trim().isNotEmpty)
                                    _infoChip(
                                      context,
                                      icon: Icons.credit_card_outlined,
                                      text: '$monthlyText / bulan',
                                    ),
                                  if (dailyText.trim().isNotEmpty)
                                    _infoChip(
                                      context,
                                      icon: Icons.payments_outlined,
                                      text: '$dailyText / hari (prorata)',
                                    ),
                                  if (genderLabel.trim().isNotEmpty)
                                    _infoChip(
                                      context,
                                      icon: Icons.people_alt_outlined,
                                      text: genderLabel,
                                    ),
                                  if (id > 0)
                                    _infoChip(
                                      context,
                                      icon: Icons.tag,
                                      text: 'ID: $id',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          id <= 0 ? null : _scrollToFacilities,
                                      icon: const Icon(Icons.list_alt_outlined),
                                      label: const Text('Fasilitas'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _accent,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: buttonShape,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          id <= 0 ? null : _scrollToGallery,
                                      icon: const Icon(Icons.image_outlined),
                                      label: const Text('Gambar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _accent,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: buttonShape,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: id <= 0
                                      ? null
                                      : () => _openReviews(
                                            kosId: id,
                                            kosName: name,
                                          ),
                                  icon: const Icon(Icons.reviews_outlined),
                                  label: const Text('Tulis Review'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _accent,
                                    backgroundColor: softLavender,
                                    side: BorderSide(
                                      color: _accent.withOpacity(0.55),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: buttonShape,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _startCtrl,
                                readOnly: true,
                                decoration: dateFieldDecoration(
                                  'Tanggal Mulai (YYYY-MM-DD)',
                                ),
                                onTap: _pickStartDate,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _endCtrl,
                                readOnly: true,
                                decoration: dateFieldDecoration(
                                  'Tanggal Selesai (YYYY-MM-DD)',
                                ),
                                onTap: _pickEndDate,
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 52,
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: (id <= 0 || _bookingSubmitting)
                                      ? null
                                      : () => _submitBooking(
                                            kosId: id,
                                            kosName: name,
                                          ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: buttonShape,
                                  ),
                                  child: _bookingSubmitting
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Booking'),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Container(
                                key: _galleryKey,
                                alignment: Alignment.centerLeft,
                                child: const Text(
                                  'Galeri',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<List<dynamic>>(
                                future: _imagesFuture,
                                builder: (context, imgSnap) {
                                  final fetchedUrls = _urlsFromItems(
                                    imgSnap.data ?? const [],
                                  );
                                  final finalUrls = _mergeUrls(
                                    widget.initialImageUrls,
                                    _mergeUrls(
                                      fetchedUrls,
                                      imagesFromDetail,
                                    ),
                                  );

                                  if (imgSnap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const LinearProgressIndicator();
                                  }
                                  if (imgSnap.hasError && finalUrls.isEmpty) {
                                    final msg =
                                        (imgSnap.error ?? '').toString();
                                    final lower = msg.toLowerCase();
                                    final denied =
                                        lower.contains('ditolak') ||
                                        lower.contains('tidak bisa') ||
                                        lower.contains('401') ||
                                        lower.contains('403') ||
                                        lower.contains('tidak memiliki akses');

                                    final notFound =
                                        lower.contains('404') ||
                                        lower.contains('not found') ||
                                        lower.contains(
                                          'endpoint gambar tidak ditemukan',
                                        );

                                    if (denied) {
                                      return const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Galeri tidak bisa ditampilkan untuk akun Society karena endpoint gambar hanya tersedia untuk Owner/Admin di backend UKK.',
                                        ),
                                      );
                                    }

                                    if (notFound) {
                                      return const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Galeri tidak tersedia (endpoint gambar tidak ditemukan di backend).',
                                        ),
                                      );
                                    }

                                    return Text('Gagal memuat gambar: $msg');
                                  }
                                  if (finalUrls.isEmpty) {
                                    return const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('Belum ada gambar.'),
                                    );
                                  }

                                  return KosImageCarousel(
                                    imageUrls: finalUrls,
                                    height: 220,
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(16),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                              Container(
                                key: _facilitiesKey,
                                alignment: Alignment.centerLeft,
                                child: const Text(
                                  'Fasilitas',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<List<String>>(
                                future: _facilitiesFuture,
                                builder: (context, facSnap) {
                                  final fromApi =
                                      facSnap.data ?? const <String>[];
                                  final merged = _mergeFacilities(
                                    facilities,
                                    fromApi,
                                  );

                                  if (facSnap.connectionState ==
                                          ConnectionState.waiting &&
                                      merged.isEmpty) {
                                    return const LinearProgressIndicator();
                                  }

                                  if (facSnap.hasError && merged.isEmpty) {
                                    return Text(
                                      'Gagal memuat fasilitas\n${facSnap.error}${networkErrorHint(facSnap.error!)}',
                                      textAlign: TextAlign.center,
                                    );
                                  }

                                  if (merged.isEmpty) {
                                    return const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Belum ada fasilitas untuk kos ini.',
                                      ),
                                    );
                                  }

                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final f in merged)
                                        _facilityCard(context, f),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                              Container(
                                key: _reviewsKey,
                                alignment: Alignment.centerLeft,
                                child: const Text(
                                  'Review',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<List<dynamic>>(
                                future: _reviewsFuture,
                                builder: (context, revSnap) {
                                  if (revSnap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const LinearProgressIndicator();
                                  }

                                  if (revSnap.hasError) {
                                    return Text(
                                      'Gagal memuat review: ${revSnap.error}',
                                    );
                                  }

                                  final all =
                                      (revSnap.data ?? const <dynamic>[])
                                          .where(
                                            (e) => !_isDeletedReviewItem(e),
                                          )
                                          .where((e) {
                                            final rid = _reviewIdFromItem(e);
                                            if (rid == null) return true;
                                            return !_locallyDeletedReviewIds
                                                .contains(rid);
                                          })
                                          .toList(growable: false);

                                  if (all.isEmpty) {
                                    return const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('Belum ada review.'),
                                    );
                                  }

                                  final cs = Theme.of(context).colorScheme;
                                  final preview = all.take(7).toList(
                                        growable: false,
                                      );

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final it in preview)
                                        Card(
                                          margin: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          elevation: 0,
                                          color: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            side: BorderSide(
                                              color: _accent.withOpacity(0.25),
                                            ),
                                          ),
                                          child: ListTile(
                                            title: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _reviewTextFromItem(it)
                                                          .trim()
                                                          .isEmpty
                                                      ? '(tanpa teks)'
                                                      : _reviewTextFromItem(it)
                                                          .trim(),
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: cs.onSurface
                                                        .withOpacity(0.88),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Builder(builder: (ctx) {
                                                  final reply =
                                                      _asString(it['reply'] ??
                                                              it['owner_reply'] ??
                                                              it['response'] ??
                                                              it['balasan'] ??
                                                              it['tanggapan'] ??
                                                              it['admin_reply'])
                                                          .trim();
                                                  if (reply.isEmpty) return const
                                                      SizedBox.shrink();

                                                  return Container(
                                                    width: double.infinity,
                                                    padding:
                                                        const EdgeInsets.all(
                                                            12),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade100,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: Border.all(
                                                          color: _accent
                                                              .withOpacity(0.25)),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Balasan Owner',
                                                          style: TextStyle(
                                                              color: _accent,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700),
                                                        ),
                                                        const SizedBox(
                                                            height: 6),
                                                        Text(
                                                          reply,
                                                          style: const TextStyle(
                                                            color: Colors.black,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (all.length > 7)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: () => _openReviews(
                                              kosId: id,
                                              kosName: name,
                                            ),
                                            icon: const Icon(
                                              Icons.arrow_forward,
                                            ),
                                            label: Text(
                                              'Lihat semua (${all.length})',
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
