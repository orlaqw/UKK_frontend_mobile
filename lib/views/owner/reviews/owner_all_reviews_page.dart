import 'package:flutter/material.dart';
import 'package:koshunter6/services/owner/owner_kos_service.dart';
import 'package:koshunter6/services/owner/owner_review_service.dart';
import 'package:koshunter6/views/owner/master_kos/owner_kos_detail_page.dart';

class OwnerAllReviewsPage extends StatefulWidget {
  final String token;

  const OwnerAllReviewsPage({super.key, required this.token});

  @override
  State<OwnerAllReviewsPage> createState() => _OwnerAllReviewsPageState();
}

class _OwnerAllReviewsPageState extends State<OwnerAllReviewsPage> {
  static const Color _accent = Color(0xFF7D86BF);

  bool _loading = true;
  String? _error;
  double _progress = 0;
  String _progressText = '';
  List<_AllReviewItem> _items = const [];
  final Map<int, Map> _kosById = {};

  int? _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  int? _kosIdFromKosItem(dynamic item) {
    if (item is Map) {
      return _toInt(
        item['id'] ??
            item['kos_id'] ??
            item['id_kos'] ??
            item['kosId'] ??
            item['idKos'],
      );
    }
    return null;
  }

  String _kosNameFromKosItem(dynamic item) {
    if (item is Map) {
      return _asString(
        item['name'] ??
            item['kos_name'] ??
            item['nama_kos'] ??
            item['title'] ??
            item['nama'],
      );
    }
    return '';
  }

  int? _reviewIdFromReviewItem(dynamic item) {
    if (item is Map) {
      return _toInt(item['id'] ?? item['review_id'] ?? item['id_review']);
    }
    return null;
  }

  String _reviewTextFromReviewItem(dynamic item) {
    if (item is Map) {
      return _asString(
        item['review'] ??
            item['ulasan'] ??
            item['comment'] ??
            item['message'] ??
            item['content'],
      );
    }
    return _asString(item);
  }

  String _reviewerNameFromReviewItem(dynamic item) {
    if (item is Map) {
      return _asString(
        item['society_name'] ??
            item['user_name'] ??
            item['username'] ??
            item['name'] ??
            item['user'],
      ).trim();
    }
    return '';
  }

  String _replyFromReviewItem(dynamic item) {
    if (item is Map) {
      return _asString(
        item['reply'] ??
            item['owner_reply'] ??
            item['admin_reply'] ??
            item['response'] ??
            item['balasan'] ??
            item['tanggapan'],
      ).trim();
    }
    return '';
  }

  DateTime? _createdAtFromReviewItem(dynamic item) {
    if (item is! Map) return null;
    final raw =
        item['created_at'] ??
        item['createdAt'] ??
        item['date'] ??
        item['tanggal'];
    final s = _asString(raw).trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _formatDate(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    return loc.formatShortDate(dt);
  }

  Future<Map> _resolveKosMap(int kosId) async {
    final existing = _kosById[kosId];
    if (existing != null) return existing;
    final detail = await OwnerKosService.detailKos(
      token: widget.token,
      kosId: kosId,
    );
    final map = Map<String, dynamic>.from(detail);
    _kosById[kosId] = map;
    return map;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
      _progressText = '';
      _items = const [];
      _kosById.clear();
    });

    try {
      final kosList = await OwnerKosService.getKos(
        token: widget.token,
        search: '',
      );
      if (!mounted) return;
      if (kosList.isEmpty) {
        setState(() {
          _loading = false;
          _items = const [];
        });
        return;
      }

      for (final k in kosList) {
        final id = _kosIdFromKosItem(k);
        if (id == null || id == 0) continue;
        if (k is Map) {
          _kosById[id] = Map<String, dynamic>.from(k);
        }
      }

      final all = <_AllReviewItem>[];
      final total = kosList.length;

      for (var i = 0; i < kosList.length; i++) {
        final kos = kosList[i];
        final kosId = _kosIdFromKosItem(kos);
        final kosName = _kosNameFromKosItem(kos);
        if (kosId == null || kosId == 0) continue;

        setState(() {
          _progress = total == 0 ? 0 : i / total;
          _progressText =
              'Memuat review: ${kosName.isEmpty ? 'Kos #$kosId' : kosName}';
        });

        List<dynamic> reviews;
        try {
          reviews = await OwnerReviewService.getReviews(
            token: widget.token,
            kosId: kosId,
          );
        } catch (_) {
          continue;
        }

        for (final r in reviews) {
          final text = _reviewTextFromReviewItem(r).trim();
          if (text.isEmpty) continue;
          all.add(
            _AllReviewItem(
              kosId: kosId,
              kosName: kosName.isEmpty ? 'Kos #$kosId' : kosName,
              reviewId: _reviewIdFromReviewItem(r),
              replyMarkerId: (r is Map) ? _toInt(r['reply_marker_id']) : null,
              reviewerName: _reviewerNameFromReviewItem(r),
              reviewText: text,
              replyText: _replyFromReviewItem(r),
              createdAt: _createdAtFromReviewItem(r),
            ),
          );
        }
      }

      all.sort((a, b) {
        final ad = a.createdAt;
        final bd = b.createdAt;
        if (ad != null && bd != null) return bd.compareTo(ad);
        if (ad != null) return -1;
        if (bd != null) return 1;
        final ai = a.reviewId ?? 0;
        final bi = b.reviewId ?? 0;
        return bi.compareTo(ai);
      });

      if (!mounted) return;
      setState(() {
        _loading = false;
        _progress = 1;
        _progressText = '';
        _items = all;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final softBg = Color.lerp(Colors.white, _accent, 0.06)!;
    final cardBorder = Color.lerp(_accent, Colors.white, 0.35)!;
    final replyBg = Color.lerp(Colors.white, _accent, 0.10)!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Semua Review'),
        centerTitle: true,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        surfaceTintColor: _accent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF7D86BF), Colors.white],
          ),
        ),
        child: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Coba lagi'),
                    ),
                  ],
                    ),
                  ),
                )
              : _loading
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(_accent),
                          ),
                          const SizedBox(height: 12),
                          if (_progressText.isNotEmpty)
                            Text(
                              _progressText,
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          const SizedBox(height: 8),
                          if (_progress > 0)
                            LinearProgressIndicator(
                              value: _progress,
                              color: _accent,
                              backgroundColor:
                                  Color.lerp(Colors.white, _accent, 0.15),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Belum ada review.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: _accent,
                      backgroundColor: Colors.white,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final it = _items[index];
                          final reviewerName = it.reviewerName.trim();
                          final replyText = it.replyText.trim();

                          return Card(
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: cardBorder),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                try {
                                  final kosMap = await _resolveKosMap(it.kosId);
                                  if (!context.mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OwnerKosDetailPage(
                                        token: widget.token,
                                        kos: kosMap,
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Gagal buka kos: $e')),
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            it.kosName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: _accent,
                                        ),
                                      ],
                                    ),
                                    if (reviewerName.isNotEmpty ||
                                        it.reviewId != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                            child: Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            if (reviewerName.isNotEmpty)
                                              _MetaChip(
                                                icon: Icons.person_rounded,
                                                label: reviewerName,
                                                borderColor: cardBorder,
                                              ),
                                            if (it.reviewId != null)
                                              _MetaChip(
                                                icon: Icons.tag_rounded,
                                                label: 'ID ${it.reviewId}',
                                                borderColor: cardBorder,
                                              ),
                                            if (it.createdAt != null)
                                              _MetaChip(
                                                icon: Icons.schedule,
                                                label:
                                                    _formatDate(context, it.createdAt!),
                                                borderColor: cardBorder,
                                              ),
                                          ],
                                        ),
                                      ),
                                    const SizedBox(height: 10),
                                    Text(
                                      it.reviewText,
                                      style: const TextStyle(height: 1.35),
                                    ),
                                    if (replyText.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: replyBg,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: cardBorder),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Balasan Owner Kos',
                                              style: TextStyle(
                                                color: _accent,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              replyText,
                                              style: const TextStyle(height: 1.35),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color borderColor;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _OwnerAllReviewsPageState._accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AllReviewItem {
  final int kosId;
  final String kosName;
  final int? reviewId;
  final int? replyMarkerId;
  final String reviewerName;
  final String reviewText;
  final String replyText;
  final DateTime? createdAt;

  const _AllReviewItem({
    required this.kosId,
    required this.kosName,
    required this.reviewId,
    this.replyMarkerId,
    required this.reviewerName,
    required this.reviewText,
    required this.replyText,
    required this.createdAt,
  });
}
