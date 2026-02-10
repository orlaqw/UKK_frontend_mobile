import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:koshunter6/services/auth_service.dart';
import 'package:koshunter6/services/society/booking_service.dart';
import 'package:koshunter6/services/society/society_image_kos_service.dart';
import 'package:koshunter6/utils/booking_pricing.dart';
import 'package:koshunter6/views/society/reviews/reviews_page.dart';

import '../../../utils/image_url.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_gradient_scaffold.dart';
import 'society_kos_detail_page.dart';

class SocietyKosListPage extends StatefulWidget {
  const SocietyKosListPage({super.key});

  @override
  State<SocietyKosListPage> createState() => _SocietyKosListPageState();
}

class _SocietyKosListPageState extends State<SocietyKosListPage> {
  static const Color _accent = Color(0xFF7D86BF);

  String? _token;
  Future<List<dynamic>>? _future;
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  String _genderFilter = 'all';
  String _priceSort = 'none'; // none | low | high
  int? _minPrice;
  int? _maxPrice;
  bool _redirecting = false;

  final Map<int, Future<String?>> _thumbFutureByKosId = {};

  String _normalizeGender(dynamic value) {
    final s = (value ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return '';

    if (s == 'l' || s == 'lk' || s == 'male' || s.contains('putra')) {
      return 'putra';
    }
    if (s == 'p' || s == 'pr' || s == 'female' || s.contains('putri')) {
      return 'putri';
    }
    if (s == 'all' ||
        s == 'semua' ||
        s.contains('campur') ||
        s.contains('mix')) {
      return 'campur';
    }

    if (s.contains('pria')) return 'putra';
    if (s.contains('wanita')) return 'putri';

    return s;
  }

  String _genderFromKos(Map kos) {
    final keys = <String>[
      'gender',
      'kos_gender',
      'gender_kos',
      'jenis_kos',
      'type',
      'kategori',
      'category',
      'for_gender',
    ];

    for (final k in keys) {
      if (kos.containsKey(k)) {
        final normalized = _normalizeGender(kos[k]);
        if (normalized.isNotEmpty) return normalized;
      }
    }
    return '';
  }

  List<dynamic> _applyGenderFilter(List<dynamic> items) {
    final selected = _genderFilter.trim().toLowerCase();
    if (selected.isEmpty || selected == 'all') return items;

    return items.where((e) {
      if (e is! Map) return false;
      final g = _genderFromKos(e);
      if (g.isEmpty) return false;
      return g == selected;
    }).toList();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  int? _kosIdFromKos(Map kos) {
    return _toInt(kos['kos_id'] ?? kos['id_kos'] ?? kos['kosId'] ?? kos['id']);
  }

  String _priceFromKos(Map kos) {
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

  int? _priceValueFromKos(Map kos) {
    final raw = _priceFromKos(kos).trim();
    if (raw.isEmpty) return null;
    return BookingPricing.parseIntDigits(raw);
  }

  bool _matchesGenderFilter(Map kos) {
    final selected = _genderFilter.trim().toLowerCase();
    if (selected.isEmpty || selected == 'all') return true;
    final g = _genderFromKos(kos);
    if (g.isEmpty) return false;
    return g == selected;
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
            selectedColor: _accent.withOpacity(0.16),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selected
                  ? _accent.withOpacity(0.55)
                  : cs.outlineVariant.withOpacity(0.85),
            ),
            labelStyle: TextStyle(
              color: selected ? _accent : cs.onSurface.withOpacity(0.85),
              fontWeight: FontWeight.w700,
            ),
            checkmarkColor: _accent,
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
                        value: 'all',
                        groupValue: nextGender,
                        onSelected: (v) => setModal(() => nextGender = v),
                      ),
                      choiceChip(
                        label: 'Putra',
                        value: 'putra',
                        groupValue: nextGender,
                        onSelected: (v) => setModal(() => nextGender = v),
                      ),
                      choiceChip(
                        label: 'Putri',
                        value: 'putri',
                        groupValue: nextGender,
                        onSelected: (v) => setModal(() => nextGender = v),
                      ),
                      choiceChip(
                        label: 'Campur',
                        value: 'campur',
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
                            fillColor: Colors.white,
                            labelStyle: TextStyle(
                              color: cs.onSurface.withOpacity(0.75),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(14),
                              ),
                              borderSide: BorderSide(
                                color: _accent.withOpacity(0.85),
                                width: 1.6,
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
                            fillColor: Colors.white,
                            labelStyle: TextStyle(
                              color: cs.onSurface.withOpacity(0.75),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(14),
                              ),
                              borderSide: BorderSide(
                                color: _accent.withOpacity(0.85),
                                width: 1.6,
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
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            side: BorderSide(color: _accent.withOpacity(0.55)),
                          ),
                          onPressed: () {
                            setModal(() {
                              nextGender = 'all';
                              nextSort = 'none';
                              minCtrl.clear();
                              maxCtrl.clear();
                            });
                          },
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                          ),
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

  String _genderLabelFromKey(String key) {
    final k = key.trim().toLowerCase();
    if (k == 'putra') return 'Putra';
    if (k == 'putri') return 'Putri';
    if (k == 'campur') return 'Campur';
    if (k == 'all') return 'Semua';
    if (k.isEmpty) return '';
    return k[0].toUpperCase() + k.substring(1);
  }

  Future<void> _openBookingHistory() async {
    final token = _token ?? await AuthService.getToken();
    if (!mounted) return;
    if (token == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    Navigator.pushNamed(
      context,
      '/booking-history',
      arguments: {'token': token, 'status': 'all'},
    );
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _search);
  }

  bool _looksLikeInvalidToken(dynamic error) {
    final s = error.toString().toLowerCase();
    return s.contains('401') ||
        (s.contains('token') &&
            (s.contains('invalid') || s.contains('tidak ditemukan')));
  }

  Future<void> _handleInvalidToken() async {
    if (_redirecting) return;
    _redirecting = true;
    await AuthService.logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sesi habis, silakan login ulang')),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<List<dynamic>> _wrapAuth(Future<List<dynamic>> future) {
    return future;
  }

  Future<void> _init() async {
    final token = await AuthService.getToken();
    if (!mounted) return;
    if (token == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    setState(() {
      _token = token;
      _future = _wrapAuth(BookingService.showKos(token: token));
    });
  }

  void _search() {
    final token = _token;
    if (token == null) return;

    _thumbFutureByKosId.clear();
    setState(() {
      _future = _wrapAuth(
        BookingService.showKos(token: token, search: _searchCtrl.text.trim()),
      );
    });
  }

  Future<String?> _thumbFuture({required int kosId, required String token}) {
    return _thumbFutureByKosId.putIfAbsent(
      kosId,
      () => SocietyImageKosService.getFirstImageUrl(token: token, kosId: kosId),
    );
  }

  String _coverFromKos(Map kos) {
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
      if (!kos.containsKey(key)) continue;
      final v = (kos[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  List<String> _initialImageUrlsFromKos(Map kos) {
    final out = <String>[];

    void addUrl(dynamic v) {
      final s = normalizeUkkImageUrl((v ?? '').toString());
      if (s.trim().isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    // Single cover-like field.
    addUrl(_coverFromKos(kos));

    // Some list responses may already carry multiple images.
    for (final key in const [
      'images',
      'image_kos',
      'kos_image',
      'kos_images',
      'gambar_kos',
      'gallery',
      'photos',
      'gambar',
    ]) {
      final v = kos[key];
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
      } else if (v is Map) {
        addUrl(
          v['image_url'] ?? v['url'] ?? v['image'] ?? v['file'] ?? v['path'],
        );
      } else if (v is String) {
        addUrl(v);
      }
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;

    final baseTheme = Theme.of(context);
    final cs = baseTheme.colorScheme;
    final theme = baseTheme.copyWith(
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        foregroundColor: _accent,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
    );

    return Theme(
      data: theme,
      child: AppGradientScaffold(
        title: 'Pilih Kos',
        showBack: true,
        backgroundGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE9ECFF), Color(0xFF9CA6DB), Color(0xFF7D86BF)],
          stops: [0.0, 0.55, 1.0],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Riwayat Booking',
            onPressed: _openBookingHistory,
          ),
        ],
        child: token == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Cari kos (nama / alamat)',
                            prefixIcon: IconButton(
                              tooltip: 'Cari',
                              onPressed: _search,
                              icon: const Icon(Icons.search),
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Filter',
                                  icon: const Icon(Icons.tune),
                                  onPressed: _openFilterSheet,
                                ),
                                if (_searchCtrl.text.trim().isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear',
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {});
                                      _search();
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
                          onSubmitted: (_) => _search(),
                          onChanged: (_) {
                            setState(() {});
                            _scheduleSearch();
                          },
                        ),
                        if (_genderFilter != 'all' ||
                            _priceSort != 'none' ||
                            _minPrice != null ||
                            _maxPrice != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (_genderFilter != 'all')
                                  InputChip(
                                    label: Text(
                                      'Tipe: ${_genderLabelFromKey(_genderFilter)}',
                                    ),
                                    labelStyle: TextStyle(
                                      color: cs.onSurface.withOpacity(0.80),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: cs.surface,
                                    side: BorderSide(
                                      color: cs.outlineVariant.withOpacity(
                                        0.65,
                                      ),
                                    ),
                                    deleteIconColor: _accent,
                                    onDeleted: () => setState(() {
                                      _genderFilter = 'all';
                                    }),
                                  ),
                                if (_priceSort != 'none')
                                  InputChip(
                                    label: Text(
                                      _priceSort == 'low'
                                          ? 'Harga: termurah'
                                          : 'Harga: termahal',
                                    ),
                                    labelStyle: TextStyle(
                                      color: cs.onSurface.withOpacity(0.80),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: cs.surface,
                                    side: BorderSide(
                                      color: cs.outlineVariant.withOpacity(
                                        0.65,
                                      ),
                                    ),
                                    deleteIconColor: _accent,
                                    onDeleted: () => setState(() {
                                      _priceSort = 'none';
                                    }),
                                  ),
                                if (_minPrice != null || _maxPrice != null)
                                  InputChip(
                                    label: Text(
                                      'Harga: ${_minPrice == null ? '' : '≥ ${BookingPricing.formatRupiahInt(_minPrice!)}'}${_minPrice != null && _maxPrice != null ? ' ' : ''}${_maxPrice == null ? '' : '≤ ${BookingPricing.formatRupiahInt(_maxPrice!)}'}',
                                    ),
                                    labelStyle: TextStyle(
                                      color: cs.onSurface.withOpacity(0.80),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    backgroundColor: cs.surface,
                                    side: BorderSide(
                                      color: cs.outlineVariant.withOpacity(
                                        0.65,
                                      ),
                                    ),
                                    deleteIconColor: _accent,
                                    onDeleted: () => setState(() {
                                      _minPrice = null;
                                      _maxPrice = null;
                                    }),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        _search();
                        await _future;
                      },
                      child: FutureBuilder<List<dynamic>>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            if (_looksLikeInvalidToken(snapshot.error)) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Sesi kamu sudah habis.\nSilakan login ulang.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                      onPressed: _handleInvalidToken,
                                      child: const Text('Login ulang'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return Center(
                              child: Text(
                                'Gagal memuat kos\n${snapshot.error}'
                                '${(kIsWeb && snapshot.error.toString().contains('XMLHttpRequest error')) ? '\n\nCatatan: di Flutter Web, error ini biasanya karena CORS / server menolak request dari browser. Coba jalankan di Android/Windows atau pakai proxy.' : ''}',
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          final rawData = snapshot.data ?? const <dynamic>[];
                          final list = rawData
                              .whereType<Map>()
                              .where(_matchesGenderFilter)
                              .where(_matchesPriceRange)
                              .toList(growable: true);

                          if (_priceSort != 'none') {
                            int priceOrBig(Map kos) =>
                                _priceValueFromKos(kos) ?? 1 << 30;
                            int priceOrSmall(Map kos) =>
                                _priceValueFromKos(kos) ?? -1;
                            list.sort((a, b) {
                              if (_priceSort == 'low') {
                                return priceOrBig(a).compareTo(priceOrBig(b));
                              }
                              return priceOrSmall(b).compareTo(priceOrSmall(a));
                            });
                          }

                          final filtered = list.toList(growable: false);

                          if (filtered.isEmpty) {
                            return const Center(
                              child: Text('Kos tidak ditemukan'),
                            );
                          }

                          final cs = Theme.of(context).colorScheme;
                          final theme = Theme.of(context);

                          return ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final kos = filtered[i];
                              if (kos is! Map) return const SizedBox.shrink();

                              final name =
                                  (kos['name'] ?? kos['nama_kos'] ?? 'Kos')
                                      .toString();
                              final address =
                                  (kos['address'] ?? kos['alamat'] ?? '-')
                                      .toString();
                              final price = _priceFromKos(kos);
                              final genderKey = _genderFromKos(kos);
                              final genderLabel = _genderLabelFromKey(
                                genderKey,
                              );
                              final kosId = _kosIdFromKos(kos);

                              void openDetail() {
                                final id = kosId;
                                if (id == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('ID kos tidak valid'),
                                    ),
                                  );
                                  return;
                                }

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SocietyKosDetailPage(
                                      token: token,
                                      kosId: id,
                                      kosName: name,
                                      initialImageUrls:
                                          _initialImageUrlsFromKos(kos),
                                    ),
                                  ),
                                );
                              }

                              void openReview() {
                                final id = kosId;
                                if (id == null) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ReviewPage(
                                      kosId: id,
                                      token: token,
                                      kosName: name,
                                      readOnly: true,
                                    ),
                                  ),
                                );
                              }

                              Widget buildThumb() {
                                const size = 92.0;

                                Widget placeholder(IconData icon) {
                                  return Container(
                                    width: size,
                                    height: size,
                                    color: cs.surfaceVariant,
                                    alignment: Alignment.center,
                                    child: Icon(
                                      icon,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  );
                                }

                                if (kosId == null) {
                                  return placeholder(Icons.image_outlined);
                                }

                                final fromData = normalizeUkkImageUrl(
                                  _coverFromKos(kos),
                                );
                                if (fromData.isNotEmpty) {
                                  return Image.network(
                                    fromData,
                                    width: size,
                                    height: size,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => placeholder(
                                      Icons.broken_image_outlined,
                                    ),
                                  );
                                }

                                return FutureBuilder<String?>(
                                  future: _thumbFuture(
                                    kosId: kosId,
                                    token: token,
                                  ),
                                  builder: (context, snap) {
                                    final url = normalizeUkkImageUrl(
                                      (snap.data ?? '').toString(),
                                    );
                                    if (url.isEmpty) {
                                      return placeholder(Icons.image_outlined);
                                    }

                                    return Image.network(
                                      url,
                                      width: size,
                                      height: size,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => placeholder(
                                        Icons.broken_image_outlined,
                                      ),
                                    );
                                  },
                                );
                              }

                              return AppCard(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                color: Colors.white,
                                onTap: openDetail,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: buildThumb(),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: cs.onSurface,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.location_on_outlined,
                                                size: 16,
                                                color: cs.onSurface.withOpacity(
                                                  0.70,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Alamat: $address',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: cs.onSurface
                                                        .withOpacity(0.70),
                                                    height: 1.25,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          if (price.trim().isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 9,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: _accent,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Rp $price / bulan',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          if (price.trim().isNotEmpty)
                                            const SizedBox(height: 10),
                                          if (genderLabel.trim().isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 9,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                border: Border.all(
                                                  color: _accent,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'Tipe: $genderLabel',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                            ),
                                          if (genderLabel.trim().isNotEmpty)
                                            const SizedBox(height: 10),
                                          Text(
                                            'Tap untuk lihat detail',
                                            style: TextStyle(
                                              color: cs.onSurface.withOpacity(
                                                0.55,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Review kos ini',
                                          icon: const Icon(
                                            Icons.rate_review_outlined,
                                          ),
                                          color: _accent,
                                          onPressed: kosId == null
                                              ? null
                                              : openReview,
                                        ),
                                      ],
                                    ),
                                  ],
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
    );
  }
}
