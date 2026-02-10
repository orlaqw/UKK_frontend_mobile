import 'package:flutter/material.dart';

import '../../../widgets/app_card.dart';
import '../../../widgets/app_gradient_scaffold.dart';
import 'reviews_page.dart';

class ReviewPageWrapper extends StatelessWidget {
  const ReviewPageWrapper({super.key});

  static const Color _accent = Color(0xFF7D86BF);

  int? _tryParseInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final token = args['token']?.toString();
      final kosId = _tryParseInt(args['kosId'] ?? args['kos_id']);
      final kosName = args['kosName']?.toString();
      final readOnly = args['readOnly'] == true;

      if ((token != null && token.trim().isNotEmpty) && kosId != null) {
        return ReviewPage(
          token: token,
          kosId: kosId,
          kosName: kosName,
          readOnly: readOnly,
        );
      }
    }

    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      foregroundColor: _accent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    );

    const backgroundGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE9ECFF), Color(0xFF9CA6DB), Color(0xFF7D86BF)],
      stops: [0.0, 0.6, 1.0],
    );

    return Theme(
      data: theme.copyWith(appBarTheme: appBarTheme),
      child: AppGradientScaffold(
        title: 'Review',
        backgroundGradient: backgroundGradient,
        child: Center(
          child: AppCard(
            color: Colors.white,
            child: Text(
              'Halaman review belum tersedia.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
}
