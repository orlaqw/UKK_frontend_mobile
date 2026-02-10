import 'package:flutter/material.dart';

import '../../../services/society/society_review_service.dart';
import '../../../utils/deleted_review_store.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_gradient_scaffold.dart';

class ReviewPage extends StatelessWidget {
  final String token;
  final int kosId;
  final String? kosName;
  final bool readOnly;

  const ReviewPage({
    super.key,
    required this.token,
    required this.kosId,
    this.kosName,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return ReviewsPage(
      token: token,
      kosId: kosId,
      kosName: (kosName ?? 'Kos').trim().isEmpty ? 'Kos' : kosName!.trim(),
      readOnly: readOnly,
    );
  }
}

class ReviewsPage extends StatefulWidget {
  final String token;
  final int kosId;
  final String kosName;
  final bool readOnly;

  const ReviewsPage({
    super.key,
    required this.token,
    required this.kosId,
    required this.kosName,
    this.readOnly = false,
  });

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  late Future<List<dynamic>> _future;
  bool _submitting = false;
  Set<int> _locallyDeletedReviewIds = const {};

  static const Color _accent = Color(0xFF7D86BF);

  DateTime? _createdAtFromItem(dynamic item) {
    if (item is! Map) return null;
    final raw =
        item['created_at'] ??
        item['createdAt'] ??
        item['date'] ??
        item['tanggal'];
    final s = (raw?.toString() ?? '').trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
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

  void _load() {
    _future = SocietyReviewService.getReviews(
      token: widget.token,
      kosId: widget.kosId,
    );
  }

  Future<void> _loadLocallyDeletedIds() async {
    final ids = await DeletedReviewStore.getDeletedReviewIds();
    if (!mounted) return;
    setState(() => _locallyDeletedReviewIds = ids);
  }

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  int? _reviewIdFromItem(dynamic item) {
    if (item is Map) {
      return _toInt(item['id'] ?? item['review_id'] ?? item['id_review']);
    }
    return null;
  }

  String _reviewTextFromItem(dynamic item) {
    if (item is Map) {
      final v =
          item['review'] ??
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

  Future<void> _addReview() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final softLavender = Color.lerp(Colors.white, _accent, 0.06)!;
        final fieldFill = Color.lerp(Colors.white, _accent, 0.10)!;

        return AlertDialog(
          backgroundColor: softLavender,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: _accent.withAlpha(56)),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          title: Row(
            children: [
              const Icon(Icons.rate_review_outlined, color: _accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tambah Review',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    color: _accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.kosName,
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withAlpha(230),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Review kamu',
                  hintText: 'Tulis review kamu...',
                  filled: true,
                  fillColor: fieldFill,
                  labelStyle: const TextStyle(color: _accent),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _accent.withAlpha(64)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _accent.withAlpha(64)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _accent, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: cs.onSurface),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: _submitting ? null : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (ok != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review tidak boleh kosong')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await SocietyReviewService.addReview(
        token: widget.token,
        kosId: widget.kosId,
        review: text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Review terkirim')));
      setState(_load);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _deleteReview(dynamic item) async {
    final reviewId = _reviewIdFromItem(item);
    if (reviewId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID review tidak ditemukan')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
        builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: _accent),
            const SizedBox(width: 10),
            const Expanded(child: Text('Hapus Review')),
          ],
        ),
        content: const Text('Yakin ingin menghapus review ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: _accent),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirm != true) return;

    setState(() => _submitting = true);
    try {
      await SocietyReviewService.deleteReview(
        token: widget.token,
        reviewId: reviewId,
      );

      // Always hide locally so the UI stays consistent even if backend
      // still returns the deleted review (stale cache / soft-delete mismatch).
      await DeletedReviewStore.markDeleted(reviewId);
      final nextDeleted = {..._locallyDeletedReviewIds, reviewId};
      if (mounted) setState(() => _locallyDeletedReviewIds = nextDeleted);

      // Verify by re-fetching; if it still exists, inform user.
      try {
        final latest = await SocietyReviewService.getReviews(
          token: widget.token,
          kosId: widget.kosId,
        );
        final stillThere = latest.any((e) => _reviewIdFromItem(e) == reviewId);
        if (stillThere && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Review sudah disembunyikan di aplikasi, tapi server masih mengembalikan review tersebut.',
              ),
            ),
          );
        }
      } catch (_) {
        // Ignore verification errors.
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Review dihapus')));
      setState(_load);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadLocallyDeletedIds();
  }

  @override
  Widget build(BuildContext context) {
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

    return Theme(
      data: theme.copyWith(appBarTheme: appBarTheme),
      child: AppGradientScaffold(
        title: 'Review: ${widget.kosName}',
        backgroundGradient: backgroundGradient,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_load),
          ),
        ],
        floatingActionButton: widget.readOnly
            ? null
            : FloatingActionButton(
                onPressed: _submitting ? null : _addReview,
                backgroundColor: Colors.white,
                foregroundColor: _accent,
                child: const Icon(Icons.rate_review_outlined),
              ),
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: AppCard(
                  color: Colors.white,
                  child: Text(
                    snapshot.error.toString(),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              );
            }

            final items = (snapshot.data ?? const <dynamic>[])
                .where((e) => !_isDeletedReviewItem(e))
                .where((e) {
                  final id = _reviewIdFromItem(e);
                  if (id == null) return true;
                  return !_locallyDeletedReviewIds.contains(id);
                })
                .toList(growable: false);
            if (items.isEmpty) {
              return Center(
                child: AppCard(
                  color: Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Belum ada review.',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!widget.readOnly) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _submitting ? null : _addReview,
                            icon: const Icon(Icons.rate_review_outlined),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                            ),
                            label: const Text('Tulis Review'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }

            final cs = Theme.of(context).colorScheme;

            return RefreshIndicator(
              onRefresh: () async {
                setState(_load);
                await _future;
              },
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final it = items[i];
                  final createdAt = _createdAtFromItem(it);
                  final text = _reviewTextFromItem(it);
                  final reply = _replyTextFromItem(it);
                  final reviewId = _reviewIdFromItem(it);
                  final canDelete = !widget.readOnly && reviewId != null;

                  final dateText = (createdAt == null)
                      ? ''
                      : _formatDate(context, createdAt);

                  return AppCard(
                    color: Colors.white,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 12),
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
                            if (reviewId != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _accent.withAlpha(60),
                                  ),
                                ),
                                child: Text(
                                  'ID ${reviewId.toString()}',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: _accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          text.isEmpty ? '(tanpa teks)' : text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: cs.onSurface.withAlpha(235),
                            height: 1.35,
                          ),
                        ),
                        if (reply.trim().isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _replyBox(context, reply.trim()),
                        ],
                        if (canDelete) ...[
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                ),
                                color: _accent,
                                tooltip: 'Hapus',
                                onPressed: _submitting
                                    ? null
                                    : () => _deleteReview(it),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
