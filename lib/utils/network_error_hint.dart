import 'package:flutter/foundation.dart';

String networkErrorHint(Object error) {
  if (!kIsWeb) return '';

  final msg = error.toString();

  if (msg.contains('XMLHttpRequest error') || msg.contains('Failed to fetch')) {
    return '\n\nCatatan: di Flutter Web, error ini biasanya karena CORS / mixed-content / server menolak request dari browser.\n- Jika URL kamu mengarah ke http://localhost:8000 dan kamu buka lewat HP/emulator browser, maka "localhost" mengarah ke perangkat itu sendiri (bukan PC). Pakai IP LAN PC (mis. http://192.168.x.x:8000) atau jalankan backend di domain yang bisa diakses.\n- Jika backend memang remote (https://...), server harus mengizinkan CORS untuk origin web kamu. Alternatif paling mudah: jalankan aplikasi di Android/Windows (bukan Web) untuk menghindari CORS.';
  }

  if (msg.contains('Failed host lookup') || msg.contains('SocketException')) {
    return '\n\nCatatan: server tidak bisa diakses. Cek base URL, koneksi, dan apakah backend sedang jalan.';
  }

  return '';
}
