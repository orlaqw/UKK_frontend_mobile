import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import 'owner_bookings_page.dart';

class OwnerBookingWrapper extends StatefulWidget {
  const OwnerBookingWrapper({super.key});

  @override
  State<OwnerBookingWrapper> createState() => _OwnerBookingWrapperState();
}

class _OwnerBookingWrapperState extends State<OwnerBookingWrapper> {
  late Future<String?> _tokenFuture;

  @override
  void initState() {
    super.initState();
    _tokenFuture = AuthService.getToken();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _tokenFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final token = snap.data;
        if (token == null) {
          return const Scaffold(body: Center(child: Text('Token tidak ditemukan')));
        }
        return OwnerBookingsPage(token: token);
      },
    );
  }
}
