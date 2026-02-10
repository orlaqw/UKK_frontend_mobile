import 'package:flutter/material.dart';

import '../../controllers/society/update_profile_controller.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_gradient_scaffold.dart';

class UpdateProfilePage extends StatefulWidget {
  const UpdateProfilePage({super.key});

  @override
  State<UpdateProfilePage> createState() => _UpdateProfilePageState();
}

class _UpdateProfilePageState extends State<UpdateProfilePage> {
  static const Color _accent = Color(0xFF7D86BF);

  final controller = UpdateProfileController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final name = (await AuthService.getUserName()) ?? '';
    final email = (await AuthService.getUserEmail()) ?? '';
    final phone = (await AuthService.getUserPhone()) ?? '';
    controller.setInitialData(name: name, email: email, phone: phone);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final softBg = Color.lerp(Colors.white, _accent, 0.06)!;
    final cardBorder = Color.lerp(_accent, Colors.white, 0.35)!;
    final fieldFill = Color.lerp(Colors.white, _accent, 0.10)!;

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cardBorder),
    );

    final appBarTheme = theme.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      foregroundColor: _accent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    );

    final inputDecorationTheme = theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: fieldFill,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: _accent, width: 1.4),
      ),
      labelStyle: const TextStyle(color: _accent),
    );

    const backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE9ECFF), Color(0xFF9CA6DB), Color(0xFF7D86BF)],
      stops: [0.0, 0.6, 1.0],
    );

    return Theme(
      data: theme.copyWith(
        appBarTheme: appBarTheme,
        inputDecorationTheme: inputDecorationTheme,
        scaffoldBackgroundColor: softBg,
      ),
      child: AppGradientScaffold(
        title: 'Edit Profil',
        backgroundGradient: backgroundGradient,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: AppCard(
                    color: Colors.white,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        TextField(
                          controller: controller.nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Nama'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller.emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller.phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(labelText: 'No. HP'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await controller.submitUpdate(context);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Profile terupdate')),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Simpan',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
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
