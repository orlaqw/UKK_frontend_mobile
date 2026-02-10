import 'package:shared_preferences/shared_preferences.dart';

class DeletedReviewStore {
  static const String _key = 'deleted_review_ids_v1';

  static Future<Set<int>> getDeletedReviewIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final out = <int>{};
    for (final s in raw) {
      final v = int.tryParse(s);
      if (v != null && v > 0) out.add(v);
    }
    return out;
  }

  static Future<void> markDeleted(int reviewId) async {
    if (reviewId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    final next = <String>{...current, reviewId.toString()}.toList(growable: false);
    await prefs.setStringList(_key, next);
  }

  static Future<void> unmarkDeleted(int reviewId) async {
    if (reviewId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_key) ?? <String>[];
    current.removeWhere((e) => e == reviewId.toString());
    await prefs.setStringList(_key, current);
  }
}
