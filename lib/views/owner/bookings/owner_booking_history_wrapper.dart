import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import 'owner_booking_history_page.dart';

class OwnerBookingHistoryWrapper extends StatefulWidget {
  const OwnerBookingHistoryWrapper({super.key});

  @override
  State<OwnerBookingHistoryWrapper> createState() => _OwnerBookingHistoryWrapperState();
}

class _OwnerBookingHistoryWrapperState extends State<OwnerBookingHistoryWrapper> {
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
        return OwnerBookingHistoryPage(token: token);
      },
    );
  }
}
