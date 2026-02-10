import 'package:flutter/material.dart';
import 'booking_history_page.dart';

class BookingHistoryWrapper extends StatelessWidget {
  const BookingHistoryWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    return BookingHistoryPage(
      token: args['token'],
      status: args['status'],
    );
  }
}
