import 'package:flutter/material.dart';

import '../core/theme.dart';

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final bool large;

  const StatTile(this.label, this.value, {super.key, this.unit, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                  fontSize: large ? 40 : 22,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ],
          ],
        ),
      ],
    );
  }
}
