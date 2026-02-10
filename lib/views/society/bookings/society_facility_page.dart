import 'package:flutter/material.dart';
import 'package:koshunter6/services/society/booking_service.dart';
import 'package:koshunter6/utils/network_error_hint.dart';

class SocietyFacilityPage extends StatefulWidget {
  final String token;
  final int kosId;
  final String kosName;

  const SocietyFacilityPage({
    super.key,
    required this.token,
    required this.kosId,
    required this.kosName,
  });

  @override
  State<SocietyFacilityPage> createState() => _SocietyFacilityPageState();
}

class _SocietyFacilityPageState extends State<SocietyFacilityPage> {
  late Future<List<String>> _future;

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  List<String> _extractFacilitiesFromDetail(Map<String, dynamic> detail) {
    final out = <String>[];

    void addFacility(dynamic v) {
      final s = _asString(v).trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return;
      if (!out.contains(s)) out.add(s);
    }

    final raw =
        detail['kos_facilities'] ??
        detail['facilities'] ??
        detail['facility'] ??
        detail['fasilitas'] ??
        detail['facilities_kos'] ??
        detail['facility_kos'];

    if (raw is List) {
      for (final it in raw) {
        if (it is Map) {
          addFacility(it['facility_name'] ?? it['name'] ?? it['nama_fasilitas']);
        } else {
          addFacility(it);
        }
      }
    }

    return out;
  }

  void _load() {
    _future = BookingService.getKosDetail(token: widget.token, kosId: widget.kosId)
        .then(_extractFacilitiesFromDetail);
  }

  Widget _facilityCard(BuildContext context, String name) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withOpacity(0.10)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Center(
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
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
        title: Text('Fasilitas: ${widget.kosName}'),
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
                  'Gagal memuat fasilitas\n${snapshot.error}${networkErrorHint(snapshot.error!)}',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final facilities = snapshot.data ?? const <String>[];
            if (facilities.isEmpty) {
              return const Center(
                child: Text(
                  'Belum ada fasilitas untuk kos ini.',
                  textAlign: TextAlign.center,
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: facilities
                      .map((f) => _facilityCard(context, f))
                      .toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
