import 'package:flutter/material.dart';
import '../../services/society/society_service.dart';
import '../../services/auth_service.dart';

class UpdateProfileController {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();

  late String oldName;
  late String oldEmail;
  late String oldPhone;

  /// Dipanggil saat halaman dibuka
  void setInitialData({
    required String name,
    required String email,
    required String phone,
  }) {
    nameController.text = name;
    emailController.text = email;
    phoneController.text = phone;
    oldName = name;
    oldEmail = email;
    oldPhone = phone;
  }

  Future<void> submitUpdate(BuildContext context) async {
    final nameInput = nameController.text.trim();
    final emailInput = emailController.text.trim();
    final phoneInput = phoneController.text.trim();

    final effectiveName = nameInput.isEmpty ? oldName : nameInput;
    final effectiveEmail = emailInput.isEmpty ? oldEmail : emailInput;

    final effectivePhone = phoneInput.isEmpty ? oldPhone : phoneInput;

    String? phoneToSend;
    if (effectivePhone.trim().isNotEmpty &&
        effectivePhone.trim().toLowerCase() != 'null') {
      // Some backends require phone even if unchanged.
      phoneToSend = effectivePhone;
    }

    final nameChanged = nameInput.isNotEmpty && nameInput != oldName;
    final emailChanged = emailInput.isNotEmpty && emailInput != oldEmail;
    final phoneChanged = phoneInput.isNotEmpty && phoneInput != oldPhone;

    if (!nameChanged && !emailChanged && !phoneChanged) {
      throw Exception('Tidak ada data yang diubah');
    }

    await SocietyService.updateProfile(
      name: effectiveName,
      email: effectiveEmail,
      phone: phoneToSend,
    );

    if (nameChanged) {
      await AuthService.saveUserName(nameInput);
    }

    if (emailChanged) {
      await AuthService.saveUserEmail(emailInput);
    }

    if (phoneChanged) {
      await AuthService.saveUserPhone(phoneInput);
    }
  }

  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
  }
}
