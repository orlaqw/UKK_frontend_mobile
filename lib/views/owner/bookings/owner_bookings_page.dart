import 'package:flutter/material.dart';
import 'package:koshunter6/widgets/booking_notification_dialog.dart';

import '../../../services/owner/owner_booking_service.dart';
import '../../../services/owner/owner_image_kos_service.dart';
import '../../../services/owner/owner_kos_service.dart';
import '../../../utils/booking_pricing.dart';
import '../../../utils/image_url.dart';
import '../../society/bookings/booking_receipt_preview_page.dart';

class OwnerBookingsPage extends StatefulWidget {
  final String token;

  const OwnerBookingsPage({
    super.key,
    required this.token,
  });

  @override
  State<OwnerBookingsPage> createState() => _OwnerBookingsPageState();
}

class _OwnerBookingsPageState extends State<OwnerBookingsPage> {
  static const Color _accent = Color(0xFF7D86BF);

  final _tglController = TextEditingController();
  final _bulanController = TextEditingController();
  bool _filterByMonth = false;
  String _status = 'all';
  late Future<List<dynamic>> _future;
  late Future<Map<int, Map<String, dynamic>>> _kosByIdFuture;
  final Map<int, Future<String?>> _thumbFutureByKosId = {};
  final Set<int> _updatingBookingIds = {};

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _toString(dynamic value) => value?.toString() ?? '';

  String _pickMapString(Map? map, List<String> keys) {
    if (map == null) return '';
    for (final key in keys) {
      final v = map[key];
      final s = _toString(v).trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  int? _bookingIdFromItem(dynamic item) {
    if (item is Map) {
      // Prefer explicit booking id fields first.
      final direct = _toInt(
        item['booking_id'] ??
            item['id_booking'] ??
            item['bookingId'] ??
            item['idBooking'],
      );
      if (direct != null) return direct;

      final nested = item['booking'];
      if (nested is Map) {
        final nestedId = _toInt(
          nested['booking_id'] ??
              nested['id_booking'] ??
              nested['id'] ??
              nested['bookingId'] ??
              nested['idBooking'],
        );
        if (nestedId != null) return nestedId;
      }

      // Fallback: some APIs may use `id` as booking id.
      return _toInt(item['id']);
    }
    return null;
  }

  int? _kosIdFromItem(dynamic item) {
    if (item is Map) {
      final kos = item['kos'];
      if (kos is Map) {
        final id = _toInt(kos['id'] ?? kos['kos_id'] ?? kos['id_kos']);
        if (id != null) return id;
      }
      final direct = _toInt(item['kos_id'] ?? item['id_kos'] ?? item['kosId']);
      if (direct != null) return direct;
    }
    return null;
  }

  Future<Map<int, Map<String, dynamic>>> _loadKosById() async {
    try {
      final list = await OwnerKosService.getKos(token: widget.token);
      final out = <int, Map<String, dynamic>>{};
      for (final it in list) {
        if (it is! Map) continue;
        final id = _toInt(it['id'] ?? it['kos_id'] ?? it['id_kos']);
        if (id == null || id <= 0) continue;
        out[id] = Map<String, dynamic>.from(it);
      }
      return out;
    } catch (_) {
      return <int, Map<String, dynamic>>{};
    }
  }

  Future<String?> _thumbFuture(int kosId) {
    return _thumbFutureByKosId.putIfAbsent(
      kosId,
      () async {
        try {
          return await OwnerImageKosService.getFirstImageUrl(
            token: widget.token,
            kosId: kosId,
          );
        } catch (_) {
          return null;
        }
      },
    );
  }

  String _kosAddressFromItem(dynamic item) {
    if (item is Map) {
      final kos = item['kos'] as Map?;
      final s = _pickMapString(kos, [
        'address',
        'alamat',
        'alamat_kos',
        'address_kos',
        'location',
        'lokasi',
        'full_address',
      ]);
      if (s.isNotEmpty) return s;
      return _pickMapString(item as Map?, ['address', 'alamat', 'alamat_kos', 'address_kos']);
    }
    return '';
  }

  String _priceFromMap(Map data) {
    final candidates = <dynamic>[
      data['price_per_month'],
      data['pricePerMonth'],
      data['monthly_price'],
      data['price'],
      data['rent_price'],
      data['harga_per_bulan'],
      data['harga'],
      data['biaya'],
    ];

    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return '';
  }

  String _monthlyPriceRawFromItem(dynamic item, Map<int, Map<String, dynamic>> kosById) {
    if (item is Map) {
      final direct = _priceFromMap(item);
      if (direct.isNotEmpty) return direct;
      final kos = item['kos'];
      if (kos is Map) {
        final nested = _priceFromMap(kos);
        if (nested.isNotEmpty) return nested;
      }
      final kosId = _kosIdFromItem(item);
      if (kosId != null) {
        final cached = kosById[kosId];
        if (cached != null) {
          final fromCache = _priceFromMap(cached);
          if (fromCache.isNotEmpty) return fromCache;
        }
      }
    }
    return '';
  }

  Widget _thumbWidget(BuildContext context, {required int kosId}) {
    Widget placeholder({bool broken = false}) {
      final cs = Theme.of(context).colorScheme;
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 56,
          height: 56,
          color: cs.surfaceVariant,
          alignment: Alignment.center,
          child: Icon(
            broken ? Icons.broken_image_outlined : Icons.image_outlined,
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: _thumbFuture(kosId),
      builder: (context, snap) {
        final raw = (snap.data ?? '').toString();
        final url = normalizeUkkImageUrl(raw);
        if (url.isEmpty) return placeholder();
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder(broken: true),
          ),
        );
      },
    );
  }

  String _statusFromItem(dynamic item) {
    if (item is Map) {
      final s = _toString(item['status'] ?? item['booking_status']).trim();
      return s.isEmpty ? '-' : s;
    }
    return '-';
  }

  String _kosNameFromItem(dynamic item) {
    if (item is Map) {
      final kos = item['kos'] as Map?;
      final s = _pickMapString(kos, ['name', 'nama_kos', 'nama', 'kos_name']);
      if (s.isNotEmpty) return s;
      final direct = _pickMapString(item as Map?, [
        'kos_name',
        'nama_kos',
        'kosName',
        'namaKos',
        'name_kos',
      ]);
      if (direct.isNotEmpty) return direct;
    }
    return 'Kos';
  }

  String _societyNameFromItem(dynamic item) {
    if (item is Map) {
      final user = item['user'] as Map?;
      final society = item['society'] as Map?;
      final s = _pickMapString(user, ['name', 'nama']);
      if (s.isNotEmpty) return s;
      final s2 = _pickMapString(society, ['name', 'nama']);
      if (s2.isNotEmpty) return s2;
      return _pickMapString(item as Map?, ['user_name', 'society_name']);
    }
    return '';
  }

  String _dateRangeFromItem(dynamic item) {
    if (item is Map) {
      final start = _toString(item['start_date']).trim();
      final end = _toString(item['end_date']).trim();
      if (start.isNotEmpty || end.isNotEmpty) {
        return '${start.isEmpty ? '-' : start} - ${end.isEmpty ? '-' : end}';
      }
      final tgl = _toString(item['tgl'] ?? item['date']).trim();
      return tgl.isEmpty ? '-' : tgl;
    }
    return '-';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;

    if (value is int || value is num) {
      final n = (value is int) ? value : (value as num).toInt();
      if (n <= 0) return null;
      final ms = (n >= 1000000000000) ? n : n * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;

    final normalizedSpace = raw.contains(' ') && !raw.contains('T')
        ? raw.replaceFirst(' ', 'T')
        : raw;
    final normalizedTry = DateTime.tryParse(normalizedSpace);
    if (normalizedTry != null) return normalizedTry;

    final m = RegExp(
      r'^(\\d{2})[\\/\\-](\\d{2})[\\/\\-](\\d{4})(?:[ T](\\d{2}):(\\d{2})(?::(\\d{2}))?)?$',
    ).firstMatch(raw);
    if (m != null) {
      final day = int.parse(m.group(1)!);
      final month = int.parse(m.group(2)!);
      final year = int.parse(m.group(3)!);
      final hour = int.tryParse(m.group(4) ?? '') ?? 0;
      final minute = int.tryParse(m.group(5) ?? '') ?? 0;
      final second = int.tryParse(m.group(6) ?? '') ?? 0;
      return DateTime(year, month, day, hour, minute, second);
    }

    return null;
  }

  bool _isCancelledOrDoneStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('cancel') ||
        s.contains('batal') ||
        s.contains('done') ||
        s.contains('finish') ||
        s.contains('selesai') ||
        s.contains('complete');
  }

  bool _isActiveAcceptedBookingToday(dynamic item) {
    if (item is! Map) return false;

    final status = _statusFromItem(item);
    if (!_isAcceptedStatus(status)) return false;
    if (_isRejectedStatus(status)) return false;
    if (_isCancelledOrDoneStatus(status)) return false;

    final start = _parseDate(item['start_date'] ?? item['tanggal_mulai']);
    final end = _parseDate(item['end_date'] ?? item['tanggal_selesai']);
    if (start == null || end == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return !today.isBefore(startDay) && !today.isAfter(endDay);
  }

  bool _matchesSelectedRange(dynamic item) {
    if (item is! Map) return false;

    final start = _parseDate(item['start_date'] ?? item['tanggal_mulai']);
    final end = _parseDate(item['end_date'] ?? item['tanggal_selesai']);
    if (start == null || end == null) return false;

    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(end.year, end.month, end.day);
    if (b.isBefore(a)) return false;

    // Build target range from selected filter.
    if (_filterByMonth) {
      final ym = _bulanController.text.trim();
      if (ym.length < 7) return false;
      final monthStart = DateTime.tryParse('${ym.substring(0, 7)}-01');
      if (monthStart == null) return false;
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
      // Overlap check.
      return !b.isBefore(monthStart) && !a.isAfter(monthEnd);
    }

    final tgl = _tglController.text.trim();
    final day = DateTime.tryParse(tgl);
    if (day == null) return false;
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(a) && !d.isAfter(b);
  }

  Future<void> _pickTgl() async {
    final now = DateTime.now();
    final initial = _tglController.text.isNotEmpty
        ? DateTime.tryParse(_tglController.text) ?? now
        : now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );

    if (picked != null) {
      _tglController.text = picked.toIso8601String().split('T').first;
      _load();
    }
  }

  Future<void> _pickBulan() async {
    final now = DateTime.now();
    DateTime initial = now;
    final current = _bulanController.text.trim();
    if (current.length >= 7) {
      final parsed = DateTime.tryParse('${current.substring(0, 7)}-01');
      if (parsed != null) initial = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Pilih bulan (ambil bulan & tahun)',
    );

    if (picked != null) {
      final ym = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}';
      _bulanController.text = ym;
      _load();
    }
  }

  void _load() {
    final tgl = _tglController.text.trim();
    final bulan = _bulanController.text.trim();

    if (_filterByMonth) {
      if (bulan.isEmpty) return;
    } else {
      if (tgl.isEmpty) return;
    }

    setState(() {
      _future = OwnerBookingService.getBookings(
        token: widget.token,
        tgl: _filterByMonth ? null : tgl,
        month: _filterByMonth ? bulan : null,
        status: _status,
      );
    });
  }

  bool _isTerminalStatus(String status) {
    final s = status.trim().toLowerCase();
    return s == 'accept' ||
        s == 'accepted' ||
        s == 'reject' ||
        s == 'rejected' ||
        s.contains('tolak') ||
        s.contains('terima');
  }

  bool _isRejectedStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('reject') || s.contains('rejected') || s.contains('tolak');
  }

  bool _isAcceptedStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('accept') || s.contains('accepted') || s.contains('terima') || s.contains('diterima');
  }

  bool _isPendingStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return true;
    if (_isRejectedStatus(s) || _isAcceptedStatus(s)) return false;
    return s.contains('pending') ||
        s.contains('wait') ||
        s.contains('menunggu') ||
        s.contains('request') ||
        s.contains('diajukan') ||
        s.contains('baru');
  }

  IconData _badgeIconForStatus(String status) {
    if (_isRejectedStatus(status)) return Icons.cancel_outlined;
    if (_isAcceptedStatus(status)) return Icons.check_circle_outline;
    return Icons.hourglass_top_rounded;
  }

  Color _badgeColorForStatus(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    if (_isRejectedStatus(status)) return Colors.redAccent;
    if (_isAcceptedStatus(status)) return Colors.green;
    if (_isPendingStatus(status)) return cs.primary;
    return cs.primary;
  }

  Widget _thumbWithBadge(BuildContext context, {required int kosId, required String status}) {
    final cs = Theme.of(context).colorScheme;
    final icon = _badgeIconForStatus(status);
    final color = _badgeColorForStatus(context, status);

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _thumbWidget(context, kosId: kosId),
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
              child: Icon(icon, size: 16, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmUpdate(
    String status, {
    required String kosName,
    required String societyName,
    required String dateRange,
  }) async {
    final label = status.toLowerCase() == 'accept' ? 'Terima' : 'Tolak';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final safeKosName = kosName.trim().isEmpty ? '-' : kosName.trim();
        final safeSociety = societyName.trim().isEmpty ? '-' : societyName.trim();
        final safeDate = dateRange.trim().isEmpty ? '-' : dateRange.trim();

        return BookingNotificationDialog(
          accentColor: _accent,
          title: 'Konfirmasi $label',
            message: 'Yakin ingin $label permintaan booking ini?\n\n'
              'Kos: $safeKosName\n'
              'Periode: $safeDate',
          leftLabel: 'Batal',
          onLeftPressed: () => Navigator.pop(ctx, false),
          rightLabel: label,
          onRightPressed: () => Navigator.pop(ctx, true),
        );
      },
    );
    return ok == true;
  }

  Future<void> _updateStatus({
    required int bookingId,
    required String status,
    required String kosName,
    required String societyName,
    required String dateRange,
  }) async {
    if (_updatingBookingIds.contains(bookingId)) return;
    final confirmed = await _confirmUpdate(
      status,
      kosName: kosName,
      societyName: societyName,
      dateRange: dateRange,
    );
    if (!confirmed) return;

    setState(() {
      _updatingBookingIds.add(bookingId);
    });

    try {
      await OwnerBookingService.updateStatus(
        token: widget.token,
        bookingId: bookingId,
        status: status,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status berhasil diubah: $status')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingBookingIds.remove(bookingId);
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tglController.text = DateTime.now().toIso8601String().split('T').first;
    final now = DateTime.now();
    _bulanController.text = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    _future = OwnerBookingService.getBookings(
      token: widget.token,
      tgl: _tglController.text,
      status: _status,
    );
    _kosByIdFuture = _loadKosById();
  }

  @override
  void dispose() {
    _tglController.dispose();
    _bulanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final softBg = Color.lerp(Colors.white, _accent, 0.06)!;
    final cardBorder = Color.lerp(_accent, Colors.white, 0.35)!;
    final fieldFill = Color.lerp(Colors.white, _accent, 0.10)!;

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cardBorder),
    );

    return Scaffold(
      backgroundColor: softBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: Navigator.of(context).canPop()
              ? () => Navigator.of(context).pop()
              : null,
        ),
        title: const Text('Booking Aktif'),
        centerTitle: true,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        surfaceTintColor: _accent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: _filterByMonth
                        ? TextField(
                            controller: _bulanController,
                            readOnly: true,
                            onTap: _pickBulan,
                            decoration: InputDecoration(
                              labelText: 'Bulan',
                              hintText: 'YYYY-MM',
                              filled: true,
                              fillColor: fieldFill,
                              border: inputBorder,
                              enabledBorder: inputBorder,
                              focusedBorder: inputBorder.copyWith(
                                borderSide: const BorderSide(color: _accent, width: 1.4),
                              ),
                            ),
                          )
                        : TextField(
                            controller: _tglController,
                            readOnly: true,
                            onTap: _pickTgl,
                            decoration: InputDecoration(
                              labelText: 'Tanggal (tgl)',
                              hintText: 'YYYY-MM-DD',
                              filled: true,
                              fillColor: fieldFill,
                              border: inputBorder,
                              enabledBorder: inputBorder,
                              focusedBorder: inputBorder.copyWith(
                                borderSide: const BorderSide(color: _accent, width: 1.4),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: fieldFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cardBorder),
                    ),
                    child: IconButton(
                      tooltip: _filterByMonth ? 'Filter per tanggal' : 'Filter per bulan',
                      onPressed: () {
                        setState(() => _filterByMonth = !_filterByMonth);
                        _load();
                      },
                      icon: Icon(
                        _filterByMonth ? Icons.event : Icons.date_range,
                        color: _accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _status,
                      decoration: InputDecoration(
                        labelText: 'Status',
                        filled: true,
                        fillColor: fieldFill,
                        border: inputBorder,
                        enabledBorder: inputBorder,
                        focusedBorder: inputBorder.copyWith(
                          borderSide: const BorderSide(color: _accent, width: 1.4),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'accept', child: Text('Accept')),
                        DropdownMenuItem(value: 'reject', child: Text('Reject')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _status = v);
                        _load();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_accent),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  );
                }

                final data = snapshot.data ?? const [];
                final filtered = data
                    .where(_matchesSelectedRange)
                    .where(_isActiveAcceptedBookingToday)
                    .toList(growable: false);
                if (filtered.isEmpty) {
                  final label = _filterByMonth
                      ? 'bulan ${_bulanController.text.trim()}'
                      : 'tanggal ${_tglController.text.trim()}';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Tidak ada booking aktif untuk $label',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  );
                }

                return FutureBuilder<Map<int, Map<String, dynamic>>>(
                  future: _kosByIdFuture,
                  builder: (context, kosSnap) {
                    final kosById = kosSnap.data ?? const <int, Map<String, dynamic>>{};

                    return RefreshIndicator(
                      color: _accent,
                      backgroundColor: Colors.white,
                      onRefresh: () async {
                        _load();
                        await _future;
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final bookingId = _bookingIdFromItem(item);
                          final kosId = _kosIdFromItem(item);
                          final societyName = _societyNameFromItem(item);
                          final dateRange = _dateRangeFromItem(item);
                          final status = _statusFromItem(item).toLowerCase();

                          var kosName = _kosNameFromItem(item).trim();
                          if ((kosName.isEmpty || kosName.toLowerCase() == 'kos') && kosId != null) {
                            final kos = kosById[kosId];
                            final fromCache = _pickMapString(kos, ['name', 'nama_kos', 'nama']);
                            if (fromCache.trim().isNotEmpty) {
                              kosName = fromCache.trim();
                            }
                          }
                          if (kosName.isEmpty || kosName.toLowerCase() == 'kos') {
                            kosName = (kosId != null) ? 'Kos #$kosId' : 'Kos';
                          }

                          var address = _kosAddressFromItem(item);
                          if (address.trim().isEmpty && kosId != null) {
                            final kos = kosById[kosId];
                            address = _pickMapString(kos, [
                              'address',
                              'alamat',
                              'alamat_kos',
                              'address_kos',
                              'location',
                              'lokasi',
                              'full_address',
                            ]);
                          }
                          final addressLine = address.trim().isEmpty ? '-' : address.trim();

                            final monthlyRaw = _monthlyPriceRawFromItem(item, kosById);
                            final monthlyText = BookingPricing.formatRupiahRaw(monthlyRaw);
                            final monthlyInt = BookingPricing.parseIntDigits(monthlyRaw);
                            final dailyInt = (monthlyInt != null)
                              ? BookingPricing.proRatedTotal(monthlyPrice: monthlyInt, days: 1)
                              : null;
                            final dailyText = (dailyInt == null)
                              ? ''
                              : '${BookingPricing.formatRupiahInt(dailyInt)} / hari';

                          final canUpdate = bookingId != null && !_isTerminalStatus(status);
                          final isUpdating = bookingId != null && _updatingBookingIds.contains(bookingId);

                          final statusLabel = _statusFromItem(item).trim();
                          final isAccepted = _isAcceptedStatus(statusLabel);
                          final isRejected = _isRejectedStatus(statusLabel);

                          final pillBg = isAccepted
                              ? Color.lerp(Colors.white, Colors.green, 0.12)!
                              : isRejected
                                  ? Color.lerp(Colors.white, Colors.redAccent, 0.10)!
                                  : Color.lerp(Colors.white, _accent, 0.12)!;
                          final pillFg = isAccepted
                              ? Colors.green
                              : isRejected
                                  ? Colors.redAccent
                                  : _accent;

                          return Card(
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: cardBorder),
                            ),
                            child: ListTile(
                              leading: (kosId == null)
                                  ? Icon(_badgeIconForStatus(status))
                                  : _thumbWithBadge(
                                      context,
                                      kosId: kosId,
                                      status: status,
                                    ),
                              title: Text(kosName),
                              subtitle: Text(
                                '$addressLine'
                                '${monthlyText.trim().isEmpty ? '' : '\nHarga: $monthlyText / bulan${dailyText.isEmpty ? '' : ' ($dailyText)'}'}'
                                '\n$dateRange'
                                '\n${societyName.trim().isEmpty ? '' : '${societyName.trim()} • '}Status: $statusLabel',
                              ),
                              isThreeLine: true,
                              onTap: () {
                                if (item is! Map) return;
                                final societyName = _societyNameFromItem(item);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BookingReceiptPreviewPage(
                                      booking: item,
                                      societyName: societyName,
                                      token: widget.token,
                                      isOwner: true,
                                    ),
                                  ),
                                );
                              },
                              trailing: canUpdate
                                  ? Wrap(
                                      spacing: 8,
                                      children: [
                                        OutlinedButton(
                                          onPressed: isUpdating
                                              ? null
                                              : () => _updateStatus(
                                                    bookingId: bookingId,
                                                    status: 'reject',
                                                    kosName: kosName,
                                                    societyName: societyName,
                                                    dateRange: dateRange,
                                                  ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.redAccent,
                                            side: const BorderSide(color: Colors.redAccent),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: isUpdating
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('Tolak'),
                                        ),
                                        ElevatedButton(
                                          onPressed: isUpdating
                                              ? null
                                              : () => _updateStatus(
                                                    bookingId: bookingId,
                                                    status: 'accept',
                                                    kosName: kosName,
                                                    societyName: societyName,
                                                    dateRange: dateRange,
                                                  ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _accent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: isUpdating
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('Terima'),
                                        ),
                                      ],
                                    )
                                  : (bookingId == null
                                      ? const Text('ID?')
                                      : Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: pillBg,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border:
                                                Border.all(color: cardBorder),
                                          ),
                                          child: Text(
                                            statusLabel.isEmpty
                                                ? status
                                                : statusLabel,
                                            style: TextStyle(
                                              color: pillFg,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
