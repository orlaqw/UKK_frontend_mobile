import 'package:flutter/material.dart';

import 'package:koshunter6/widgets/booking_notification_dialog.dart';

import '../../../services/auth_service.dart';
import '../../../services/owner/owner_kos_service.dart';
import '../../../utils/booking_pricing.dart';

class EditKosPage extends StatefulWidget {
  final String token;
  final Map kos;

  const EditKosPage({
    super.key,
    required this.token,
    required this.kos,
  });

  @override
  State<EditKosPage> createState() => _EditKosPageState();
}

class _EditKosPageState extends State<EditKosPage> {
  static const Color _accentPurple = Color(0xFF7D86BF);

  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _price;
  late String _gender;
  bool _saving = false;

  String _asString(dynamic v) => (v == null) ? '' : v.toString();

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int get _kosId => _toInt(
        widget.kos['kos_id'] ?? widget.kos['id_kos'] ?? widget.kos['kosId'] ?? widget.kos['id'],
      );

  String _initialGender() {
    final raw = widget.kos['gender'] ??
        widget.kos['kos_gender'] ??
        widget.kos['gender_kos'] ??
        widget.kos['jenis_kos'] ??
        widget.kos['type'] ??
        widget.kos['kategori'] ??
        widget.kos['category'] ??
        widget.kos['for_gender'];
    final s = _asString(raw).trim().toLowerCase();
    if (s.isEmpty) return 'male';
    if (s == 'l' || s == 'lk' || s == 'male' || s.contains('putra')) return 'male';
    if (s == 'p' || s == 'pr' || s == 'female' || s.contains('putri')) return 'female';
    if (s == 'all' || s.contains('campur') || s.contains('mix')) return 'all';
    return s;
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _asString(widget.kos['name'] ?? widget.kos['nama_kos']).trim());
    _address = TextEditingController(text: _asString(widget.kos['address'] ?? widget.kos['alamat']).trim());
    _price = TextEditingController(text: _asString(widget.kos['price_per_month'] ?? widget.kos['harga']).trim());
    _gender = _initialGender();
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _price.dispose();
    super.dispose();
  }

  int? _priceInt() {
    final v = BookingPricing.parseIntDigits(_price.text);
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final address = _address.text.trim();
    final price = _priceInt();

    if (_kosId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID kos tidak valid')),
      );
      return;
    }

    if (name.isEmpty || address.isEmpty || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama, alamat, dan harga wajib diisi')),
      );
      return;
    }

    final userId = await AuthService.getUserId();
    if (!mounted) return;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('user_id tidak ditemukan. Silakan login ulang.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await OwnerKosService.updateKos(
        token: widget.token,
        kosId: _kosId,
        userId: userId,
        name: name,
        address: address,
        pricePerMonth: price,
        gender: _gender,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kos berhasil diupdate')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_kosId <= 0) return;

    final softLavender = Color.lerp(Colors.white, _accentPurple, 0.06)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return BookingNotificationDialog(
          accentColor: _accentPurple,
          title: 'Hapus Kos',
          message: 'Yakin ingin menghapus kos ini?',
          leftLabel: 'Batal',
          onLeftPressed: () => Navigator.pop(ctx, false),
          rightLabel: 'Hapus',
          onRightPressed: () => Navigator.pop(ctx, true),
        );
      },
    );

    if (confirm != true) return;

    setState(() => _saving = true);
    final progress = ValueNotifier<String>('Menyiapkan...');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: softLavender,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _accentPurple.withOpacity(0.22)),
        ),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: _accentPurple),
            const SizedBox(width: 10),
            const Expanded(child: Text('Menghapus...')),
          ],
        ),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, value, __) => Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: _accentPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(value)),
            ],
          ),
        ),
      ),
    );

    try {
      await OwnerKosService.deleteKosCascade(
        token: widget.token,
        kosId: _kosId,
        onProgress: (m) => progress.value = m,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kos dihapus')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      progress.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleName = _name.text.trim().isEmpty ? 'Kos' : _name.text.trim();
    final cs = Theme.of(context).colorScheme;
    final pageBg = Color.lerp(Colors.white, _accentPurple, 0.07)!;
    final softLavender = Color.lerp(Colors.white, _accentPurple, 0.08)!;
    final fieldFill = Color.lerp(Colors.white, _accentPurple, 0.10)!;

    InputDecoration inputDecoration({
      required String label,
      required IconData icon,
      String? hint,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: fieldFill,
        prefixIcon: Icon(icon, color: _accentPurple),
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
        title: Text('Edit: $titleName'),
        backgroundColor: _accentPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Hapus',
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            if (_saving) const SizedBox(height: 14),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: inputDecoration(
                label: 'Nama kos',
                icon: Icons.home_work_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              textInputAction: TextInputAction.next,
              decoration: inputDecoration(
                label: 'Alamat',
                icon: Icons.place_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: inputDecoration(
                label: 'Harga per bulan',
                hint: 'contoh: 1000000',
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: inputDecoration(
                label: 'Tipe (gender)',
                icon: Icons.badge_outlined,
              ),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Putra (male)')),
                DropdownMenuItem(value: 'female', child: Text('Putri (female)')),
                DropdownMenuItem(value: 'all', child: Text('Campur (all)')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _gender = v);
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: softLavender,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accentPurple.withOpacity(0.18)),
              ),
              child: Text(
                'Pastikan data sudah benar sebelum menyimpan.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
