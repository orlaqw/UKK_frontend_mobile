import 'package:flutter/material.dart';
import 'package:koshunter6/widgets/booking_notification_dialog.dart';
import 'package:koshunter6/services/owner/owner_facility_service.dart';
import 'package:koshunter6/utils/network_error_hint.dart';

class FacilityPage extends StatefulWidget {
  final String token;
  final Map kos;

  const FacilityPage({super.key, required this.token, required this.kos});

  @override
  State<FacilityPage> createState() => _FacilityPageState();
}

class _FacilityPageState extends State<FacilityPage> {
  late Future<List<dynamic>> _futureFacilities;

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _pickKosIdFromMap(Map? map) {
    if (map == null) return 0;
    return _toInt(
      map['id'] ??
          map['kos_id'] ??
          map['id_kos'] ??
          map['kosId'] ??
          map['idKos'],
    );
  }

  int _kosId() {
    // Beberapa endpoint mengembalikan struktur nested.
    final direct = _pickKosIdFromMap(widget.kos);
    if (direct > 0) return direct;
    final data = widget.kos['data'];
    if (data is Map) {
      final nested = _pickKosIdFromMap(data);
      if (nested > 0) return nested;
    }
    final kos = widget.kos['kos'];
    if (kos is Map) {
      final nested = _pickKosIdFromMap(kos);
      if (nested > 0) return nested;
    }
    return 0;
  }

  int _facilityIdFrom(dynamic facility) {
    if (facility is Map) {
      return _toInt(
        facility['id'] ?? facility['facility_id'] ?? facility['id_facility'],
      );
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final kosId = _kosId();
    if (kosId <= 0) {
      _futureFacilities = Future.error(
        Exception(
          'Gagal memuat fasilitas: kosId tidak ditemukan dari data kos.',
        ),
      );
      return;
    }
    _futureFacilities = OwnerFacilityService.getFacilities(
      token: widget.token,
      kosId: kosId,
    );
  }

  Future<void> _showFacilityDialog({Map<String, dynamic>? facility}) async {
    final controller = TextEditingController(
      text: facility != null ? facility['facility_name'] ?? '' : '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        const splashTop = Color(0xFF7D86BF);
        const splashBottom = Color(0xFFE9ECFF);
        final softLavender = Color.lerp(Colors.white, splashBottom, 0.65)!;
        final isEdit = facility != null;
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            isEdit ? 'Edit Fasilitas' : 'Tambah Fasilitas',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: splashTop,
            ),
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Nama fasilitas',
              filled: true,
              fillColor: softLavender,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: splashTop.withOpacity(0.20)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: splashTop, width: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: splashTop,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: splashTop.withOpacity(0.35)),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: splashTop,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ).copyWith(
                overlayColor: WidgetStateProperty.all(
                  softLavender.withOpacity(0.30),
                ),
              ),
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                bool success;
                if (isEdit) {
                  final id = _facilityIdFrom(facility);
                  if (id <= 0) {
                    if (!mounted) return;
                    Navigator.pop(ctx, false);
                    return;
                  }
                  success = await OwnerFacilityService.updateFacility(
                    token: widget.token,
                    facilityId: id,
                    facilityName: name,
                  );
                } else {
                  final kosId = _kosId();
                  if (kosId <= 0) {
                    if (!mounted) return;
                    Navigator.pop(ctx, false);
                    return;
                  }
                  success = await OwnerFacilityService.addFacility(
                    token: widget.token,
                    kosId: kosId,
                    facilityName: name,
                  );
                }

                if (!mounted) return;
                Navigator.pop(ctx, success);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );

    if (result == true && mounted) {
      setState(_reload);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Berhasil disimpan')));
    }
  }

  Future<void> _confirmDelete(int facilityId) async {
    const splashTop = Color(0xFF7D86BF);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BookingNotificationDialog(
        accentColor: splashTop,
        title: 'Hapus Fasilitas',
        message: 'Yakin ingin menghapus fasilitas ini?',
        leftLabel: 'Batal',
        onLeftPressed: () => Navigator.pop(ctx, false),
        rightLabel: 'Hapus',
        onRightPressed: () => Navigator.pop(ctx, true),
      ),
    );

    if (confirm == true) {
      final success = await OwnerFacilityService.deleteFacility(
        token: widget.token,
        facilityId: facilityId,
      );

      if (!mounted) return;
      if (success) {
        setState(_reload);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fasilitas dihapus')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus fasilitas')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

    final kosName = _asString(widget.kos['name']).trim().isNotEmpty
        ? _asString(widget.kos['name']).trim()
        : (_asString(widget.kos['nama_kos']).trim().isNotEmpty
              ? _asString(widget.kos['nama_kos']).trim()
              : 'Kos');

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
          'Fasilitas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
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
              // Space for transparent AppBar.
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
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.08),
                      ),
                    ),
                    child: RefreshIndicator(
                      onRefresh: () async {
                        setState(_reload);
                        await _futureFacilities;
                      },
                      child: FutureBuilder<List<dynamic>>(
                        future: _futureFacilities,
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
                                  'Gagal memuat fasilitas.\n${snapshot.error}${networkErrorHint(snapshot.error!)}',
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
                                    'Belum ada fasilitas.\nTekan tombol + untuk menambah.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: data.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final facility = data[index] as Map;
                              final name =
                                  _asString(facility['facility_name']).trim();
                              final facilityId = _facilityIdFrom(facility);

                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline
                                        .withOpacity(0.10),
                                  ),
                                ),
                                child: ListTile(
                                  title: Text(
                                    name.isEmpty ? 'Tanpa nama' : name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      miniActionIconButton(
                                        icon: Icons.edit,
                                        tooltip: 'Edit',
                                        onPressed: () => _showFacilityDialog(
                                          facility: facility
                                              .cast<String, dynamic>(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      miniActionIconButton(
                                        icon: Icons.delete_outline,
                                        tooltip: 'Hapus',
                                        backgroundColor: splashTop,
                                        iconColor: Colors.white,
                                        borderColor: Colors.white.withOpacity(
                                          0.18,
                                        ),
                                        onPressed: facilityId > 0
                                            ? () =>
                                                _confirmDelete(facilityId)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: splashTop,
        foregroundColor: Colors.white,
        onPressed: () => _showFacilityDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
