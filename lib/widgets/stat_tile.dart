import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Label kecil + angka besar, seperti di mockup.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final double size;
  final CrossAxisAlignment align;
  final Color? color;

  const StatTile(this.label, this.value,
      {super.key,
      this.unit,
      this.size = 24,
      this.align = CrossAxisAlignment.start,
      this.color});

  /// Kompatibilitas: ukuran besar untuk layar rekam.
  const StatTile.large(this.label, this.value,
      {super.key, this.unit, this.align = CrossAxisAlignment.start, this.color})
      : size = 52;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: size,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: size > 40 ? -1.5 : -0.3,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (unit != null)
              TextSpan(
                text: ' $unit',
                style: TextStyle(
                    fontSize: size > 40 ? 16 : 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500),
              ),
          ]),
        ),
      ],
    );
  }
}
