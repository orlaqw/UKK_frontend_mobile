import 'dart:async';

import 'package:flutter/material.dart';
import 'package:koshunter6/services/owner/owner_kos_service.dart';
import 'package:koshunter6/services/owner/owner_image_kos_service.dart';
import 'package:koshunter6/utils/booking_pricing.dart';
import 'package:koshunter6/utils/image_url.dart';
import 'package:koshunter6/views/owner/master_kos/add_kos_page.dart';
import 'package:koshunter6/views/owner/master_kos/edit_kos_page.dart';
import 'package:koshunter6/views/owner/master_kos/facility_page.dart';
import 'package:koshunter6/views/owner/master_kos/image_kos_page.dart';
import 'package:koshunter6/widgets/booking_notification_dialog.dart';
import 'package:koshunter6/views/owner/master_kos/owner_kos_detail_page.dart';
import 'package:koshunter6/views/owner/reviews/owner_reviews_page.dart';

enum _KosMenuAction { images, facilities, edit, delete }

class KosListPage extends StatefulWidget {
  final String token;

  const KosListPage({super.key, required this.token});

  @override
  State<KosListPage> createState() => _KosListPageState();
}

class _KosListPageState extends State<KosListPage> {
  late Future<List<dynamic>> future;
  final Map<int, Future<String?>> _thumbFutureByKosId = {};

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  String _genderFilter = 'any'; // any | male | female | all(campur)
  String _priceSort = 'none'; // none | low | high
  int? _minPrice;
  int? _maxPrice;

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _kosIdFromItem(dynamic item) {
    if (item is Map) {
      return _toInt(
        // UKK responses sometimes include both a row id and kos_id.
        // For all downstream routes (detail/delete/images/facilities), we need the kos id.
        item['kos_id'] ?? item['id_kos'] ?? item['kosId'] ?? item['id'],
      );
    }
    return 0;
  }

  Future<String?> _thumbFuture(int kosId) {
    return _thumbFutureByKosId.putIfAbsent(
      kosId,
      () => OwnerImageKosService.getFirstImageUrl(
        token: widget.token,
        kosId: kosId,
      ),
    );
  }

  Widget _thumbWidget({required int kosId}) {
    return FutureBuilder<String?>(
      future: _thumbFuture(kosId),
      builder: (context, snapshot) {
        final raw = (snapshot.data ?? '').trim();
        final url = raw.isEmpty ? '' : normalizeUkkImageUrl(raw);

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 72,
            height: 72,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: url.isEmpty
                ? const Icon(Icons.image_outlined, size: 28)
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined, size: 28),
                  ),
          ),
        );
      },
    );
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

  String _genderKeyFromKos(Map kos) {
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
    if (s == 'l' ||
        s == 'lk' ||
        s == 'male' ||
        s.contains('putra') ||
        s.contains('pria')) {
      return 'male';
    }
    if (s == 'p' ||
        s == 'pr' ||
        s == 'female' ||
        s.contains('putri') ||
        s.contains('wanita')) {
      return 'female';
    }
    if (s == 'all' || s.contains('campur') || s.contains('mix')) {
      return 'all';
    }
    return s;
  }

  bool _matchesGenderFilter(Map kos) {
    final filter = _genderFilter;
    if (filter == 'any') return true;
    return _genderKeyFromKos(kos) == filter;
  }

  int? _priceValueFromKos(Map kos) {
    final raw = _asString(kos['price_per_month'] ?? kos['harga']).trim();
    if (raw.isEmpty) return null;
    return BookingPricing.parseIntDigits(raw);
  }

  bool _matchesPriceRange(Map kos) {
    final min = _minPrice;
    final max = _maxPrice;
    if (min == null && max == null) return true;

    final price = _priceValueFromKos(kos);
    if (price == null) return false;
    if (min != null && price < min) return false;
    if (max != null && price > max) return false;
    return true;
  }

  Future<void> _openFilterSheet() async {
    final minCtrl = TextEditingController(
      text: (_minPrice == null) ? '' : _minPrice.toString(),
    );
    final maxCtrl = TextEditingController(
      text: (_maxPrice == null) ? '' : _maxPrice.toString(),
    );
    String nextGender = _genderFilter;
    String nextSort = _priceSort;

    int? parseMoney(String raw) {
      final v = BookingPricing.parseIntDigits(raw);
      if (v == null || v <= 0) return null;
      return v;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        const accent = Color(0xFF7D86BF);
        final softLavender = Color.lerp(Colors.white, accent, 0.06)!;
        final cardBorder = Color.lerp(accent, Colors.white, 0.35)!;
        final fieldFill = Color.lerp(Colors.white, accent, 0.08)!;

        final inputBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cardBorder),
        );

        Widget choiceChip({
          required String label,
          required String value,
          required String groupValue,
          required void Function(String v) onSelected,
        }) {
          final selected = value == groupValue;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => onSelected(value),
            selectedColor: accent.withOpacity(0.16),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selected
                  ? accent.withOpacity(0.55)
                  : cs.outlineVariant.withOpacity(0.85),
            ),
            labelStyle: TextStyle(
              color: selected ? accent : cs.onSurface.withOpacity(0.85),
              fontWeight: FontWeight.w700,
            ),
            checkmarkColor: accent,
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Filter',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tipe kos',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      choiceChip(
                        label: 'Semua',
                        value: 'any',
                        groupValue: nextGender,
                        onSelected: (v) => setModal(() => nextGender = v),
                      ),
                      choiceChip(
                        label: 'Putra',
                        value: 'male',
                        groupValue: nextGender,
                        onSelected: (v) => setModal(() => nextGender = v),
                      ),
                      choiceChip(
                        label: 'Putri',
                        value: 'female',
                        groupValue: nextGender,
                        onSelected: (v) => setModal(() => nextGender = v),
                      ),
                      choiceChip(
                        label: 'Campur',
                        value: 'all',
                        groupValue: nextGender,
                        onSelected: (v) => setModal(() => nextGender = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Urutkan harga',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      choiceChip(
                        label: 'Default',
                        value: 'none',
                        groupValue: nextSort,
                        onSelected: (v) => setModal(() => nextSort = v),
                      ),
                      choiceChip(
                        label: 'Termurah',
                        value: 'low',
                        groupValue: nextSort,
                        onSelected: (v) => setModal(() => nextSort = v),
                      ),
                      choiceChip(
                        label: 'Termahal',
                        value: 'high',
                        groupValue: nextSort,
                        onSelected: (v) => setModal(() => nextSort = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Rentang harga / bulan',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Min',
                            hintText: 'contoh: 500000',
                            filled: true,
                            fillColor: fieldFill,
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: const BorderSide(
                                color: accent,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Max',
                            hintText: 'contoh: 1500000',
                            filled: true,
                            fillColor: fieldFill,
                            border: inputBorder,
                            enabledBorder: inputBorder,
                            focusedBorder: inputBorder.copyWith(
                              borderSide: const BorderSide(
                                color: accent,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setModal(() {
                              nextGender = 'any';
                              nextSort = 'none';
                              minCtrl.clear();
                              maxCtrl.clear();
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accent,
                            side: BorderSide(color: accent.withOpacity(0.35)),
                            backgroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final min = parseMoney(minCtrl.text);
                            final max = parseMoney(maxCtrl.text);
                            if (min != null && max != null && min > max) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Min tidak boleh lebih besar dari Max',
                                  ),
                                  backgroundColor: cs.error,
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _genderFilter = nextGender;
                              _priceSort = nextSort;
                              _minPrice = min;
                              _maxPrice = max;
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ).copyWith(
                            overlayColor: WidgetStateProperty.all(
                              softLavender.withOpacity(0.30),
                            ),
                          ),
                          icon: const Icon(Icons.check),
                          label: const Text('Terapkan'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    future = OwnerKosService.getKos(token: widget.token);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _thumbFutureByKosId.clear();
      final q = _searchQuery.trim();
      future = OwnerKosService.getKos(
        token: widget.token,
        search: q.isEmpty ? null : q,
      );
    });
    await future;
  }

  void _applySearch(String value) {
    final next = value.trim();
    if (next == _searchQuery) return;
    setState(() => _searchQuery = next);
    _refresh();
  }

  void _onSearchChanged(String value) {
    // Update UI (clear icon) immediately.
    if (mounted) setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _applySearch(value);
    });
  }

  Future<void> _openEdit(Map kos) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditKosPage(token: widget.token, kos: kos),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      await _refresh();
    }
  }

  Future<void> _openDetail(Map kos) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerKosDetailPage(token: widget.token, kos: kos),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      await _refresh();
    }
  }

  Future<void> _openReviews(Map kos) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerReviewsPage(token: widget.token, kos: kos),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openFacilities(Map kos) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FacilityPage(token: widget.token, kos: kos),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openImages(Map kos) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageKosPage(token: widget.token, kos: kos),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _confirmDelete(Map kos) async {
    final kosId = _kosIdFromItem(kos);
    if (kosId <= 0) return;

    final name = _asString(kos['name'] ?? kos['nama_kos']).trim();
    const accent = Color(0xFF7D86BF);
    final softLavender = Color.lerp(Colors.white, accent, 0.06)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return BookingNotificationDialog(
          accentColor: accent,
          title: 'Hapus Kos',
          message:
              'Yakin ingin menghapus kos ${name.isEmpty ? '' : '"$name" '}ini?\n\nCatatan: ini akan menghapus juga fasilitas, gambar, dan review terkait (permanent).',
          leftLabel: 'Batal',
          onLeftPressed: () => Navigator.pop(ctx, false),
          rightLabel: 'Hapus',
          onRightPressed: () => Navigator.pop(ctx, true),
        );
      },
    );

    if (ok != true) return;

    final progress = ValueNotifier<String>('Menyiapkan...');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: softLavender,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: accent.withOpacity(0.22)),
        ),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: accent),
            const SizedBox(width: 10),
            const Expanded(child: Text('Menghapus...')),
          ],
        ),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, value, __) => Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(value)),
            ],
          ),
        ),
      ),
    );

    try {
      await OwnerKosService.deleteKosCascade(
        token: widget.token,
        kosId: kosId,
        onProgress: (m) => progress.value = m,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Kos dihapus')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus kos\n$e')),
      );
    } finally {
      progress.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep palette consistent with OwnerHomePage / Splash gradient.
    const splashTop = Color(0xFF7D86BF);
    const splashMid = Color(0xFF9CA6DB);
    const splashBottom = Color(0xFFE9ECFF);

    final boxBg = Color.lerp(Colors.white, splashBottom, 0.65)!;
    final boxBorder = splashTop.withOpacity(0.16);
    final menuBg = Color.lerp(Colors.white, splashBottom, 0.90)!;
    final menuBorder = splashTop.withOpacity(0.18);

    return Scaffold(
      extendBodyBehindAppBar: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: splashTop,
        elevation: 0,
        surfaceTintColor: splashTop,
        foregroundColor: Colors.white,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            splashRadius: 20,
            onPressed: Navigator.of(context).canPop()
                ? () => Navigator.of(context).pop()
                : null,
          ),
        ),
        title: const Text(
          'Kos Saya',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: 'Tambah Kos',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              splashRadius: 20,
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddKosPage(token: widget.token),
                  ),
                );
                if (!mounted) return;
                if (changed == true) {
                  await _refresh();
                }
              },
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [splashTop, splashMid, splashBottom],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  onSubmitted: _applySearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari kos (nama / alamat)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Filter',
                          onPressed: _openFilterSheet,
                          icon: const Icon(Icons.tune),
                        ),
                        if (_searchCtrl.text.trim().isNotEmpty)
                          IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applySearch('');
                            },
                          ),
                      ],
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.06),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.12),
                      ),
                    ),
                  ),
                ),
              ),
              if (_genderFilter != 'any' ||
                  _priceSort != 'none' ||
                  _minPrice != null ||
                  _maxPrice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (_genderFilter != 'any')
                        InputChip(
                          label: Text(
                            'Tipe: ${_genderFilter == 'male' ? 'Putra' : _genderFilter == 'female' ? 'Putri' : 'Campur'}',
                          ),
                          onDeleted: () => setState(() => _genderFilter = 'any'),
                        ),
                      if (_priceSort != 'none')
                        InputChip(
                          label: Text(
                            _priceSort == 'low'
                                ? 'Harga: termurah'
                                : 'Harga: termahal',
                          ),
                          onDeleted: () => setState(() => _priceSort = 'none'),
                        ),
                      if (_minPrice != null || _maxPrice != null)
                        InputChip(
                          label: Text(
                            'Harga: ${_minPrice == null ? '' : '≥ ${BookingPricing.formatRupiahInt(_minPrice!)}'}${_minPrice != null && _maxPrice != null ? ' ' : ''}${_maxPrice == null ? '' : '≤ ${BookingPricing.formatRupiahInt(_maxPrice!)}'}',
                          ),
                          onDeleted: () => setState(() {
                            _minPrice = null;
                            _maxPrice = null;
                          }),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: FutureBuilder<List<dynamic>>(
                    future: future,
                    builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(
                      children: [
                        const SizedBox(height: 48),
                        Center(child: Text(snapshot.error.toString())),
                      ],
                    );
                  }

                  final rawData = snapshot.data ?? const [];
                  final list = rawData
                      .whereType<Map>()
                      .where(_matchesGenderFilter)
                      .where(_matchesPriceRange)
                      .toList(growable: true);

                  if (_priceSort != 'none') {
                    int priceOrBig(Map kos) => _priceValueFromKos(kos) ?? 1 << 30;
                    int priceOrSmall(Map kos) => _priceValueFromKos(kos) ?? -1;
                    list.sort((a, b) {
                      if (_priceSort == 'low') {
                        return priceOrBig(a).compareTo(priceOrBig(b));
                      }
                      return priceOrSmall(b).compareTo(priceOrSmall(a));
                    });
                  }

                  final data = list.toList(growable: false);

                  if (data.isEmpty) {
                    final hasSearch = _searchQuery.trim().isNotEmpty;
                    final emptyText = hasSearch
                        ? 'Tidak ada hasil'
                        : (rawData.isEmpty
                              ? 'Belum ada kos'
                              : 'Tidak ada kos sesuai filter');
                    return ListView(
                      children: [
                        const SizedBox(height: 48),
                        Center(child: Text(emptyText)),
                      ],
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final kos = data[index];
                      final kosId = _kosIdFromItem(kos);

                      final name = _asString(
                        kos['name'] ?? kos['nama_kos'],
                      ).trim();
                      final address = _asString(
                        kos['address'] ?? kos['alamat'],
                      ).trim();
                      final genderLabel = _genderLabelFromKos(kos).trim();
                      final price = _asString(
                        kos['price_per_month'] ?? kos['harga'],
                      ).trim();
                      final monthlyText = BookingPricing.formatRupiahRaw(price);
                      final typeText =
                          genderLabel.isEmpty ? 'Semua' : genderLabel;

                      final chipBg = Color.lerp(
                        Colors.white,
                        splashBottom,
                        0.62,
                      )!;

                      Widget chip(String text) {
                        final cs = Theme.of(context).colorScheme;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: chipBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: boxBorder,
                            ),
                          ),
                          child: Text(
                            text,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withOpacity(0.88),
                                ),
                          ),
                        );
                      }

                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.12),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _openDetail(kos),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _thumbWidget(kosId: kosId),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name.isEmpty ? 'Kos' : name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 36,
                                            height: 36,
                                            child: Material(
                                              color: boxBg,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: BorderSide(
                                                  color: boxBorder,
                                                ),
                                              ),
                                              child: IconButton(
                                                tooltip: 'Review',
                                                onPressed: () => _openReviews(kos),
                                                padding: EdgeInsets.zero,
                                                iconSize: 20,
                                                color: splashTop,
                                                icon: const Icon(
                                                  Icons.reviews_outlined,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          PopupMenuButton<_KosMenuAction>(
                                            tooltip: 'Menu',
                                            color: menuBg,
                                            elevation: 10,
                                            surfaceTintColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              side: BorderSide(
                                                color: menuBorder,
                                              ),
                                            ),
                                            onSelected: (value) async {
                                              switch (value) {
                                                case _KosMenuAction.images:
                                                  await _openImages(kos);
                                                  break;
                                                case _KosMenuAction.facilities:
                                                  await _openFacilities(kos);
                                                  break;
                                                case _KosMenuAction.edit:
                                                  await _openEdit(kos);
                                                  break;
                                                case _KosMenuAction.delete:
                                                  await _confirmDelete(kos);
                                                  break;
                                              }
                                            },
                                            itemBuilder: (ctx) {
                                              final cs =
                                                  Theme.of(ctx).colorScheme;

                                              Widget menuRow({
                                                required IconData icon,
                                                required String text,
                                                required Color iconColor,
                                                Color? textColor,
                                              }) {
                                                return Row(
                                                  children: [
                                                    Icon(
                                                      icon,
                                                      color: iconColor,
                                                      size: 22,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Text(
                                                      text,
                                                      style: Theme.of(ctx)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: textColor ??
                                                                cs.onSurface
                                                                    .withOpacity(
                                                                      0.86,
                                                                    ),
                                                          ),
                                                    ),
                                                  ],
                                                );
                                              }

                                              return [
                                                PopupMenuItem(
                                                  value: _KosMenuAction.images,
                                                  child: menuRow(
                                                    icon: Icons.image_outlined,
                                                    text: 'Image',
                                                    iconColor: splashTop,
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: _KosMenuAction.facilities,
                                                  child: menuRow(
                                                    icon:
                                                        Icons.grid_view_outlined,
                                                    text: 'Fasilitas',
                                                    iconColor: splashTop,
                                                  ),
                                                ),
                                                PopupMenuDivider(
                                                  height: 12,
                                                ),
                                                PopupMenuItem(
                                                  value: _KosMenuAction.edit,
                                                  child: menuRow(
                                                    icon: Icons.edit_outlined,
                                                    text: 'Edit',
                                                    iconColor: splashTop,
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: _KosMenuAction.delete,
                                                  child: menuRow(
                                                    icon: Icons.delete_outline,
                                                    text: 'Hapus',
                                                    iconColor: cs.error,
                                                    textColor: cs.error,
                                                  ),
                                                ),
                                              ];
                                            },
                                            icon: Icon(
                                              Icons.more_vert,
                                              size: 22,
                                              color: splashTop,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (address.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 0,
                                          ),
                                          child: Text(
                                            'Alamat: $address',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.70),
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          if (monthlyText.trim().isNotEmpty)
                                            chip('$monthlyText / bulan'),
                                          chip('Tipe: $typeText'),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Tap untuk lihat detail',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.55),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
