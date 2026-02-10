class BookingPricing {
  static int? parseIntDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  static String formatRupiahRaw(String raw) {
    final v = parseIntDigits(raw);
    if (v == null) return raw;
    return formatRupiahInt(v);
  }

  static String formatRupiahInt(int value) {
    final s = value.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final idxFromEnd = s.length - i;
      buf.write(s[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) {
        buf.write('.');
      }
    }
    final formatted = buf.toString();
    final prefix = value < 0 ? '-Rp ' : 'Rp ';
    return '$prefix$formatted';
  }

  static int proRatedTotal({required int monthlyPrice, required int days}) {
    if (days <= 0) return 0;
    // Default sederhana: asumsi 30 hari per bulan.
    final daily = (monthlyPrice / 30.0);
    return (daily * days).round();
  }

  static int durationDaysInclusive(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final diff = e.difference(s).inDays;
    return diff < 0 ? 0 : diff + 1;
  }
}
