import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../services/owner/owner_booking_service.dart';
import '../../../services/owner/owner_image_kos_service.dart';
import '../../society/bookings/booking_receipt_preview_page.dart';
import '../../../utils/booking_receipt_pdf.dart';
import '../../../utils/image_url.dart';
import '../../../utils/booking_receipt_data.dart';

class OwnerBookingHistoryPage extends StatefulWidget {
  final String token;

  const OwnerBookingHistoryPage({
    super.key,
    required this.token,
  });

  @override
  State<OwnerBookingHistoryPage> createState() =>
      _OwnerBookingHistoryPageState();
}

class _OwnerBookingHistoryPageState extends State<OwnerBookingHistoryPage> {
  static const Color _accentPurple = Color(0xFF7D86BF);

  late Future<List<dynamic>> _future;
  final _searchController = TextEditingController();
  String _status = 'all';
  DateTime? _filterStart;
  DateTime? _filterEnd;

  final Map<int, Future<String?>> _thumbFutureByKosId = {};

  @override
  void initState() {
    super.initState();
    _future = _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _toString(dynamic value) => value?.toString() ?? '';

  int? _kosIdFromItem(dynamic item) {
    if (item is! Map) return null;
    final kos = item['kos'] as Map?;
    return _toInt(kos?['id'] ?? item['kos_id'] ?? item['id_kos']);
  }

  String _imageUrlFromAny(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is Map) {
      return _toString(
          raw['url'] ?? raw['path'] ?? raw['image'] ?? raw['image_url']);
    }
    return _toString(raw);
  }

  String _thumbUrlFromItem(dynamic item) {
    if (item is! Map) return '';
    final kos = item['kos'] as Map?;

    // direct keys
    final direct = _pickMapString(kos, [
      'thumbnail',
      'thumbnail_url',
      'image',
      'image_url',
      'foto',
      'gambar',
      'url',
    ]);
    if (direct.isNotEmpty) return normalizeUkkImageUrl(direct);

    // images list
    final images =
        kos?['images'] ?? kos?['gambar'] ?? kos?['photos'] ?? kos?['foto_kos'];
    if (images is List && images.isNotEmpty) {
      final first = _imageUrlFromAny(images.first);
      if (first.trim().isNotEmpty) return normalizeUkkImageUrl(first);
    }

    // fallback from item
    final fallback =
        _pickMapString(item, ['kos_image', 'image', 'image_url', 'thumbnail']);
    return fallback.isEmpty ? '' : normalizeUkkImageUrl(fallback);
  }

  Future<String?> _thumbFuture(int kosId) {
    return _thumbFutureByKosId.putIfAbsent(
      kosId,
      () => OwnerImageKosService.getFirstImageUrl(
          token: widget.token, kosId: kosId),
    );
  }

  Future<void> _printReceipt({required Map item}) async {
    try {
      final normalized = BookingReceiptData.normalizeBooking(item);
      final bytes = await BookingReceiptPdf.build(
        booking: normalized,
        societyName: null,
        isOwnerReceipt: true,
      );

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'bukti-booking.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal cetak nota: $e')),
      );
    }
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

  bool _isRejectedStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('reject') ||
        s.contains('rejected') ||
        s.contains('tolak');
  }

  bool _isAcceptedStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s.contains('accept') ||
        s.contains('accepted') ||
        s.contains('terima') ||
        s.contains('diterima');
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

  Widget _thumbWithBadge(
    BuildContext context, {
    required Widget thumb,
    required String status,
  }) {
    final cs = Theme.of(context).colorScheme;
    final icon = _badgeIconForStatus(status);
    final color = _badgeColorForStatus(context, status);

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: thumb),
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

  Widget _placeholderThumb() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.image),
    );
  }

  Widget _networkThumb(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderThumb(),
      ),
    );
  }

  bool _isEndedBooking(dynamic item) {
    final status = _statusFromItem(item);
    if (_isTerminalStatus(status)) return true;

    if (item is! Map) return false;
    final end = _parseDate(item['end_date'] ?? item['tanggal_selesai']);
    if (end == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return today.isAfter(endDay);
  }

  String _pickMapString(Map? map, List<String> keys) {
    if (map == null) return '';
    for (final key in keys) {
      final v = map[key];
      final s = _toString(v).trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _kosNameFromItem(dynamic item) {
    if (item is Map) {
      final kos = item['kos'] as Map?;
      final s = _pickMapString(kos, ['name', 'nama_kos']);
      if (s.isNotEmpty) return s;
      final alt = _pickMapString(item, ['kos_name', 'nama_kos', 'name']);
      if (alt.isNotEmpty) return alt;
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
      return _pickMapString(item, ['user_name', 'society_name']);
    }
    return '';
  }

  String _statusFromItem(dynamic item) {
    if (item is Map) {
      final s = _toString(item['status'] ?? item['booking_status']).trim();
      return s.isEmpty ? '-' : s;
    }
    return '-';
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

  int? _bookingIdFromItem(dynamic item) {
    if (item is Map) {
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

      return _toInt(item['id']);
    }
    return null;
  }

  String _fmtYyyyMm(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  String _formatDateShort(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterStart ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _filterStart = picked);
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterEnd ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _filterEnd = picked);
    }
  }

  Future<List<dynamic>> _loadHistory() async {
    // Ambil 12 bulan terakhir (termasuk bulan ini) untuk membentuk "history".
    final now = DateTime.now();
    final months = <String>[];
    for (int i = 0; i < 12; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      months.add(_fmtYyyyMm(d));
    }

    final merged = <dynamic>[];
    for (final m in months) {
      final list = await OwnerBookingService.getBookings(
        token: widget.token,
        month: m,
        status: 'all',
      );
      merged.addAll(list);
    }

    // Dedupe: prefer bookingId.
    final seen = <String>{};
    final out = <dynamic>[];

    for (final raw in merged) {
      // History hanya booking yang sudah selesai.
      if (!_isEndedBooking(raw)) continue;
      final id = _bookingIdFromItem(raw);
      final key = (id != null)
          ? 'id:$id'
          : 'k:${_kosNameFromItem(raw)}|u:${_societyNameFromItem(raw)}|d:${_dateRangeFromItem(raw)}|s:${_statusFromItem(raw).toLowerCase()}';
      if (seen.add(key)) out.add(raw);
    }

    // Sort kira-kira terbaru dulu berdasarkan string start_date kalau tersedia.
    out.sort((a, b) {
      final aMap = a is Map ? a : null;
      final bMap = b is Map ? b : null;
      final aUpdated = _toString(aMap?['updated_at'] ?? aMap?['updatedAt']).trim();
      final bUpdated = _toString(bMap?['updated_at'] ?? bMap?['updatedAt']).trim();
      final aCreated = _toString(aMap?['created_at'] ?? aMap?['createdAt']).trim();
      final bCreated = _toString(bMap?['created_at'] ?? bMap?['createdAt']).trim();
      final aStart = _toString(aMap?['start_date'] ?? aMap?['tanggal_mulai']).trim();
      final bStart = _toString(bMap?['start_date'] ?? bMap?['tanggal_mulai']).trim();

      // Prefer updated_at, then created_at, then start_date.
      final c1 = bUpdated.compareTo(aUpdated);
      if (c1 != 0 && (aUpdated.isNotEmpty || bUpdated.isNotEmpty)) return c1;

      final c2 = bCreated.compareTo(aCreated);
      if (c2 != 0 && (aCreated.isNotEmpty || bCreated.isNotEmpty)) return c2;

      final c3 = bStart.compareTo(aStart);
      if (c3 != 0) return c3;
      return _kosNameFromItem(a)
          .toLowerCase()
          .compareTo(_kosNameFromItem(b).toLowerCase());
    });

    return out;
  }

  void _refresh() {
    setState(() {
      _future = _loadHistory();
    });
  }

  bool _matchesStatus(dynamic item) {
    final normalized = _status.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'all') return true;

    final itemStatus = _statusFromItem(item).trim().toLowerCase();
    if (itemStatus.isEmpty) return false;

    // Beberapa backend bisa return accepted/rejected.
    if (normalized == 'accept') {
      return itemStatus == 'accept' ||
          itemStatus == 'accepted' ||
          itemStatus.contains('terima') ||
          itemStatus.contains('accept');
    }
    if (normalized == 'reject') {
      return itemStatus == 'reject' ||
          itemStatus == 'rejected' ||
          itemStatus.contains('tolak') ||
          itemStatus.contains('reject');
    }

    return itemStatus.contains(normalized);
  }

  bool _matchesSearch(dynamic item) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final kos = _kosNameFromItem(item).toLowerCase();
    final soc = _societyNameFromItem(item).toLowerCase();
    final status = _statusFromItem(item).toLowerCase();
    return kos.contains(q) || soc.contains(q) || status.contains(q);
  }

  bool _matchesDateRange(dynamic item) {
    if (_filterStart == null && _filterEnd == null) return true;
    // Try to parse a start date from the item (start_date, tanggal_mulai, created_at)
    DateTime? start = _parseDate(item['start_date'] ?? item['tanggal_mulai'] ?? item['created_at'] ?? item['createdAt'] ?? item['date']);
    if (start == null) return true; // if no date on item, don't exclude

    final s = DateTime(start.year, start.month, start.day);
    if (_filterStart != null) {
      final fs = DateTime(_filterStart!.year, _filterStart!.month, _filterStart!.day);
      if (s.isBefore(fs)) return false;
    }
    if (_filterEnd != null) {
      final fe = DateTime(_filterEnd!.year, _filterEnd!.month, _filterEnd!.day);
      if (s.isAfter(fe)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pageBg = Color.lerp(Colors.white, _accentPurple, 0.07)!;
    final softLavender = Color.lerp(Colors.white, _accentPurple, 0.08)!;
    final fieldFill = Color.lerp(Colors.white, _accentPurple, 0.10)!;

    InputDecoration inputDecoration({
      required String label,
      required IconData icon,
      String? hint,
      Widget? suffix,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: fieldFill,
        isDense: true,
        prefixIcon: Icon(icon, color: _accentPurple),
        suffixIcon: suffix,
        labelStyle: const TextStyle(color: _accentPurple),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accentPurple.withOpacity(0.22)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accentPurple.withOpacity(0.22)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accentPurple, width: 2),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: Navigator.of(context).canPop()
              ? () => Navigator.of(context).pop()
              : null,
        ),
        title: const Text('History Booking'),
        backgroundColor: _accentPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: softLavender,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accentPurple.withOpacity(0.18)),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: inputDecoration(
                      label: 'Cari kos / penyewa / status',
                      icon: Icons.search,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: inputDecoration(
                      label: 'Status',
                      icon: Icons.tune,
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
                  },
                ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickStartDate,
                          child: AbsorbPointer(
                            child: TextFormField(
                              readOnly: true,
                              decoration: inputDecoration(
                                label: 'Mulai',
                                icon: Icons.date_range,
                                suffix: _filterStart != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        color: _accentPurple,
                                        onPressed: () => setState(() => _filterStart = null),
                                      )
                                    : null,
                              ),
                              controller:
                                  TextEditingController(text: _formatDateShort(_filterStart)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickEndDate,
                          child: AbsorbPointer(
                            child: TextFormField(
                              readOnly: true,
                              decoration: inputDecoration(
                                label: 'Selesai',
                                icon: Icons.event,
                                suffix: _filterEnd != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        color: _accentPurple,
                                        onPressed: () => setState(() => _filterEnd = null),
                                      )
                                    : null,
                              ),
                              controller:
                                  TextEditingController(text: _formatDateShort(_filterEnd)),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }

                final raw = snapshot.data ?? const [];
                final data = raw
                  .where(_matchesStatus)
                  .where(_matchesSearch)
                  .where(_matchesDateRange)
                  .toList();

                if (data.isEmpty) {
                  return Center(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: softLavender,
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: _accentPurple.withOpacity(0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, color: _accentPurple),
                          const SizedBox(width: 10),
                          Text(
                            'Belum ada booking',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    _refresh();
                    await _future;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = data[index];
                      final kosName = _kosNameFromItem(item);
                      final dateRange = _dateRangeFromItem(item);
                      final status = _statusFromItem(item);

                      final title = kosName;
                      final kosId = _kosIdFromItem(item);
                      final directThumbUrl = _thumbUrlFromItem(item);

                      Widget leading;
                      if (directThumbUrl.isNotEmpty) {
                        final url = normalizeImageUrl(directThumbUrl);
                        leading = _thumbWithBadge(
                          context,
                          thumb: _networkThumb(url),
                          status: status,
                        );
                      } else if (kosId == null) {
                        leading = _thumbWithBadge(
                          context,
                          thumb: _placeholderThumb(),
                          status: status,
                        );
                      } else {
                        leading = FutureBuilder<String?>(
                          future: _thumbFuture(kosId),
                          builder: (context, snap) {
                            final raw = (snap.data ?? '').toString();
                            final url = normalizeImageUrl(raw);
                            final thumb = url.isEmpty
                                ? _placeholderThumb()
                                : _networkThumb(url);
                            return _thumbWithBadge(
                              context,
                              thumb: thumb,
                              status: status,
                            );
                          },
                        );
                      }

                      return Card(
                        elevation: 0,
                        color: softLavender,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: _accentPurple.withOpacity(0.16),
                          ),
                        ),
                        child: ListTile(
                          leading: leading,
                          title: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '$dateRange\nStatus: $status',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withOpacity(0.72),
                                ),
                          ),
                          isThreeLine: true,
                          onTap: () {
                            if (item is! Map) return;
                            final name = _societyNameFromItem(item);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookingReceiptPreviewPage(
                                  booking: item,
                                  societyName: name,
                                  token: widget.token,
                                  isOwner: true,
                                ),
                              ),
                            );
                          },
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.print),
                                tooltip: 'Cetak nota',
                                color: _accentPurple,
                                onPressed: () {
                                  if (item is Map) {
                                    _printReceipt(item: item);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
