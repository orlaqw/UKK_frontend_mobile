import 'package:flutter/material.dart';
import 'package:koshunter6/services/auth_service.dart';
import 'package:koshunter6/utils/booking_receipt_pdf.dart';
import 'package:koshunter6/utils/booking_receipt_data.dart';
import 'package:printing/printing.dart';

class BookingReceiptPreviewPage extends StatefulWidget {
  final Map booking;
  final String? societyName;
  final String? token;
  final bool isOwner;

  const BookingReceiptPreviewPage({
    super.key,
    required this.booking,
    this.societyName,
    this.token,
    this.isOwner = false,
  });

  @override
  State<BookingReceiptPreviewPage> createState() =>
      _BookingReceiptPreviewPageState();
}

class _BookingReceiptPreviewPageState extends State<BookingReceiptPreviewPage> {
  static const Color _accent = Color(0xFF7D86BF);

  late Future<String?> _userNameFuture;
  late Future<Map<String, dynamic>> _bookingForPdfFuture;

  @override
  void initState() {
    super.initState();
    _userNameFuture = AuthService.getUserName();

    final token = (widget.token ?? '').trim();
    // If no token is available, we can't fetch kos detail.
    if (token.isEmpty) {
      _bookingForPdfFuture = Future.value(
        BookingReceiptData.normalizeBooking(widget.booking),
      );
    } else {
      _bookingForPdfFuture = BookingReceiptData.enrich(
        booking: widget.booking,
        token: token,
        isOwner: widget.isOwner,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final softBg = Color.lerp(Colors.white, _accent, 0.06)!;
    final cardBorder = Color.lerp(_accent, Colors.white, 0.35)!;

    return Scaffold(
      backgroundColor: softBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Kembali',
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
              return;
            }
            Navigator.pushNamedAndRemoveUntil(
              context,
              widget.isOwner ? '/owner' : '/society',
              (route) => false,
            );
          },
        ),
        title: const Text('Bukti Pemesanan'),
        centerTitle: true,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        surfaceTintColor: _accent,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _bookingForPdfFuture,
        builder: (context, bookingSnap) {
          if (bookingSnap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_accent),
              ),
            );
          }

          if (bookingSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    bookingSnap.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            );
          }

          final booking =
              bookingSnap.data ?? Map<String, dynamic>.from(widget.booking);

          final overrideName = (widget.societyName ?? '').trim();
          if (widget.isOwner) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: PdfPreview(
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  build: (format) async {
                    return BookingReceiptPdf.build(
                      booking: booking,
                      societyName: null,
                      isOwnerReceipt: true,
                    );
                  },
                ),
              ),
            );
          }

          return FutureBuilder<String?>(
            future: _userNameFuture,
            builder: (context, snapshot) {
              final name = overrideName.isNotEmpty
                  ? overrideName
                  : (snapshot.data ?? '').trim();
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PdfPreview(
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    build: (format) async {
                      return BookingReceiptPdf.build(
                        booking: booking,
                        societyName: name,
                        isOwnerReceipt: false,
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
