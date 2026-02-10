import 'package:flutter/material.dart';
import 'package:koshunter6/widgets/booking_notification_dialog.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/owner/owner_image_kos_service.dart';
import '../../../utils/image_url.dart';
import '../../../widgets/kos_image_carousel.dart';

class ImageKosPage extends StatefulWidget {
  final String token;
  final Map kos;

  const ImageKosPage({
    super.key,
    required this.token,
    required this.kos,
  });

  @override
  State<ImageKosPage> createState() => _ImageKosPageState();
}

class _ImageKosPageState extends State<ImageKosPage> {
  late Future<List<dynamic>> _future;
  final _picker = ImagePicker();

  int get _kosId => int.tryParse(widget.kos['id']?.toString() ?? '') ?? 0;

  void _load() {
    _future = OwnerImageKosService.getImages(token: widget.token, kosId: _kosId);
  }

  int _getImageId(Map img) {
    final v = img['id'] ?? img['image_id'] ?? img['id_image'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _getImageUrl(Map img) {
    final v = img['image_url'] ??
        img['url'] ??
        img['image'] ??
        img['file'] ??
        img['path'];
    return (v ?? '').toString();
  }

  void _openFullscreen(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.white,
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

  Future<void> _pickAndUpload() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      await OwnerImageKosService.uploadImage(
        token: widget.token,
        kosId: _kosId,
        file: picked,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image berhasil diupload')),
      );
      setState(_load);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _pickAndUpdate(int imageId) async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      await OwnerImageKosService.updateImage(
        token: widget.token,
        imageId: imageId,
        file: picked,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image berhasil diupdate')),
      );
      setState(_load);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _confirmDelete(int imageId) async {
    const splashTop = Color(0xFF7D86BF);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BookingNotificationDialog(
        accentColor: splashTop,
        title: 'Hapus Gambar',
        message: 'Yakin ingin menghapus image ini?',
        leftLabel: 'Batal',
        onLeftPressed: () => Navigator.pop(ctx, false),
        rightLabel: 'Hapus',
        onRightPressed: () => Navigator.pop(ctx, true),
      ),
    );

    if (confirm != true) return;

    try {
      await OwnerImageKosService.deleteImage(token: widget.token, imageId: imageId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image dihapus')),
      );
      setState(_load);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final kosName = (widget.kos['name'] ?? widget.kos['nama'] ?? 'Kos').toString();
    const canMutate = true;

    // Keep palette consistent with OwnerHomePage / Splash gradient.
    const splashTop = Color(0xFF7D86BF);
    const splashMid = Color(0xFF9CA6DB);
    const splashBottom = Color(0xFFE9ECFF);

    final softLavender = Color.lerp(Colors.white, splashBottom, 0.65)!;
    final boxBorder = splashTop.withOpacity(0.18);

    Widget appBarIconBg({required Widget child}) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.22)),
        ),
        child: Center(child: child),
      );
    }

    Widget miniActionIconButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      Color? backgroundColor,
      Color? iconColor,
      Color? borderColor,
    }) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor ?? softLavender,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor ?? boxBorder),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          splashRadius: 18,
          iconSize: 20,
          color: iconColor ?? splashTop,
          icon: Icon(icon),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: appBarIconBg(
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              splashRadius: 20,
              onPressed: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
          ),
        ),
        title: const Text(
          'Gambar',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: appBarIconBg(
              child: IconButton(
                icon: const Icon(Icons.add_a_photo),
                tooltip: 'Upload Gambar',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 40, height: 40),
                splashRadius: 20,
                onPressed: _pickAndUpload,
              ),
            ),
          ),
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
          child: Column(
            children: [
              const SizedBox(height: kToolbarHeight - 40),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kos: $kosName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.08),
                      ),
                    ),
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
                          return ListView(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            children: [
                              Text(
                                'Gagal memuat gambar.\n${snapshot.error}',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          );
                        }

                        final data = snapshot.data ?? [];
                        if (data.isEmpty) {
                          return ListView(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            children: const [
                              SizedBox(height: 48),
                              Center(
                                child: Text(
                                  'Belum ada gambar.\nTekan ikon kamera untuk upload.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          );
                        }

                        final urls = data
                            .whereType<Map>()
                            .map(
                              (m) => normalizeUkkImageUrl(
                                _getImageUrl(
                                  Map<String, dynamic>.from(m),
                                ),
                              ),
                            )
                            .where((u) => u.isNotEmpty)
                            .toList(growable: false);

                        return Column(
                          children: [
                            if (urls.isNotEmpty) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 12, 12, 8),
                                child: KosImageCarousel(
                                  imageUrls: urls,
                                  height: 220,
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(16),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                            ],
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: data.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = data[index];
                                  if (item is! Map) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline
                                              .withOpacity(0.10),
                                        ),
                                      ),
                                      child: Text(item.toString()),
                                    );
                                  }

                                  final img =
                                      Map<String, dynamic>.from(item);
                                  final imageId = _getImageId(img);
                                  final rawUrl = _getImageUrl(img);
                                  final url = normalizeUkkImageUrl(rawUrl);

                                  final leading = url.isNotEmpty
                                      ? Image.network(
                                          url,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                        )
                                      : const Icon(Icons.image_outlined);

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withOpacity(0.10),
                                      ),
                                    ),
                                    child: ListTile(
                                      leading: InkWell(
                                        onTap: url.isNotEmpty
                                            ? () =>
                                                _openFullscreen(context, url)
                                            : null,
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: SizedBox(
                                            width: 56,
                                            height: 56,
                                            child: Center(child: leading),
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        'ID: $imageId',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      subtitle: Text(
                                        rawUrl.isEmpty
                                            ? 'Tidak ada URL/path'
                                            : rawUrl,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          miniActionIconButton(
                                            icon: Icons.edit,
                                            tooltip: 'Update Gambar',
                                            onPressed:
                                                (canMutate && imageId > 0)
                                                    ? () =>
                                                        _pickAndUpdate(imageId)
                                                    : null,
                                          ),
                                          const SizedBox(width: 8),
                                          miniActionIconButton(
                                            icon: Icons.delete_outline,
                                            tooltip: 'Hapus Gambar',
                                            backgroundColor: splashTop,
                                            iconColor: Colors.white,
                                            borderColor:
                                                Colors.white.withOpacity(0.18),
                                            onPressed:
                                                (canMutate && imageId > 0)
                                                    ? () => _confirmDelete(
                                                          imageId,
                                                        )
                                                    : null,
                                          ),
                                        ],
                                      ),
                                      onTap: () async {
                                        if (imageId <= 0) return;
                                        try {
                                          final detail =
                                              await OwnerImageKosService
                                                  .detailImage(
                                            token: widget.token,
                                            imageId: imageId,
                                          );
                                          if (!context.mounted) return;
                                          showDialog<void>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: Colors.white,
                                              surfaceTintColor:
                                                  Colors.transparent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                              title: Text(
                                                'Detail Gambar ($imageId)',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: splashTop,
                                                ),
                                              ),
                                              content: SingleChildScrollView(
                                                child: Text(detail.toString()),
                                              ),
                                              actions: [
                                                TextButton(
                                                  style:
                                                      TextButton.styleFrom(
                                                    foregroundColor: splashTop,
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 14,
                                                      vertical: 10,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(12),
                                                      side: BorderSide(
                                                        color: splashTop
                                                            .withOpacity(0.35),
                                                      ),
                                                    ),
                                                  ),
                                                  onPressed: () =>
                                                      Navigator.pop(ctx),
                                                  child: const Text('Tutup'),
                                                ),
                                              ],
                                            ),
                                          );
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(e.toString()),
                                            ),
                                          );
                                        }
                                      },
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
