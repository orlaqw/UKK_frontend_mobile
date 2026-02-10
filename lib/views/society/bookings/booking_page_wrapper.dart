import 'package:flutter/material.dart';

class BookingWrapperPage extends StatelessWidget {
  final int kosId;

  const BookingWrapperPage({super.key, required this.kosId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking')),
      body: Center(
        child: Text('Halaman booking (kosId: $kosId) belum tersedia.'),
      ),
    );
  }
}
