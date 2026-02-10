import 'package:flutter/material.dart';
import 'package:koshunter6/services/society/booking_service.dart';
import 'package:koshunter6/services/society/society_image_kos_service.dart';
import 'package:koshunter6/services/auth_service.dart';
import '../../../utils/image_url.dart';
import '../../../utils/booking_receipt_pdf.dart';
import '../../../utils/booking_receipt_data.dart';
import 'package:printing/printing.dart';
import 'booking_receipt_preview_page.dart';

class BookingHistoryPage extends StatefulWidget {
  final String token;
  final String status;

  const BookingHistoryPage({
    super.key,
    required this.token,
    required this.status,
  });

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  static const Color _accentPurple = Color(0xFF7D86BF);

  late Future<List<dynamic>> _future;
  late Future<String?> _userNameFuture;

  DateTime? _selectedDate;
  String _statusFilter = 'all';
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  final Map<int, Future<String?>> _thumbFutureByKosId = {};

  int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String _toString(dynamic value) => value?.toString() ?? '';

  DateTime? _parseDate(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _fmtYyyyMmDd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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

  bool _isPendingStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return true;
    return s.contains('pending') ||
        s.contains('wait') ||
        s.contains('menunggu') ||
        s.contains('request') ||
        s.contains('diajukan');
  }

  IconData _badgeIconForStatus(String status) {
    if (_isRejectedStatus(status)) return Icons.cancel_outlined;
    if (_isAcceptedStatus(status)) return Icons.check_circle_outline;
    if (_isTerminalStatus(status)) return Icons.done_all;
    if (_isPendingStatus(status)) return Icons.hourglass_top_rounded;
    return Icons.info_outline;
  }

  Color _badgeColorForStatus(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    if (_isRejectedStatus(status)) return Colors.redAccent;
    if (_isAcceptedStatus(status)) return Colors.green;
    if (_isTerminalStatus(status)) return Colors.blueGrey;
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
          thumb,
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

  Widget _placeholderThumb(
    BuildContext context, {
    IconData icon = Icons.image,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 56,
        height: 56,
        color: cs.surfaceVariant,
        alignment: Alignment.center,
        child: Icon(icon, color: cs.onSurfaceVariant),
      ),
    );
  }

  String _statusFromItem(dynamic item) {
    if (item is Map) {
      final s = _toString(item['status'] ?? item['booking_status']).trim();
      return s.isEmpty ? '-' : s;
    }
    return '-';
  }

  bool _matchesStatusFilter(dynamic item) {
    final selected = _statusFilter.trim().toLowerCase();
    if (selected.isEmpty || selected == 'all') return true;
    final status = _statusFromItem(item);

    switch (selected) {
      case 'pending':
        return _isPendingStatus(status) &&
            !_isAcceptedStatus(status) &&
            !_isRejectedStatus(status) &&
            !_isTerminalStatus(status);
      case 'accepted':
        return _isAcceptedStatus(status) && !_isTerminalStatus(status);
      case 'rejected':
        return _isRejectedStatus(status);
      default:
        // fallback contains match
        return status.toLowerCase().contains(selected);
    }
  }

  bool _matchesDateFilter(dynamic item) {
    if (_selectedDate == null) return true;
    if (item is! Map) return true;
    final start = _parseDate(item['start_date'] ?? item['tanggal_mulai']);
    final end = _parseDate(item['end_date'] ?? item['tanggal_selesai']);
    if (start == null && end == null) return true;

    final d = _selectedDate!;
    final day = DateTime(d.year, d.month, d.day);
    final startDay = start == null
        ? null
        : DateTime(start.year, start.month, start.day);
    final endDay = end == null ? null : DateTime(end.year, end.month, end.day);

    if (startDay != null && endDay != null) {
      return !day.isBefore(startDay) && !day.isAfter(endDay);
    }
    if (startDay != null) {
      return day.isAtSameMomentAs(startDay);
    }
    if (endDay != null) {
      return day.isAtSameMomentAs(endDay);
    }
    return true;
  }

  bool _isActiveAcceptedBookingToday(dynamic item) {
    if (item is! Map) return false;
    final status = _statusFromItem(item);
    if (!_isAcceptedStatus(status)) return false;
    if (_isTerminalStatus(status)) return false;

    final start = _parseDate(item['start_date'] ?? item['tanggal_mulai']);
    final end = _parseDate(item['end_date'] ?? item['tanggal_selesai']);
    if (start == null || end == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return !today.isBefore(startDay) && !today.isAfter(endDay);
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
      final kos = (item['kos'] is Map) ? (item['kos'] as Map) : null;
      final s = _pickMapString(kos, ['name', 'nama_kos', 'nama']);
      if (s.isNotEmpty) return s;
      final s2 = _pickMapString(item as Map?, [
        'kos_name',
        'nama_kos',
        'name',
        'kosName',
      ]);
      if (s2.isNotEmpty) return s2;
    }
    return 'Kos';
  }

  Future<String?> _thumbFuture(int kosId) {
    return _thumbFutureByKosId.putIfAbsent(
      kosId,
      () => SocietyImageKosService.getFirstImageUrl(
        token: widget.token,
        kosId: kosId,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _userNameFuture = AuthService.getUserName();
    _selectedDate = null;
    _dateController.text = '';
    final rawInitialStatus = widget.status.trim().toLowerCase();
    final allowed = <String>{'all', 'pending', 'accepted', 'rejected'};
    String mapped;
    if (rawInitialStatus.isEmpty || rawInitialStatus == 'all') {
      mapped = 'all';
    } else if (rawInitialStatus == 'menunggu' ||
        rawInitialStatus.contains('pending')) {
      mapped = 'pending';
    } else if (rawInitialStatus == 'diterima' ||
        rawInitialStatus.contains('accept')) {
      mapped = 'accepted';
    } else if (rawInitialStatus == 'ditolak' ||
        rawInitialStatus.contains('reject') ||
        rawInitialStatus.contains('tolak')) {
      mapped = 'rejected';
    } else if (rawInitialStatus == 'selesai' ||
        rawInitialStatus.contains('done') ||
        rawInitialStatus.contains('finish')) {
      // Done/selesai is treated as part of full history; no dedicated filter.
      mapped = 'all';
    } else {
      mapped = rawInitialStatus;
    }
    _statusFilter = allowed.contains(mapped) ? mapped : 'all';
    _future = BookingService.getBookingHistory(
      token: widget.token,
      status: 'all',
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(dynamic item) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final kos = _kosNameFromItem(item).toLowerCase();
    final status = _statusFromItem(item).toLowerCase();
    final id = _toString(item is Map ? (item['booking_id'] ?? item['id']) : null).toLowerCase();
    return kos.contains(q) || status.contains(q) || id.contains(q);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = BookingService.getBookingHistory(
        token: widget.token,
        status: 'all',
      );
    });
    await _future;
  }

  Future<void> _pickDate() async {
    final base = _selectedDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _dateController.text = _fmtYyyyMmDd(_selectedDate!);
    });
  }

  Future<void> _printReceipt({required Map item}) async {
    try {
      final name = (await _userNameFuture) ?? '';
      final enriched = await BookingReceiptData.enrich(
        booking: item,
        token: widget.token,
        isOwner: false,
      );
      final bytes = await BookingReceiptPdf.build(
        booking: enriched,
        societyName: name,
      );

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'bukti-booking.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal cetak nota: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Booking History';
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
        title: Text(title),
        backgroundColor: _accentPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
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
                      label: 'Cari kos / status / id',
                      icon: Icons.search,
                      hint: 'Cari berdasarkan nama kos, status, atau id',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dateController,
                          style: const TextStyle(color: Colors.black),
                          readOnly: true,
                          onTap: _pickDate,
                          decoration: inputDecoration(
                            label: 'Tanggal (tgl)',
                            hint: 'Semua tanggal',
                            icon: Icons.calendar_month,
                            suffix: _selectedDate == null
                                ? null
                                : IconButton(
                                    tooltip: 'Hapus tanggal',
                                    icon: const Icon(Icons.close),
                                    color: cs.onSurface.withOpacity(0.72),
                                    onPressed: () {
                                      setState(() {
                                        _selectedDate = null;
                                        _dateController.text = '';
                                      });
                                    },
                                  ),
                          ).copyWith(
                            labelStyle: const TextStyle(color: Colors.black),
                            floatingLabelStyle:
                                const TextStyle(color: Colors.black),
                            hintStyle: const TextStyle(color: Colors.black),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _statusFilter,
                          decoration: inputDecoration(
                            label: 'Status',
                            icon: Icons.tune,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All')),
                            DropdownMenuItem(
                              value: 'pending',
                              child: Text('Pending'),
                            ),
                            DropdownMenuItem(
                              value: 'accepted',
                              child: Text('Accepted'),
                            ),
                            DropdownMenuItem(
                              value: 'rejected',
                              child: Text('Rejected'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _statusFilter = v;
                            });
                          },
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

                final data = snapshot.data ?? const <dynamic>[];
                // Show all booking records (do not dedupe), so the same kos can
                // appear multiple times if it was booked multiple times.
                final filtered = data
                    .where(_matchesStatusFilter)
                    .where(_matchesDateFilter)
                    .where(_matchesSearch)
                    .where((it) => !_isActiveAcceptedBookingToday(it))
                    .toList();

                filtered.sort((a, b) {
                  final aMap = a is Map ? a : null;
                  final bMap = b is Map ? b : null;
                  final aBooking = (aMap?['booking'] is Map) ? (aMap?['booking'] as Map) : null;
                  final bBooking = (bMap?['booking'] is Map) ? (bMap?['booking'] as Map) : null;

                  final aUpdRaw = _toString(
                    aMap?['updated_at'] ?? aMap?['updatedAt'] ?? aBooking?['updated_at'] ?? aBooking?['updatedAt'],
                  ).trim();
                  final bUpdRaw = _toString(
                    bMap?['updated_at'] ?? bMap?['updatedAt'] ?? bBooking?['updated_at'] ?? bBooking?['updatedAt'],
                  ).trim();
                  final aUpdDt = _parseDate(aUpdRaw);
                  final bUpdDt = _parseDate(bUpdRaw);

                  if (aUpdDt != null && bUpdDt != null) {
                    final c = bUpdDt.compareTo(aUpdDt);
                    if (c != 0) return c;
                  } else {
                    final c = bUpdRaw.compareTo(aUpdRaw);
                    if (c != 0 && (aUpdRaw.isNotEmpty || bUpdRaw.isNotEmpty)) return c;
                  }

                  // Fallback to created_at then start_date
                  final aCreated = _toString(
                    aMap?['created_at'] ?? aMap?['createdAt'] ?? aBooking?['created_at'] ?? aBooking?['createdAt'],
                  ).trim();
                  final bCreated = _toString(
                    bMap?['created_at'] ?? bMap?['createdAt'] ?? bBooking?['created_at'] ?? bBooking?['createdAt'],
                  ).trim();
                  final c2 = bCreated.compareTo(aCreated);
                  if (c2 != 0 && (aCreated.isNotEmpty || bCreated.isNotEmpty)) return c2;

                  final aStart = _toString(aMap?['start_date'] ?? aMap?['tanggal_mulai']).trim();
                  final bStart = _toString(bMap?['start_date'] ?? bMap?['tanggal_mulai']).trim();
                  final c3 = bStart.compareTo(aStart);
                  if (c3 != 0) return c3;
                  final aId = _toInt(aMap?['id'] ?? aMap?['booking_id']) ?? 0;
                  final bId = _toInt(bMap?['id'] ?? bMap?['booking_id']) ?? 0;
                  return bId.compareTo(aId);
                });

                if (filtered.isEmpty) {
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
                            'Tidak ada data',
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
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final kos = (item is Map && item['kos'] is Map)
                          ? (item['kos'] as Map)
                          : null;
                      final title = _kosNameFromItem(item);
                      final start = (item is Map)
                          ? (item['start_date'] ?? item['tanggal_mulai'] ?? '-')
                          : '-';
                      final end = (item is Map)
                          ? (item['end_date'] ?? item['tanggal_selesai'] ?? '-')
                          : '-';
                      final status = (item is Map)
                          ? (item['status'] ?? item['booking_status'] ?? '-')
                          : '-';
                      final kosId = (item is Map)
                          ? _toInt(kos?['id'] ?? item['kos_id'])
                          : null;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: softLavender,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: _accentPurple.withOpacity(0.16),
                          ),
                        ),
                        child: ListTile(
                          leading: (kosId == null)
                              ? _thumbWithBadge(
                                  context,
                                  thumb: _placeholderThumb(context),
                                  status: status.toString(),
                                )
                              : FutureBuilder<String?>(
                                  future: _thumbFuture(kosId),
                                  builder: (context, snap) {
                                    final raw = (snap.data ?? '').toString();
                                    final url = normalizeImageUrl(raw);
                                    if (url.isEmpty) {
                                      return _thumbWithBadge(
                                        context,
                                        thumb: _placeholderThumb(context),
                                        status: status.toString(),
                                      );
                                    }
                                    final imageThumb = ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        url,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _placeholderThumb(
                                              context,
                                              icon: Icons.broken_image,
                                            ),
                                      ),
                                    );
                                    return _thumbWithBadge(
                                      context,
                                      thumb: imageThumb,
                                      status: status.toString(),
                                    );
                                  },
                                ),
                          title: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '$start - $end\nStatus: $status',
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookingReceiptPreviewPage(
                                  booking: item,
                                  token: widget.token,
                                  isOwner: false,
                                ),
                              ),
                            );
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.print),
                            tooltip: 'Cetak nota',
                            color: _accentPurple,
                            onPressed: () {
                              if (item is Map) {
                                _printReceipt(item: item);
                              }
                            },
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
