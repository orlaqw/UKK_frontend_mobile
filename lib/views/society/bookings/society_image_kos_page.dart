import 'package:flutter/material.dart';
import 'package:koshunter6/services/society/booking_service.dart';
import 'package:koshunter6/services/society/society_image_kos_service.dart';
import 'package:koshunter6/utils/image_url.dart';
import 'package:koshunter6/widgets/kos_image_carousel.dart';

class SocietyImageKosPage extends StatefulWidget {
  final String token;
  final int kosId;
  final String kosName;
  final List<String>? initialImageUrls;

  const SocietyImageKosPage({
    super.key,
    required this.token,
    required this.kosId,
    required this.kosName,
    this.initialImageUrls,
  });

  @override
  State<SocietyImageKosPage> createState() => _SocietyImageKosPageState();
}

class _SocietyImageKosPageState extends State<SocietyImageKosPage> {
  late Future<List<String>> _future;

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  String _imageUrlFromItem(dynamic item) {
    if (item is String) return item;
    if (item is Map) {
      final v =
          item['image_url'] ??
          item['url'] ??
          item['image'] ??
          item['file'] ??
          item['path'];
      return _asString(v);
    }
    return '';
  }

  void _load() {
    _future = () async {
      final initial = (widget.initialImageUrls ?? const <String>[])
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false);
      if (initial.isNotEmpty) return initial;

      try {
        final items = await SocietyImageKosService.getImages(
          token: widget.token,
          kosId: widget.kosId,
        );
        final urls = items
            .map((e) => normalizeUkkImageUrl(_imageUrlFromItem(e)))
            .where((u) => u.trim().isNotEmpty)
            .toList(growable: false);
        if (urls.isNotEmpty) return urls;
      } catch (_) {
        // ignore, fall back to detail extraction
      }

      final map = await BookingService.getKosDetail(
        token: widget.token,
        kosId: widget.kosId,
      );
      return _extractImageUrls(map);
    }();
  }

  List<String> _extractImageUrls(Map<String, dynamic> kos) {
    final out = <String>[];

    void addUrl(dynamic raw) {
      final s = normalizeUkkImageUrl(_asString(raw).trim());
      if (s.isEmpty) return;
      if (!out.contains(s)) out.add(s);
    }

    void addFromValue(dynamic v) {
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
        return;
      }
      if (v is Map) {
        addUrl(
          v['image_url'] ?? v['url'] ?? v['image'] ?? v['file'] ?? v['path'],
        );
        return;
      }
      addUrl(v);
    }

    for (final key in const [
      'images',
      'image',
      'image_kos',
      'images_kos',
      'gallery',
      'photos',
      'image_urls',
      'images_url',
    ]) {
      final v = kos[key];
      if (v != null) addFromValue(v);
    }

    for (final nestedKey in const ['kos', 'data', 'detail', 'result']) {
      final v = kos[nestedKey];
      if (v is Map) {
        for (final key in const [
          'images',
          'image',
          'image_kos',
          'images_kos',
          'gallery',
          'photos',
          'image_urls',
          'images_url',
        ]) {
          final nested = v[key];
          if (nested != null) addFromValue(nested);
        }
      }
    }

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
      if (kos.containsKey(key)) addUrl(kos[key]);
    }

    return out;
  }

  void _openFullscreen(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: cs.surface,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Icon(Icons.broken_image_outlined, size: 48),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Tutup',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: Navigator.of(context).canPop()
              ? () => Navigator.of(context).pop()
              : null,
        ),
        title: Text('Gambar: ${widget.kosName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_load),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(_load);
          await _future;
        },
        child: FutureBuilder<List<String>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Gagal memuat gambar\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final urls = snapshot.data ?? const <String>[];
            if (urls.isEmpty) {
              return const Center(child: Text('Belum ada gambar'));
            }

            return ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: KosImageCarousel(
                    imageUrls: urls,
                    height: 220,
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: urls.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemBuilder: (context, i) {
                      final url = urls[i];
                      return InkWell(
                        onTap: () => _openFullscreen(context, url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
