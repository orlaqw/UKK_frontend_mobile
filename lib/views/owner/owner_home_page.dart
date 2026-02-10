import 'package:flutter/material.dart';
import 'package:koshunter6/services/auth_service.dart';
import 'package:koshunter6/services/owner/owner_booking_service.dart';
import 'package:koshunter6/services/owner/owner_image_kos_service.dart';
import 'package:koshunter6/services/owner/owner_kos_service.dart';
import 'package:koshunter6/utils/image_url.dart';
import 'package:koshunter6/views/society/bookings/booking_receipt_preview_page.dart';
import 'package:koshunter6/views/owner/master_kos/master_kos_page.dart';
import 'package:koshunter6/views/owner/reviews/owner_all_reviews_page.dart';
import 'package:koshunter6/widgets/booking_notification_dialog.dart';

class OwnerHomePage extends StatefulWidget {
  const OwnerHomePage({super.key});

  @override
  State<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends State<OwnerHomePage> {
  late Future<String?> _userNameFuture;
  late Future<String?> _tokenFuture;
  late Future<Map<int, String>> _kosNameByIdFuture;
  late Future<List<_OwnerActiveBooking>> _activeBookingsFuture;
  late Future<List<_OwnerIncomingBooking>> _incomingBookingsFuture;
  final Map<int, Future<String?>> _thumbFutureByKosId = {};
  final Set<int> _updatingBookingIds = {};
  bool _forcedLogoutScheduled = false;

  bool _isUnauthorizedError(Object? error) {
    final s = (error ?? '').toString().toLowerCase();
    return s.contains('(401') ||
        s.contains('unauthorized') ||
        s.contains('token tidak ditemukan') ||
        s.contains('token invalid');
  }

  void _forceLogoutAfterFrame(BuildContext context) {
    if (_forcedLogoutScheduled) return;
    _forcedLogoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi login sudah tidak valid. Silakan login ulang.'),
        ),
      );
      await _logout(context, confirm: false);
    });
  }

  @override
  void initState() {
    super.initState();
    _userNameFuture = AuthService.getUserName();
    _tokenFuture = AuthService.getToken();
    _kosNameByIdFuture = _loadKosNameById();
    _incomingBookingsFuture = _loadIncomingBookings();
    _activeBookingsFuture = _loadActiveBookings();
  }

  bool _hasTenantName(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    if (lower == '-' || lower == 'null' || lower == 'undefined') return false;
    return true;
  }

  Future<Map<int, String>> _loadKosNameById() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.trim().isEmpty) return <int, String>{};
      final list = await OwnerKosService.getKos(token: token);
      final out = <int, String>{};
      for (final it in list) {
        if (it is! Map) continue;
        final id = _toInt(it['id'] ?? it['kos_id'] ?? it['id_kos']);
        if (id == null || id <= 0) continue;
        final name = _toString(
          it['name'] ?? it['nama_kos'] ?? it['nama'],
        ).trim();
        if (name.isNotEmpty) out[id] = name;
      }
      return out;
    } catch (_) {
      return <int, String>{};
    }
  }

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

  Map<String, dynamic> _toStringKeyedMap(Map raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      out[k.toString()] = v;
    });
    return out;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;

    // Handle unix timestamp (seconds/millis)
    if (value is int || value is num) {
      final n = (value is int) ? value : (value as num).toInt();
      if (n <= 0) return null;
      // Heuristic: >= 1e12 is milliseconds
      final ms = (n >= 1000000000000) ? n : n * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    // Fast path: ISO-8601 (and several Dart-supported variants)
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;

    // Normalize common backend format: "YYYY-MM-DD HH:mm:ss(.SSS)"
    final normalizedSpace = raw.contains(' ') && !raw.contains('T')
        ? raw.replaceFirst(' ', 'T')
        : raw;
    final normalizedTry = DateTime.tryParse(normalizedSpace);
    if (normalizedTry != null) return normalizedTry;

    // Handle Indonesian common format: "DD/MM/YYYY" or "DD-MM-YYYY" (optional time)
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
    return s.contains('reject') ||
        s.contains('tolak') ||
        s.contains('cancel') ||
        s.contains('batal') ||
        s.contains('done') ||
        s.contains('finish') ||
        s.contains('selesai') ||
        s.contains('complete');
  }

  bool _isAcceptedStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return false;
    return s == 'accept' ||
        s == 'accepted' ||
        s.contains('accept') ||
        s.contains('approve') ||
        s.contains('terima') ||
        s.contains('diterima');
  }

  bool _isIncomingStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) {
      return true; // beberapa backend mengosongkan status saat request
    }
    if (_isTerminalStatus(s)) return false;
    if (_isAcceptedStatus(s)) return false;
    return s.contains('pending') ||
        s.contains('wait') ||
        s.contains('menunggu') ||
        s.contains('request') ||
        s.contains('diajukan') ||
        s.contains('baru');
  }

  int? _bookingIdFromItem(dynamic item) {
    if (item is Map) {
      final direct = _toInt(
        item['booking_id'] ??
            item['id_booking'] ??
            item['bookingId'] ??
            item['idBooking'] ??
            item['id'],
      );
      if (direct != null) return direct;
      final nested = item['booking'];
      if (nested is Map) {
        return _toInt(
          nested['booking_id'] ??
              nested['id_booking'] ??
              nested['id'] ??
              nested['bookingId'] ??
              nested['idBooking'],
        );
      }
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
      return _toInt(item['kos_id'] ?? item['id_kos'] ?? item['kosId']);
    }
    return null;
  }

  Future<String?> _thumbFuture(int kosId, {required String token}) {
    return _thumbFutureByKosId.putIfAbsent(kosId, () async {
      try {
        return await OwnerImageKosService.getFirstImageUrl(
          token: token,
          kosId: kosId,
        );
      } catch (_) {
        return null;
      }
    });
  }

  Widget _thumbWidget(BuildContext context, {required int kosId}) {
    Widget placeholder({bool broken = false}) {
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

    return FutureBuilder<String?>(
      future: _tokenFuture,
      builder: (context, tokenSnap) {
        final token = (tokenSnap.data ?? '').trim();
        if (token.isEmpty) return placeholder();

        return FutureBuilder<String?>(
          future: _thumbFuture(kosId, token: token),
          builder: (context, snap) {
            final raw = (snap.data ?? '').toString();
            final url = normalizeUkkImageUrl(raw);
            if (url.isEmpty) return placeholder();
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder(broken: true),
              ),
            );
          },
        );
      },
    );
  }

  _OwnerActiveBooking? _mapToActiveBooking(dynamic item) {
    if (item is! Map) return null;

    final source = _toStringKeyedMap(item);

    final bookingId = _bookingIdFromItem(item);
    final kosId = _kosIdFromItem(item);
    final status = _toString(item['status'] ?? item['booking_status']).trim();
    final start = _parseDate(item['start_date'] ?? item['tanggal_mulai']);
    final end = _parseDate(item['end_date'] ?? item['tanggal_selesai']);

    final nestedBooking = (item['booking'] is Map)
        ? (item['booking'] as Map)
        : null;
    final updatedAt = _parseDate(
      item['updated_at'] ??
          item['updatedAt'] ??
          nestedBooking?['updated_at'] ??
          nestedBooking?['updatedAt'],
    );
    final createdAt = _parseDate(
      item['created_at'] ??
          item['createdAt'] ??
          nestedBooking?['created_at'] ??
          nestedBooking?['createdAt'],
    );

    final kosRaw = item['kos'];
    final kos = (kosRaw is Map) ? kosRaw : null;
    final kosName = _pickMapString(kos, ['name', 'nama_kos', 'nama']).isNotEmpty
        ? _pickMapString(kos, ['name', 'nama_kos', 'nama'])
        : _pickMapString(item, ['kos_name', 'nama_kos', 'kosName', 'name']);

    final user = item['user'] as Map?;
    final society = item['society'] as Map?;
    final societyName = _pickMapString(user, ['name', 'nama']).isNotEmpty
        ? _pickMapString(user, ['name', 'nama'])
        : (_pickMapString(society, ['name', 'nama']).isNotEmpty
              ? _pickMapString(society, ['name', 'nama'])
              : _pickMapString(item, ['user_name', 'society_name']));

    if (start == null || end == null) return null;
    if (_isTerminalStatus(status)) return null;
    if (!_isAcceptedStatus(status)) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final isActive = !today.isBefore(startDay) && !today.isAfter(endDay);
    if (!isActive) return null;

    return _OwnerActiveBooking(
      source: source,
      bookingId: bookingId,
      kosId: kosId,
      kosName: kosName.trim().isEmpty ? 'Kos' : kosName.trim(),
      societyName: societyName.trim(),
      startDate: start,
      endDate: end,
      status: status.isEmpty ? '-' : status,
      updatedAt: updatedAt,
      createdAt: createdAt,
    );
  }

  _OwnerIncomingBooking? _mapToIncomingBooking(dynamic item) {
    if (item is! Map) return null;

    final bookingId = _bookingIdFromItem(item);
    final kosId = _kosIdFromItem(item);
    final status = _toString(item['status'] ?? item['booking_status']).trim();
    if (!_isIncomingStatus(status)) return null;

    final start = _parseDate(item['start_date'] ?? item['tanggal_mulai']);
    final end = _parseDate(item['end_date'] ?? item['tanggal_selesai']);

    final kosRaw = item['kos'];
    final kos = (kosRaw is Map) ? kosRaw : null;
    final kosName = _pickMapString(kos, ['name', 'nama_kos', 'nama']).isNotEmpty
        ? _pickMapString(kos, ['name', 'nama_kos', 'nama'])
        : _pickMapString(item, ['kos_name', 'nama_kos', 'kosName', 'name']);

    final user = item['user'] as Map?;
    final society = item['society'] as Map?;
    final societyName = _pickMapString(user, ['name', 'nama']).isNotEmpty
        ? _pickMapString(user, ['name', 'nama'])
        : (_pickMapString(society, ['name', 'nama']).isNotEmpty
              ? _pickMapString(society, ['name', 'nama'])
              : _pickMapString(item, ['user_name', 'society_name']));

    return _OwnerIncomingBooking(
      bookingId: bookingId,
      kosId: kosId,
      kosName: kosName.trim().isEmpty ? 'Kos' : kosName.trim(),
      societyName: societyName.trim(),
      startDate: start,
      endDate: end,
      status: status.isEmpty ? '-' : status,
    );
  }

  Future<List<_OwnerIncomingBooking>> _loadIncomingBookings() async {
    final token = await AuthService.getToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Token tidak ditemukan');
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = <DateTime>[
      today.subtract(const Duration(days: 1)),
      today,
      today.add(const Duration(days: 1)),
    ];

    final results = await Future.wait(
      dates.map((d) {
        final tgl =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        return OwnerBookingService.getBookings(
          token: token,
          tgl: tgl,
          status: 'all',
        );
      }),
    );

    final merged = <dynamic>[];
    for (final list in results) {
      merged.addAll(list);
    }

    final seen = <String>{};
    final out = <_OwnerIncomingBooking>[];
    for (final raw in merged) {
      final mapped = _mapToIncomingBooking(raw);
      if (mapped == null) continue;
      final key = (mapped.bookingId != null)
          ? 'id:${mapped.bookingId}'
          : 'k:${mapped.kosName}|s:${mapped.startText}|e:${mapped.endText}|u:${mapped.societyName}|st:${mapped.status.toLowerCase()}';
      if (seen.add(key)) out.add(mapped);
    }

    out.sort((a, b) {
      // Urutkan yang paling baru masuk (tanggal mulai paling dekat) di atas.
      final ad = a.startDate ?? DateTime(2100);
      final bd = b.startDate ?? DateTime(2100);
      final c = ad.compareTo(bd);
      if (c != 0) return c;
      return a.kosName.toLowerCase().compareTo(b.kosName.toLowerCase());
    });

    return out;
  }

  void _refreshIncomingBookings() {
    setState(() {
      _kosNameByIdFuture = _loadKosNameById();
      _incomingBookingsFuture = _loadIncomingBookings();
    });
  }

  Future<List<_OwnerActiveBooking>> _loadActiveBookings() async {
    final token = await AuthService.getToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Token tidak ditemukan');
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = <DateTime>[
      today.subtract(const Duration(days: 1)),
      today,
      today.add(const Duration(days: 1)),
    ];

    final results = await Future.wait(
      dates.map((d) {
        final tgl =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        return OwnerBookingService.getBookings(
          token: token,
          tgl: tgl,
          status: 'all',
        );
      }),
    );

    final merged = <dynamic>[];
    for (final list in results) {
      merged.addAll(list);
    }

    final seen = <String>{};
    final out = <_OwnerActiveBooking>[];

    for (final raw in merged) {
      final mapped = _mapToActiveBooking(raw);
      if (mapped == null) continue;
      final key = (mapped.bookingId != null)
          ? 'id:${mapped.bookingId}'
          : 'k:${mapped.kosName}|s:${mapped.startDate.toIso8601String()}|e:${mapped.endDate.toIso8601String()}|u:${mapped.societyName}|st:${mapped.status.toLowerCase()}';
      if (seen.add(key)) out.add(mapped);
    }

    out.sort((a, b) {
      final aKey = a.updatedAt ?? a.createdAt ?? a.startDate;
      final bKey = b.updatedAt ?? b.createdAt ?? b.startDate;
      final c = bKey.compareTo(aKey);
      if (c != 0) return c;
      return a.kosName.toLowerCase().compareTo(b.kosName.toLowerCase());
    });

    return out;
  }

  void _refreshActiveBookings() {
    setState(() {
      _kosNameByIdFuture = _loadKosNameById();
      _activeBookingsFuture = _loadActiveBookings();
    });
  }

  Future<bool> _confirmIncomingUpdate({
    required String status,
    required String kosName,
    required String societyName,
    required String startText,
    required String endText,
  }) async {
    if (!mounted) return false;

    final normalized = status.trim().toLowerCase();
    final isAccept = normalized == 'accept' || normalized.contains('accept');
    final label = isAccept ? 'Terima' : 'Tolak';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Konfirmasi $label', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Yakin ingin $label permintaan booking ini?\n\n'
          'Kos: $kosName\n'
          'Periode: $startText - $endText',
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[700],
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF7D86BF),
              foregroundColor: Colors.white,
              elevation: 0,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmAndUpdateIncomingStatus({
    required int bookingId,
    required String status,
    required String kosName,
    required String societyName,
    required String startText,
    required String endText,
  }) async {
    if (_updatingBookingIds.contains(bookingId)) return;
    final confirmed = await _confirmIncomingUpdate(
      status: status,
      kosName: kosName,
      societyName: societyName,
      startText: startText,
      endText: endText,
    );
    if (!confirmed) return;
    await _updateIncomingStatus(bookingId: bookingId, status: status);
  }

  Future<void> _updateIncomingStatus({
    required int bookingId,
    required String status,
  }) async {
    final token = await AuthService.getToken();
    if (!mounted) return;
    if (token == null || token.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Token tidak ditemukan')));
      return;
    }

    setState(() {
      _updatingBookingIds.add(bookingId);
    });
    try {
      await OwnerBookingService.updateStatus(
        token: token,
        bookingId: bookingId,
        status: status,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Berhasil: $status')));

      // Setelah update, refresh kedua list agar berpindah section jika perlu.
      _refreshIncomingBookings();
      _refreshActiveBookings();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal update: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _updatingBookingIds.remove(bookingId);
      });
    }
  }

  Future<void> _logout(BuildContext context, {bool confirm = true}) async {
    if (confirm) {
      const accent = Color(0xFF7D86BF);
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => BookingNotificationDialog(
          accentColor: accent,
          title: 'Konfirmasi logout',
          message: 'Yakin ingin logout?',
          leftLabel: 'Batal',
          onLeftPressed: () => Navigator.pop(ctx, false),
          rightLabel: 'Logout',
          onRightPressed: () => Navigator.pop(ctx, true),
        ),
      );

      if (confirmed != true) return;
    }

    await AuthService.logout();
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _openUpdateProfile(BuildContext context) async {
    final result = await Navigator.pushNamed(context, '/owner-update-profile');

    if (!mounted) return;

    setState(() {
      _userNameFuture = AuthService.getUserName();
    });

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile berhasil diperbarui')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep palette consistent with SplashPage gradient.
    const splashTop = Color(0xFF7D86BF);
    const splashMid = Color(0xFF9CA6DB);
    const splashBottom = Color(0xFFE9ECFF);
    const cardColor = Colors.white;
    const accent = splashTop;

    Widget sectionHeader({
      required String title,
      VoidCallback? onRefresh,
      VoidCallback? onViewAll,
    }) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
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
                    color: splashBottom.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.35)),
                  ),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.black.withOpacity(0.88),
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            if (onViewAll != null)
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                child: const Text('Lihat semua'),
              ),
          ],
        ),
      );
    }

    Widget surfaceCard({required Widget child, double radius = 22}) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      );
    }

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
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: splashBottom.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: splashTop,
        foregroundColor: Colors.white,
        surfaceTintColor: splashTop,
        elevation: 0,
        centerTitle: true,
        title: const Text('Home Owner'),
        actions: [
          IconButton(
            tooltip: 'Update Profile',
            onPressed: () => _openUpdateProfile(context),
            icon: const Icon(Icons.person_rounded),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 6),
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
          child: ListView(
            padding: const EdgeInsets.only(top: 10, bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<String?>(
                            future: _userNameFuture,
                            builder: (context, snapshot) {
                              final name = (snapshot.data ?? '').trim();
                              final displayName = name.isEmpty ? 'Owner' : name;
                              return Text(
                                'Selamat datang, $displayName',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.1,
                                    ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Quick Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: quickAction(
                            icon: Icons.home_work_rounded,
                            title: 'Kos Saya',
                            subtitle: 'Kelola daftar kos',
                            onTap: () async {
                              final token = await AuthService.getToken();
                              if (!context.mounted) return;
                              if (token == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MasterKosPage(token: token),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: quickAction(
                            icon: Icons.history_rounded,
                            title: 'History',
                            subtitle: 'Riwayat booking',
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                '/owner-booking-history',
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: quickAction(
                            icon: Icons.notifications_active_rounded,
                            title: 'Booking',
                            subtitle: 'Permintaan & aktif',
                            onTap: () {
                              Navigator.pushNamed(context, '/owner-bookings');
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: quickAction(
                            icon: Icons.reviews_rounded,
                            title: 'Review',
                            subtitle: 'Lihat & balas ulasan',
                            onTap: () async {
                              final token = await AuthService.getToken();
                              if (!context.mounted) return;
                              if (token == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OwnerAllReviewsPage(token: token),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Incoming bookings
              sectionHeader(
                title: 'Permintaan booking',
                onRefresh: _refreshIncomingBookings,
                onViewAll: () =>
                    Navigator.pushNamed(context, '/owner-bookings'),
              ),
              surfaceCard(
                radius: 14,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: FutureBuilder<List<_OwnerIncomingBooking>>(
                    future: _incomingBookingsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(14),
                          child: LinearProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        if (_isUnauthorizedError(snapshot.error)) {
                          _forceLogoutAfterFrame(context);
                        }
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Gagal memuat permintaan booking.',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _isUnauthorizedError(snapshot.error)
                                        ? () => _logout(context, confirm: false)
                                        : _refreshIncomingBookings,
                                    style: TextButton.styleFrom(
                                      foregroundColor: accent,
                                    ),
                                    child: Text(
                                      _isUnauthorizedError(snapshot.error)
                                          ? 'Login ulang'
                                          : 'Coba lagi',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isUnauthorizedError(snapshot.error)
                                    ? 'Token login tidak valid / sudah kedaluwarsa.'
                                    : snapshot.error.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final items = snapshot.data ?? const [];
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                          child: Text(
                            'Tidak ada permintaan booking saat ini.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.black.withOpacity(0.62),
                                ),
                          ),
                        );
                      }

                      final preview = items.take(3).toList();
                      return FutureBuilder<Map<int, String>>(
                        future: _kosNameByIdFuture,
                        builder: (context, kosSnap) {
                          final kosNameById =
                              kosSnap.data ?? const <int, String>{};
                          return Column(
                            children: [
                              for (final b in preview)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    6,
                                    12,
                                    6,
                                  ),
                                  child: Material(
                                    color: const Color(0xFFF4F6FF),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => Navigator.pushNamed(
                                        context,
                                        '/owner-bookings',
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            (b.kosId == null)
                                                ? const Icon(
                                                    Icons
                                                        .notifications_active_outlined,
                                                  )
                                                : _thumbWidget(
                                                    context,
                                                    kosId: b.kosId!,
                                                  ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (b.kosId != null &&
                                                            (b.kosName
                                                                    .trim()
                                                                    .isEmpty ||
                                                                b.kosName
                                                                        .trim()
                                                                        .toLowerCase() ==
                                                                    'kos'))
                                                        ? (kosNameById[b
                                                                  .kosId!] ??
                                                              b.kosName)
                                                        : b.kosName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    (() {
                                                      final tenant =
                                                          b.societyName;
                                                      final hasTenant =
                                                          _hasTenantName(
                                                            tenant,
                                                          );
                                                      final prefix = hasTenant
                                                          ? 'Penyewa: $tenant\n'
                                                          : '';
                                                      return '$prefix${b.startText} - ${b.endText}';
                                                    })(),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Colors.black
                                                              .withOpacity(0.6),
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (b.bookingId != null)
                                              Builder(
                                                builder: (context) {
                                                  final bookingId =
                                                      b.bookingId!;
                                                  final isUpdating =
                                                      _updatingBookingIds
                                                          .contains(bookingId);
                                                  return Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        tooltip: 'Tolak',
                                                        onPressed: isUpdating
                                                            ? null
                                                            : () => _confirmAndUpdateIncomingStatus(
                                                                bookingId:
                                                                    bookingId,
                                                                status:
                                                                    'reject',
                                                                kosName:
                                                                    b.kosName,
                                                                societyName: b
                                                                    .societyName,
                                                                startText:
                                                                    b.startText,
                                                                endText:
                                                                    b.endText,
                                                              ),
                                                        icon: const Icon(
                                                          Icons.close,
                                                        ),
                                                        color: Colors.redAccent,
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Terima',
                                                        onPressed: isUpdating
                                                            ? null
                                                            : () => _confirmAndUpdateIncomingStatus(
                                                                bookingId:
                                                                    bookingId,
                                                                status:
                                                                    'accept',
                                                                kosName:
                                                                    b.kosName,
                                                                societyName: b
                                                                    .societyName,
                                                                startText:
                                                                    b.startText,
                                                                endText:
                                                                    b.endText,
                                                              ),
                                                        icon: isUpdating
                                                            ? const SizedBox(
                                                                width: 18,
                                                                height: 18,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                              )
                                                            : const Icon(
                                                                Icons.check,
                                                              ),
                                                        color: Colors.green,
                                                      ),
                                                    ],
                                                  );
                                                },
                                              )
                                            else
                                              const Icon(
                                                Icons.chevron_right,
                                                color: accent,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (items.length > preview.length)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    4,
                                    14,
                                    10,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '+${items.length - preview.length} permintaan lainnya',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Active bookings
              sectionHeader(
                title: 'Booking aktif',
                onRefresh: _refreshActiveBookings,
                onViewAll: () =>
                    Navigator.pushNamed(context, '/owner-bookings'),
              ),
              surfaceCard(
                radius: 14,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: FutureBuilder<List<_OwnerActiveBooking>>(
                    future: _activeBookingsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(14),
                          child: LinearProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        if (_isUnauthorizedError(snapshot.error)) {
                          _forceLogoutAfterFrame(context);
                        }
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Gagal memuat booking aktif.',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed:
                                        _isUnauthorizedError(snapshot.error)
                                        ? () => _logout(context, confirm: false)
                                        : _refreshActiveBookings,
                                    style: TextButton.styleFrom(
                                      foregroundColor: accent,
                                    ),
                                    child: Text(
                                      _isUnauthorizedError(snapshot.error)
                                          ? 'Login ulang'
                                          : 'Coba lagi',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isUnauthorizedError(snapshot.error)
                                    ? 'Token login tidak valid / sudah kedaluwarsa.'
                                    : snapshot.error.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final items = snapshot.data ?? const [];
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                          child: Text(
                            'Belum ada booking aktif saat ini.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.black.withOpacity(0.62),
                                ),
                          ),
                        );
                      }

                      final preview = items.take(3).toList();
                      return FutureBuilder<Map<int, String>>(
                        future: _kosNameByIdFuture,
                        builder: (context, kosSnap) {
                          final kosNameById =
                              kosSnap.data ?? const <int, String>{};
                          return Column(
                            children: [
                              for (final b in preview)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    6,
                                    12,
                                    6,
                                  ),
                                  child: Material(
                                    color: const Color(0xFFF4F6FF),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () async {
                                        final raw = b.source;
                                        if (raw == null) {
                                          Navigator.pushNamed(
                                            context,
                                            '/owner-bookings',
                                          );
                                          return;
                                        }

                                        final token =
                                            await AuthService.getToken();
                                        if (!mounted) return;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                BookingReceiptPreviewPage(
                                                  booking: raw,
                                                  token: token,
                                                  isOwner: true,
                                                ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            (b.kosId == null)
                                                ? const Icon(Icons.key)
                                                : _thumbWidget(
                                                    context,
                                                    kosId: b.kosId!,
                                                  ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (b.kosId != null &&
                                                            (b.kosName
                                                                    .trim()
                                                                    .isEmpty ||
                                                                b.kosName
                                                                        .trim()
                                                                        .toLowerCase() ==
                                                                    'kos'))
                                                        ? (kosNameById[b
                                                                  .kosId!] ??
                                                              b.kosName)
                                                        : b.kosName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    (() {
                                                      final tenant =
                                                          b.societyName;
                                                      final hasTenant =
                                                          _hasTenantName(
                                                            tenant,
                                                          );
                                                      final prefix = hasTenant
                                                          ? 'Penyewa: $tenant\n'
                                                          : '';
                                                      return '$prefix${b.startText} - ${b.endText}';
                                                    })(),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Colors.black
                                                              .withOpacity(0.6),
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.chevron_right,
                                              color: accent,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (items.length > preview.length)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    4,
                                    14,
                                    10,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '+${items.length - preview.length} booking aktif lainnya',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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

class _OwnerActiveBooking {
  final Map<String, dynamic>? source;
  final int? bookingId;
  final int? kosId;
  final String kosName;
  final String societyName;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  const _OwnerActiveBooking({
    required this.source,
    required this.bookingId,
    required this.kosId,
    required this.kosName,
    required this.societyName,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.updatedAt,
    required this.createdAt,
  });

  String get startText => startDate.toIso8601String().split('T').first;
  String get endText => endDate.toIso8601String().split('T').first;
}

class _OwnerIncomingBooking {
  final int? bookingId;
  final int? kosId;
  final String kosName;
  final String societyName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;

  const _OwnerIncomingBooking({
    required this.bookingId,
    required this.kosId,
    required this.kosName,
    required this.societyName,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  String get startText =>
      startDate == null ? '-' : startDate!.toIso8601String().split('T').first;
  String get endText =>
      endDate == null ? '-' : endDate!.toIso8601String().split('T').first;
}
