import 'package:flutter/material.dart';
import 'package:koshunter6/services/auth_service.dart';
import 'package:koshunter6/services/society/booking_service.dart';
import 'package:koshunter6/services/society/society_review_service.dart';
import 'package:koshunter6/utils/deleted_review_store.dart';
import 'package:koshunter6/views/society/bookings/society_kos_detail_page.dart';
import 'package:koshunter6/widgets/app_card.dart';
import 'package:koshunter6/widgets/app_gradient_scaffold.dart';

class SocietyAllReviewsPage extends StatefulWidget {
  const SocietyAllReviewsPage({super.key});

  @override
  State<SocietyAllReviewsPage> createState() => _SocietyAllReviewsPageState();
}

class _SocietyAllReviewsPageState extends State<SocietyAllReviewsPage> {
  static const Color _accent = Color(0xFF7D86BF);

  bool _loading = true;
  String? _error;
  double _progress = 0;
  String _progressText = '';
  String? _token;
  List<_AllReviewItem> _items = const [];

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

  String _replyFromReviewItem(dynamic item) {
    if (item is Map) {
      dynamic v =
          item['reply'] ??
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

  String _formatDate(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    return loc.formatShortDate(dt);
  }

  Widget _replyBox(BuildContext context, String reply) {
    final cs = Theme.of(context).colorScheme;
    final softLavender = Color.lerp(Colors.white, _accent, 0.10)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: softLavender,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balasan owner',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: _accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reply,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withAlpha(235),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
      _progressText = '';
      _items = const [];
    });

    try {
      final locallyDeleted = await DeletedReviewStore.getDeletedReviewIds();
      final token = await AuthService.getToken();
      if (!mounted) return;
      if (token == null || token.trim().isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Kamu belum login.';
        });
        return;
      }

      _token = token;
      final kosList = await BookingService.showKos(token: token, search: '');
      if (!mounted) return;
      if (kosList.isEmpty) {
        setState(() {
          _loading = false;
          _items = const [];
        });
        return;
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
          reviews = await SocietyReviewService.getReviews(
            token: token,
            kosId: kosId,
          );
        } catch (_) {
          // Skip one kos if its reviews endpoint fails; keep others.
          continue;
        }

        for (final r in reviews) {
          if (_isDeletedReviewItem(r)) continue;
          final rid = _reviewIdFromReviewItem(r);
          if (rid != null && locallyDeleted.contains(rid)) continue;
          final text = _reviewTextFromReviewItem(r).trim();
          if (text.isEmpty) continue;
          all.add(
            _AllReviewItem(
              kosId: kosId,
              kosName: kosName.isEmpty ? 'Kos #$kosId' : kosName,
              reviewId: rid,
              reviewText: text,
              reviewerName: _reviewerNameFromReviewItem(r),
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
    final token = _token;

    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      foregroundColor: _accent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    );

    const backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE9ECFF), Color(0xFF9CA6DB), Color(0xFF7D86BF)],
      stops: [0.0, 0.6, 1.0],
    );

    Widget body;

    if (_error != null) {
      body = Center(
        child: AppCard(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Coba lagi'),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_loading) {
      body = Center(
        child: AppCard(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              if (_progressText.isNotEmpty)
                Text(_progressText, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              if (_progress > 0) LinearProgressIndicator(value: _progress),
            ],
          ),
        ),
      );
    } else if (_items.isEmpty) {
      body = Center(
        child: AppCard(
          color: Colors.white,
          child: Text(
            'Belum ada review.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } else {
      final cs = theme.colorScheme;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final it = _items[index];
            final dateText = (it.createdAt == null)
                ? ''
                : _formatDate(context, it.createdAt!);
            final hasReply = it.replyText.trim().isNotEmpty;

            return AppCard(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              onTap: token == null
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SocietyKosDetailPage(
                            token: token,
                            kosId: it.kosId,
                            kosName: it.kosName,
                          ),
                        ),
                      );
                      if (!mounted) return;
                      await _load();
                    },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 18,
                        color: cs.onSurface.withAlpha(150),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dateText.isEmpty ? '-' : dateText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withAlpha(160),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (it.reviewId != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _accent.withAlpha(60)),
                          ),
                          child: Text(
                            'ID ${it.reviewId.toString()}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: _accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    it.kosName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                  if (it.reviewerName.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Oleh: ${it.reviewerName.trim()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withAlpha(150),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    it.reviewText,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurface.withAlpha(235),
                      height: 1.35,
                    ),
                  ),
                  if (hasReply) ...[
                    const SizedBox(height: 14),
                    _replyBox(context, it.replyText.trim()),
                  ],
                ],
              ),
            );
          },
        ),
      );
    }

    return Theme(
      data: theme.copyWith(appBarTheme: appBarTheme),
      child: AppGradientScaffold(
        title: 'Semua Review',
        backgroundGradient: backgroundGradient,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: body,
      ),
    );
  }
}

class _AllReviewItem {
  final int kosId;
  final String kosName;
  final int? reviewId;
  final String reviewText;
  final String reviewerName;
  final String replyText;
  final DateTime? createdAt;

  const _AllReviewItem({
    required this.kosId,
    required this.kosName,
    required this.reviewId,
    required this.reviewText,
    required this.reviewerName,
    required this.replyText,
    required this.createdAt,
  });
}
