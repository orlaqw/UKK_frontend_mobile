import 'package:flutter/material.dart';

import '../../../services/owner/owner_review_service.dart';

class OwnerReviewsPage extends StatefulWidget {
  final String token;
  final Map kos;

  const OwnerReviewsPage({super.key, required this.token, required this.kos});

  @override
  State<OwnerReviewsPage> createState() => _OwnerReviewsPageState();
}

class _OwnerReviewsPageState extends State<OwnerReviewsPage> {
  late Future<List<dynamic>> futureReviews;
  bool submitting = false;

  static const Color _accentPurple = Color(0xFF7D86BF);

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

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int get _kosId =>
      _toInt(widget.kos['id'] ?? widget.kos['kos_id'] ?? widget.kos['id_kos']);

  void load() {
    futureReviews = OwnerReviewService.getReviews(
      token: widget.token,
      kosId: _kosId,
    );
  }

  String _reviewTextFromItem(dynamic item) {
    if (item is Map) {
      final v =
          item['review'] ??
          item['comment'] ??
          item['message'] ??
          item['content'] ??
          item['ulasan'];
      final s = (v?.toString() ?? '').trim();
      final m = RegExp(r'\[\[reply_to:(\d+)\]\]\s*(.*)$').firstMatch(s);
      if (m != null) return (m.group(2) ?? '').trim();
      return s;
    }
    return item?.toString() ?? '';
  }

  String _replyTextFromItem(dynamic item) {
    if (item is Map) {
      dynamic v =
          item['reply'] ??
          item['owner_reply'] ??
          item['admin_reply'] ??
          item['response'] ??
          item['balasan'] ??
          item['balasan_owner'] ??
          item['tanggapan'] ??
          item['reply_text'] ??
          item['reply_message'] ??
          item['replyReview'];

      // beberapa response mengembalikan nested object
      if (v is Map) {
        v = v['reply'] ?? v['text'] ?? v['message'] ?? v['content'];
      }

      return v?.toString() ?? '';
    }
    return '';
  }

  int? _reviewIdFromItem(dynamic item) {
    if (item is Map) {
      final v = item['id'] ?? item['review_id'] ?? item['id_review'];
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    }
    return null;
  }

  String _societyNameFromItem(dynamic item) {
    if (item is Map) {
      final user = item['user'] as Map?;
      final society = item['society'] as Map?;
      final v =
          (user?['name'] ??
          society?['name'] ??
          item['user_name'] ??
          item['society_name']);
      return (v?.toString() ?? '').trim();
    }
    return '';
  }

  String _formatDate(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    return loc.formatShortDate(dt);
  }

  Widget _replyBox(BuildContext context, String reply, dynamic item) {
    final cs = Theme.of(context).colorScheme;
    final softLavender = Color.lerp(Colors.white, _accentPurple, 0.10)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: softLavender,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentPurple.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balasan owner',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _accentPurple,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  reply,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.92),
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: _accentPurple),
            tooltip: 'Hapus balasan',
            onPressed: submitting ? null : () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) {
                  return AlertDialog(
                    title: Row(
                      children: [
                        Icon(Icons.delete_outline, color: _accentPurple),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Hapus Balasan Review')),
                      ],
                    ),
                    content: const Text('Yakin ingin menghapus balasan review ini?'),
                    actions: [
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: _accentPurple),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentPurple,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Hapus'),
                      ),
                    ],
                  );
                },
              );
              if (confirm == true) {
                setState(() => submitting = true);
                try {
                  int? markerId;
                  if (item is Map) {
                    final cand = item['reply_marker_id'] ?? item['reply_marker'] ?? item['marker_id'] ?? item['marker'];
                    if (cand is num) markerId = cand.toInt();
                    else markerId = int.tryParse(cand?.toString() ?? '');
                  }
                  if (markerId != null && markerId > 0) {
                    await OwnerReviewService.deleteReview(
                      token: widget.token,
                      reviewId: markerId,
                    );
                  } else {
                    await OwnerReviewService.replyToReview(
                      token: widget.token,
                      kosId: _kosId,
                      reviewId: _reviewIdFromItem(item)!,
                      reply: '',
                    );
                  }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Balasan owner berhasil dihapus')),
                  );
                  setState(load);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menghapus balasan: $e')),
                  );
                } finally {
                  if (mounted) setState(() => submitting = false);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _replyTo(dynamic item) async {
    final reviewId = _reviewIdFromItem(item);
    if (reviewId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID review tidak ditemukan')),
      );
      return;
    }

    final reviewText = _reviewTextFromItem(item).trim();
    final societyName = _societyNameFromItem(item).trim();

    final existingReply = _replyTextFromItem(item).trim();
    final isEditing = existingReply.isNotEmpty;
    final dialogTitle = isEditing ? 'Edit Balasan' : 'Balas Review';
    final submitLabel = isEditing ? 'Simpan' : 'Kirim';

    final controller = TextEditingController(text: existingReply);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final softLavender = Color.lerp(Colors.white, _accentPurple, 0.06)!;
        final fieldFill = Color.lerp(Colors.white, _accentPurple, 0.10)!;

        return AlertDialog(
          backgroundColor: softLavender,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: _accentPurple.withOpacity(0.22)),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          title: Row(
            children: [
              Icon(
                isEditing ? Icons.edit_outlined : Icons.reply_outlined,
                color: _accentPurple,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dialogTitle,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    color: _accentPurple,
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
              if (societyName.isNotEmpty)
                Text(
                  societyName,
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withOpacity(0.9),
                  ),
                ),
              Text(
                'ID review: $reviewId',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.65),
                ),
              ),
              if (reviewText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _accentPurple.withOpacity(0.18)),
                  ),
                  child: Text(
                    reviewText,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.9),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Balasan owner',
                  filled: true,
                  fillColor: fieldFill,
                  labelStyle: const TextStyle(color: _accentPurple),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _accentPurple.withOpacity(0.25),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _accentPurple.withOpacity(0.25),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: _accentPurple,
                      width: 2,
                    ),
                  ),
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _accentPurple),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: submitting ? null : () => Navigator.pop(ctx, true),
              child: Text(submitLabel),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final reply = controller.text.trim();
    if (reply.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Balasan tidak boleh kosong')),
      );
      return;
    }

    setState(() => submitting = true);
    try {
      await OwnerReviewService.replyToReview(
        token: widget.token,
        kosId: _kosId,
        reviewId: reviewId,
        reply: reply,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Balasan terkirim')));
      setState(load);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _delete(dynamic item) async {
    final reviewId = _reviewIdFromItem(item);
    if (reviewId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID review tidak ditemukan')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final softLavender = Color.lerp(Colors.white, _accentPurple, 0.06)!;
        return AlertDialog(
          backgroundColor: softLavender,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: _accentPurple.withOpacity(0.22)),
          ),
          title: Row(
            children: [
              Icon(Icons.delete_outline, color: cs.error),
              const SizedBox(width: 10),
              const Expanded(child: Text('Hapus Review')),
            ],
          ),
          content: const Text('Yakin ingin menghapus review ini?'),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _accentPurple),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await OwnerReviewService.deleteReview(
        token: widget.token,
        reviewId: reviewId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Review dihapus')));
      setState(load);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kosName = widget.kos['name']?.toString() ?? 'Kos';
    final cs = Theme.of(context).colorScheme;
    final softLavender = Color.lerp(Colors.white, _accentPurple, 0.08)!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: Navigator.of(context).canPop()
              ? () => Navigator.of(context).pop()
              : null,
        ),
        title: Text('Review: $kosName'),
        backgroundColor: _accentPurple,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF7D86BF),
              Color(0xFF9CA6DB),
              Color(0xFFE9ECFF),
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: Column(
          children: [
            if (submitting) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: futureReviews,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => setState(load),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Coba lagi'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentPurple,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final data = snapshot.data ?? const [];
                if (data.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.reviews_outlined,
                            size: 44,
                            color: cs.onSurface.withOpacity(0.45),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Belum ada review',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Nanti review dari penyewa akan muncul di sini.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: cs.onSurface.withOpacity(0.65),
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(load);
                    await futureReviews;
                  },
                  color: _accentPurple,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = data[index];
                      final text = _reviewTextFromItem(item);
                      final id = _reviewIdFromItem(item);
                      final reply = _replyTextFromItem(item).trim();
                      final societyName = _societyNameFromItem(item).trim();
                      final createdAt = _createdAtFromItem(item);

                      return Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: _accentPurple.withOpacity(0.18),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: societyName.isEmpty
                                        ? (createdAt == null
                                              ? const SizedBox.shrink()
                                              : Row(
                                                  children: [
                                                    Icon(
                                                      Icons.schedule,
                                                      size: 16,
                                                      color: cs.onSurface
                                                          .withOpacity(0.6),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      _formatDate(
                                                        context,
                                                        createdAt,
                                                      ),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: cs.onSurface
                                                                .withOpacity(
                                                                  0.6,
                                                                ),
                                                          ),
                                                    ),
                                                  ],
                                                ))
                                        : Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 16,
                                                backgroundColor: softLavender,
                                                child: Icon(
                                                  Icons.person_outline,
                                                  size: 18,
                                                  color: _accentPurple,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      societyName,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.titleSmall,
                                                    ),
                                                    if (createdAt != null)
                                                      Text(
                                                        _formatDate(
                                                          context,
                                                          createdAt,
                                                        ),
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: cs
                                                                  .onSurface
                                                                  .withOpacity(
                                                                    0.6,
                                                                  ),
                                                            ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                  if (id != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: softLavender,
                                        borderRadius: BorderRadius.circular(99),
                                        border: Border.all(
                                          color: _accentPurple.withOpacity(
                                            0.18,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'ID $id',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: _accentPurple.withOpacity(
                                                0.95,
                                              ),
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                text.isEmpty ? '(tanpa teks)' : text,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: cs.onSurface.withOpacity(0.9),
                                    ),
                              ),
                              if (reply.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _replyBox(context, reply, item),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: submitting
                                        ? null
                                        : () => _replyTo(item),
                                    icon: Icon(
                                      reply.isNotEmpty
                                          ? Icons.edit_outlined
                                          : Icons.reply_outlined,
                                    ),
                                    label: Text(
                                      reply.isNotEmpty
                                          ? 'Edit balasan'
                                          : 'Balas',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _accentPurple,
                                      backgroundColor: softLavender,
                                      side: BorderSide(
                                        color: _accentPurple.withOpacity(0.30),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Color.lerp(
                                        _accentPurple,
                                        Colors.black,
                                        0.35,
                                      )!,
                                    ),
                                    tooltip: 'Hapus',
                                    onPressed: submitting
                                        ? null
                                        : () => _delete(item),
                                  ),
                                ],
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
      ),
    );
  }
}
