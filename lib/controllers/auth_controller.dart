import 'package:flutter/material.dart';

import '../services/auth_api_service.dart';
import '../services/auth_service.dart';

class AuthController {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  String role = 'society';

  Future<void> login(BuildContext context) async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email dan password wajib diisi')),
      );
      return;
    }

    try {
      final result =
          await AuthApiService.login(email: email, password: password);

      String? pickString(dynamic v) {
        if (v is String) {
          final s = v.trim();
          return s.isEmpty ? null : s;
        }
        return null;
      }

      String? pickFromMap(Map<String, dynamic>? m, List<String> keys) {
        if (m == null) return null;
        for (final k in keys) {
          final v = pickString(m[k]);
          if (v != null) return v;
        }
        return null;
      }

      String? extractField(Map<String, dynamic>? json, List<String> keys) {
        if (json == null) return null;

        // Try direct.
        final direct = pickFromMap(json, keys);
        if (direct != null) return direct;

        // Common nested shapes.
        final data = json['data'];
        if (data is Map<String, dynamic>) {
          final fromData = pickFromMap(data, keys);
          if (fromData != null) return fromData;

          final user = data['user'];
          if (user is Map<String, dynamic>) {
            final fromUser = pickFromMap(user, keys);
            if (fromUser != null) return fromUser;
          }
        }

        final user = json['user'];
        if (user is Map<String, dynamic>) {
          final fromUser = pickFromMap(user, keys);
          if (fromUser != null) return fromUser;
        }

        // Some backends nest by role.
        for (final containerKey in const [
          'society',
          'owner',
          'account',
          'profile'
        ]) {
          final v = json[containerKey];
          if (v is Map<String, dynamic>) {
            final fromContainer = pickFromMap(v, keys);
            if (fromContainer != null) return fromContainer;
          }
          if (data is Map<String, dynamic>) {
            final vv = data[containerKey];
            if (vv is Map<String, dynamic>) {
              final fromContainer = pickFromMap(vv, keys);
              if (fromContainer != null) return fromContainer;
            }
          }
        }

        return null;
      }

      final resolvedRole = (result.role ?? '').trim();
      final token = result.token;

      if (resolvedRole.isEmpty) {
        throw Exception('Role tidak ditemukan pada respon login');
      }

      await AuthService.saveUserEmail(email);
      await AuthService.saveRole(resolvedRole);

      final raw = result.rawJson;
      final nameFromRes = extractField(raw, const [
        'name',
        'nama',
        'full_name',
        'fullname',
      ]);
      if (nameFromRes != null) {
        await AuthService.saveUserName(nameFromRes);
      }

      final phoneFromRes = extractField(raw, const [
        'phone',
        'no_hp',
        'nohp',
        'hp',
        'telp',
        'telephone',
      ]);
      if (phoneFromRes != null) {
        await AuthService.saveUserPhone(phoneFromRes);
      }

      if (token != null) {
        await AuthService.saveToken(token);
      } else {
        // Tanpa token, halaman lain yang butuh Authorization akan gagal.
        throw Exception('Token tidak ditemukan pada respon login');
      }

      if (result.userId != null && result.userId! > 0) {
        await AuthService.saveUserId(result.userId!);
      }

      if (!context.mounted) return;
      final next = resolvedRole == 'owner' ? '/owner' : '/society';
      Navigator.of(context).pushReplacementNamed(next);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> register(BuildContext context) async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final phone = phoneController.text.trim();
    final password = passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama, email, dan password wajib diisi')),
      );
      return;
    }

    try {
      final result = await AuthApiService.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
        role: role,
      );

      await AuthService.saveUserName(name);
      await AuthService.saveUserEmail(email);
      if (phone.isNotEmpty) {
        await AuthService.saveUserPhone(phone);
      }
      await AuthService.saveRole((result.role ?? role).trim());

      // Beberapa backend register tidak langsung mengembalikan token.
      if (result.token != null) {
        await AuthService.saveToken(result.token!);
      }

      if (result.userId != null && result.userId! > 0) {
        await AuthService.saveUserId(result.userId!);
      }

      if (!context.mounted) return;

      if (result.token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Register berhasil. Silakan login.')),
        );
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      final next =
          (result.role ?? role).trim() == 'owner' ? '/owner' : '/society';
      Navigator.of(context).pushReplacementNamed(next);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
  }
}
