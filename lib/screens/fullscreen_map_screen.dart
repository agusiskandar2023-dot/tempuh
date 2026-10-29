import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../widgets/route_map.dart';
import '../widgets/stat_tile.dart';
import 'home_screen.dart';

/// Peta rute layar penuh: bisa di-zoom dan digeser, dengan ringkasan di bawah.
class FullscreenMapScreen extends StatelessWidget {
  final Activity activity;
  final List<LatLng> route;
  const FullscreenMapScreen({super.key, required this.activity, required this.route});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: RouteMap(route: route, controlsBottom: 140)),
          Positioned(
            top: 0,
            left: 12,
            right: 12,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  IconButton.filled(
                    tooltip: 'Tutup layar penuh',
                    style: IconButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: AppColors.lime,
                        fixedSize: const Size(48, 48)),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(14)),
                      child: Text(activityTitle(a),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.only(bottom: 28),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatTile('Jarak', formatKm(a.distanceMeters).replaceAll('.', ','),
                        unit: 'km', size: 20),
                    StatTile('Waktu aktif', formatDuration(a.movingSeconds), size: 20),
                    a.sport.showsSpeed
                        ? StatTile('Kecepatan',
                            a.avgSpeedKmh.toStringAsFixed(1).replaceAll('.', ','),
                            unit: 'km/j', size: 20)
                        : StatTile('Pace', formatPace(a.avgPaceSecondsPerKm),
                            unit: '/km', size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
