import 'package:flutter/material.dart';

class BookingNotificationDialog extends StatelessWidget {
  final Color? accentColor;
  final String title;
  final String message;
  final String leftLabel;
  final VoidCallback onLeftPressed;
  final String? middleLabel;
  final VoidCallback? onMiddlePressed;
  final String rightLabel;
  final VoidCallback onRightPressed;

  const BookingNotificationDialog({
    super.key,
    this.accentColor,
    required this.title,
    required this.message,
    required this.leftLabel,
    required this.onLeftPressed,
    this.middleLabel,
    this.onMiddlePressed,
    required this.rightLabel,
    required this.onRightPressed,
  }) : assert(
          (middleLabel == null && onMiddlePressed == null) ||
              (middleLabel != null && onMiddlePressed != null),
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseAccent = accentColor ?? theme.colorScheme.primary;
    final actionPurple = baseAccent;

    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: titleStyle),
            const SizedBox(height: 12),
            Text(message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: actionPurple,
                  ),
                  onPressed: onLeftPressed,
                  child: Text(leftLabel),
                ),
                if (middleLabel != null) ...[
                  const SizedBox(width: 10),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: actionPurple,
                    ),
                    onPressed: onMiddlePressed,
                    child: Text(middleLabel!),
                  ),
                ],
                const SizedBox(width: 14),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                  ),
                  onPressed: onRightPressed,
                  child: Text(rightLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
