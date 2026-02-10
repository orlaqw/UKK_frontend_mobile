import 'package:flutter/material.dart';
import 'package:koshunter6/services/owner/owner_facility_service.dart';
import 'package:koshunter6/services/owner/owner_image_kos_service.dart';
import 'package:koshunter6/services/owner/owner_review_service.dart';
import 'package:koshunter6/utils/booking_pricing.dart';
import 'package:koshunter6/utils/deleted_review_store.dart';
import 'package:koshunter6/utils/image_url.dart';
import 'package:koshunter6/views/owner/master_kos/edit_kos_page.dart';
import 'package:koshunter6/views/owner/master_kos/facility_page.dart';
import 'package:koshunter6/views/owner/master_kos/image_kos_page.dart';
import 'package:koshunter6/views/owner/reviews/owner_reviews_page.dart';
import 'package:koshunter6/widgets/kos_image_carousel.dart';
import 'package:koshunter6/utils/network_error_hint.dart';

class OwnerKosDetailPage extends StatefulWidget {
  final String token;
  final Map kos;

  const OwnerKosDetailPage({super.key, required this.token, required this.kos});

  @override
  State<OwnerKosDetailPage> createState() => _OwnerKosDetailPageState();
}

class _OwnerKosDetailPageState extends State<OwnerKosDetailPage> {
  late Future<List<dynamic>> _imagesFuture;
  late Future<List<dynamic>> _facilitiesFuture;
  late Future<List<dynamic>> _reviewsFuture;

  Set<int> _locallyDeletedReviewIds = const {};

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  int _toInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _pickKosIdFromMap(Map? map) {
    if (map == null) return 0;
    return _toInt(
      map['id'] ??
          map['kos_id'] ??
          map['id_kos'] ??
          map['kosId'] ??
          map['idKos'],
    );
  }

  int _kosId() {
    final direct = _pickKosIdFromMap(widget.kos);
    if (direct > 0) return direct;
    final data = widget.kos['data'];
    if (data is Map) {
      final nested = _pickKosIdFromMap(data);
      if (nested > 0) return nested;
    }
    final kos = widget.kos['kos'];
    if (kos is Map) {
      final nested = _pickKosIdFromMap(kos);
      if (nested > 0) return nested;
    }
    return 0;
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

  String _facilityName(dynamic item) {
    if (item is Map) {
      final v = item['facility_name'] ?? item['name'] ?? item['nama_fasilitas'];
      final s = _asString(v).trim();
      if (s.isNotEmpty) return s;
    }
    final s = _asString(item).trim();
    return s.isEmpty ? '-' : s;
  }

  Widget _facilityCard(BuildContext context, String name) {
    final cs = Theme.of(context).colorScheme;
    const splashTop = Color(0xFF7D86BF);
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: splashTop.withOpacity(0.85)),
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

  String _imageUrl(dynamic item) {
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

  void _refresh() {
    final kosId = _kosId();
    setState(() {
      _imagesFuture = (kosId <= 0)
          ? Future.value(const [])
          : OwnerImageKosService.getImages(token: widget.token, kosId: kosId);
      _facilitiesFuture = (kosId <= 0)
          ? Future.value(const [])
          : OwnerFacilityService.getFacilities(
              token: widget.token,
              kosId: kosId,
            );
      _reviewsFuture = (kosId <= 0)
          ? Future.value(const [])
          : OwnerReviewService.getReviews(token: widget.token, kosId: kosId);
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

  String _replyTextFromItem(dynamic item) {
    if (item is Map) {
      dynamic v = item['reply'] ??
          item['owner_reply'] ??
          item['admin_reply'] ??
          item['response'] ??
          item['balasan'] ??
          item['tanggapan'] ??
          item['reply_text'] ??
          item['reply_message'];
      if (v is Map) {
        v = v['reply'] ?? v['text'] ?? v['message'] ?? v['content'];
      }
      return _asString(v).trim();
    }
    return '';
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

  Future<void> _openEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditKosPage(token: widget.token, kos: widget.kos),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      _refresh();
      // Beri sinyal ke halaman list bahwa ada perubahan
      Navigator.pop(context, true);
    }
  }

  Future<void> _openFacilities() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacilityPage(token: widget.token, kos: widget.kos),
      ),
    );
    if (!mounted) return;
    _refresh();
  }

  Future<void> _openImages() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageKosPage(token: widget.token, kos: widget.kos),
      ),
    );
    if (!mounted) return;
    _refresh();
  }

  Future<void> _openReviews() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerReviewsPage(token: widget.token, kos: widget.kos),
      ),
    );
    if (!mounted) return;
    _refresh();
  }

  @override
  void initState() {
    super.initState();
    final kosId = _kosId();
    _imagesFuture = (kosId <= 0)
        ? Future.value(const [])
        : OwnerImageKosService.getImages(token: widget.token, kosId: kosId);
    _facilitiesFuture = (kosId <= 0)
        ? Future.value(const [])
        : OwnerFacilityService.getFacilities(token: widget.token, kosId: kosId);
    _reviewsFuture = (kosId <= 0)
      ? Future.value(const [])
      : OwnerReviewService.getReviews(token: widget.token, kosId: kosId);
    _loadLocallyDeletedReviewIds();
  }

  @override
  Widget build(BuildContext context) {
    // Keep palette consistent with OwnerHomePage / Splash gradient.
    const splashTop = Color(0xFF7D86BF);
    const splashMid = Color(0xFF9CA6DB);
    const splashBottom = Color(0xFFE9ECFF);

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
                ..color = splashTop.withOpacity(0.95),
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
          Icon(icon, size: size + 3.5, color: splashTop.withOpacity(0.95)),
          Icon(icon, size: size, color: Colors.white),
        ],
      );
    }

    final softLavender = Color.lerp(Colors.white, splashBottom, 0.65)!;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final chipSide = BorderSide(color: splashTop.withOpacity(0.85));
    final chipShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: chipSide,
    );

    final kos = widget.kos;
    final kosId = _kosId();

    final name = _asString(kos['name']).trim().isNotEmpty
        ? _asString(kos['name']).trim()
        : (_asString(kos['nama_kos']).trim().isNotEmpty
              ? _asString(kos['nama_kos']).trim()
              : 'Kos');

    final address = _asString(kos['address']).trim().isNotEmpty
        ? _asString(kos['address']).trim()
        : (_asString(kos['alamat']).trim().isNotEmpty
              ? _asString(kos['alamat']).trim()
              : '-');

    final price = _asString(kos['price_per_month'] ?? kos['harga']).trim();
    final monthlyText = BookingPricing.formatRupiahRaw(price);
    final monthlyInt = BookingPricing.parseIntDigits(price);
    final dailyInt = (monthlyInt != null)
        ? BookingPricing.proRatedTotal(monthlyPrice: monthlyInt, days: 1)
        : null;
    final genderLabel = _genderLabelFromKos(kos);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [splashTop, splashMid, splashBottom],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 240,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.white,
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
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? const [];
                    final raw = items.isEmpty ? '' : _imageUrl(items.first);
                    final url = normalizeUkkImageUrl(raw);

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (url.isNotEmpty)
                          Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.broken_image, size: 56),
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
                        // gradient overlay biar title kebaca
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
                        Chip(
                          backgroundColor: softLavender,
                          shape: chipShape,
                          label: Text('$monthlyText / bulan'),
                          avatar: Icon(
                            Icons.credit_card_outlined,
                            size: 18,
                            color: splashTop,
                          ),
                        ),
                      if (dailyInt != null)
                        Chip(
                          backgroundColor: softLavender,
                          shape: chipShape,
                          label: Text(
                            '${BookingPricing.formatRupiahInt(dailyInt)} / hari (prorata)',
                          ),
                          avatar: Icon(
                            Icons.payments_outlined,
                            size: 18,
                            color: splashTop,
                          ),
                        ),
                      if (genderLabel.isNotEmpty)
                        Chip(
                          backgroundColor: softLavender,
                          shape: chipShape,
                          label: Text(genderLabel),
                          avatar: Icon(
                            Icons.people_alt_outlined,
                            size: 18,
                            color: splashTop,
                          ),
                        ),
                      if (kosId > 0)
                        Chip(
                          backgroundColor: softLavender,
                          shape: chipShape,
                          label: Text('ID: $kosId'),
                          avatar: Icon(Icons.tag, size: 18, color: splashTop),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openFacilities,
                          icon: const Icon(Icons.list_alt),
                          label: const Text('Fasilitas'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: splashTop,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: buttonShape,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openImages,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gambar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: splashTop,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: buttonShape,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openReviews,
                          icon: const Icon(Icons.reviews_outlined),
                          label: const Text('Tulis Review'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: splashTop,
                            backgroundColor: softLavender,
                            side: BorderSide(color: splashTop.withOpacity(0.55)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: buttonShape,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openEdit,
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: splashTop,
                            backgroundColor: softLavender,
                            side: BorderSide(color: splashTop.withOpacity(0.55)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: buttonShape,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    'Galeri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<dynamic>>(
                    future: _imagesFuture,
                    builder: (context, snapshot) {
                      final items = snapshot.data ?? const [];
                      final urls = items
                          .map((e) => normalizeUkkImageUrl(_imageUrl(e)))
                          .where((u) => u.isNotEmpty)
                          .toList(growable: false);

                      if (urls.isEmpty) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Belum ada gambar.'),
                        );
                      }

                      return KosImageCarousel(
                        imageUrls: urls,
                        height: 220,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    'Fasilitas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<dynamic>>(
                    future: _facilitiesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LinearProgressIndicator();
                      }
                      if (snapshot.hasError) {
                        return Text(
                          'Gagal memuat fasilitas: ${snapshot.error}${networkErrorHint(snapshot.error!)}',
                        );
                      }

                      final facilities = snapshot.data ?? const [];
                      if (facilities.isEmpty) {
                        return const Text('Belum ada fasilitas untuk kos ini.');
                      }

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in facilities)
                            _facilityCard(context, _facilityName(f)),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    'Review',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<dynamic>>(
                    future: _reviewsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LinearProgressIndicator();
                      }
                      if (snapshot.hasError) {
                        return Text('Gagal memuat review: ${snapshot.error}');
                      }

                      final all = (snapshot.data ?? const <dynamic>[])
                          .where((e) => !_isDeletedReviewItem(e))
                          .where((e) {
                            final rid = _reviewIdFromItem(e);
                            if (rid == null) return true;
                            return !_locallyDeletedReviewIds.contains(rid);
                          })
                          .toList(growable: false);

                      if (all.isEmpty) {
                        return const Text('Belum ada review.');
                      }

                      final cs = Theme.of(context).colorScheme;
                      final preview = all.take(7).toList(growable: false);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final it in preview)
                            Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: splashTop.withOpacity(0.25),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _reviewTextFromItem(it).trim().isEmpty
                                                ? '(tanpa teks)'
                                                : _reviewTextFromItem(it).trim(),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: cs.onSurface.withOpacity(0.88),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_replyTextFromItem(it).trim().isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.grey[300]!),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Balasan Owner',
                                                    style: TextStyle(
                                                      color: Color(0xFF7D86BF),
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _replyTextFromItem(it).trim(),
                                                    style: const TextStyle(height: 1.35),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          if (all.length > 7)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _openReviews,
                                icon: const Icon(Icons.arrow_forward),
                                label: Text('Lihat semua (${all.length})'),
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
        ),
      ),
    );
  }
}
