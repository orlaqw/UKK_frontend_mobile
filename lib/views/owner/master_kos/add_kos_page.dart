import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/owner/owner_kos_service.dart';
import '../../../utils/booking_pricing.dart';

class AddKosPage extends StatefulWidget {
  final String token;

  const AddKosPage({super.key, required this.token});

  @override
  State<AddKosPage> createState() => _AddKosPageState();
}

class _AddKosPageState extends State<AddKosPage> {
  static const Color _accentPurple = Color(0xFF7D86BF);

  final _name = TextEditingController();
  final _address = TextEditingController();
  final _price = TextEditingController();
  String _gender = 'male';
  bool _saving = false;

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
      await OwnerKosService.addKos(
        token: widget.token,
        userId: userId,
        name: name,
        address: address,
        pricePerMonth: price,
        gender: _gender,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kos berhasil ditambahkan')),
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

  @override
  Widget build(BuildContext context) {
    // Keep palette consistent with Owner pages.
    const splashTop = _accentPurple;
    const splashMid = Color(0xFF9CA6DB);
    const splashBottom = Color(0xFFE9ECFF);

    // Hapus background pada tombol back
    Widget appBarIconBg({required Widget child}) {
      return child;
    }

    final fieldFill = Color.lerp(Colors.white, splashBottom, 0.55)!;

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
        prefixIcon: Icon(icon, color: splashTop),
        labelStyle: const TextStyle(color: splashTop),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: splashTop.withOpacity(0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: splashTop.withOpacity(0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: splashTop, width: 1.8),
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
        title: const Text(
          'Tambah Kos',
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
                            DropdownMenuItem(
                              value: 'male',
                              child: Text('Putra (male)'),
                            ),
                            DropdownMenuItem(
                              value: 'female',
                              child: Text('Putri (female)'),
                            ),
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('Campur (all)'),
                            ),
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
                              backgroundColor: splashTop,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
                          ),
                        ),
                      ],
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
