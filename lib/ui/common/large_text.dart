import 'package:flutter/material.dart';

/// Whether text is shown much larger than normal (system font size and/or
/// the app's text size: at least 130 %). Layouts then stack or drop
/// decorative icons so words still fit on a phone.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) >= 13;

/// A [SwitchListTile] that keeps working with very large text: the switch
/// moves below the texts and the decorative [secondary] icon is dropped,
/// so long words ("anonymously", "substitutions") aren't broken mid-word.
class AdaptiveSwitchTile extends StatelessWidget {
  const AdaptiveSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    if (!isLargeText(context)) {
      return SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        secondary: secondary,
        contentPadding: contentPadding,
      );
    }
    final toggle = onChanged;
    return MergeSemantics(
      child: ListTile(
        contentPadding: contentPadding,
        enabled: toggle != null,
        onTap: toggle == null ? null : () => toggle(!value),
        title: title,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?subtitle,
            Switch(value: value, onChanged: toggle),
          ],
        ),
      ),
    );
  }
}
