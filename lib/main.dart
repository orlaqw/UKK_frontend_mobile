import 'package:flutter/material.dart';
import 'package:koshunter6/views/login_page.dart';
import 'package:koshunter6/views/owner/master_kos/add_kos_page.dart';
import 'package:koshunter6/views/owner/master_kos/edit_kos_page.dart';
import 'package:koshunter6/views/owner/master_kos/master_kos_page.dart';
import 'package:koshunter6/views/owner/bookings/owner_booking_wrapper.dart';
import 'package:koshunter6/views/owner/bookings/owner_booking_history_wrapper.dart';
import 'package:koshunter6/views/owner/owner_home_page.dart';
import 'package:koshunter6/views/owner/owner_update_profile_page.dart';
import 'package:koshunter6/views/register_page.dart';
import 'package:koshunter6/views/splash_page.dart';
import 'package:koshunter6/views/society/bookings/booking_history_wrapper.dart';
import 'package:koshunter6/views/society/bookings/booking_page_wrapper.dart';
import 'package:koshunter6/views/society/reviews/review_page_wrapper.dart';
import 'package:koshunter6/views/society/society_home_page.dart';
import 'package:koshunter6/views/society/update_profile_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Colors.indigo;
    return MaterialApp(
      title: 'KOS HUNTER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        appBarTheme: const AppBarTheme(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: seedColor,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: seedColor, width: 1.6),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashPage(),
        '/login': (context) => LoginPage(),
        '/register': (context) => RegisterPage(),
        '/owner': (context) => const OwnerHomePage(),
        '/owner-bookings': (context) => const OwnerBookingWrapper(),
        '/owner-booking-history': (context) =>
            const OwnerBookingHistoryWrapper(),
        '/owner-update-profile': (context) => const OwnerUpdateProfilePage(),
        '/society': (context) => const SocietyHomePage(),
        '/update-profile': (context) => const UpdateProfilePage(),
        '/booking': (context) => const BookingWrapperPage(kosId: 0),
        '/booking-history': (context) => const BookingHistoryWrapper(),
        '/review': (context) => const ReviewPageWrapper(),
        '/master-kos': (context) => const MasterKosPage(token: ''),
        '/add-kos': (context) => const AddKosPage(token: ''),
        '/edit-kos': (context) => const EditKosPage(token: '', kos: {}),
      },
    );
  }
}
