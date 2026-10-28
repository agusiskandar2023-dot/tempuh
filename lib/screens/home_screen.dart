import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../widgets/route_thumbnail.dart';
import 'activity_detail_screen.dart';

/// Target jarak mingguan (km). Bisa dibuat bisa diubah di versi berikutnya.
const weeklyTargetKm = 20.0;

class HomeScreen extends StatelessWidget {
  final VoidCallback onStart;
  const HomeScreen({super.key, required this.onStart});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 19) return 'Selamat sore';
    return 'Selamat malam';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ActivityStore>();
    final week = store.thisWeek();
    final days = store.weekDailyMeters();
    final last = store.items.isEmpty ? null : store.items.first;
    final today = DateFormat('EEEE, d MMM', 'id_ID').format(DateTime.now());
    final progress = (week.meters / 1000 / weeklyTargetKm).clamp(0.0, 1.0);
    final maxDay = days.reduce(math.max);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: store.reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              Row(children: [
                const TempuhLogo(size: 36),
                const SizedBox(width: 10),
                const Text(appName,
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                const Spacer(),
                Text(today, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ]),
              const SizedBox(height: 18),
              Text(_greeting(),
                  style: const TextStyle(fontSize: 15, color: AppColors.muted)),
              const Text('Siap bergerak hari ini?',
                  style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: AppColors.charcoal, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Text('Minggu ini',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('Target ${weeklyTargetKm.toStringAsFixed(0)} km',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _big('Jarak', formatKm(week.meters).replaceAll('.', ','), 'km'),
                        _big('Waktu', formatDuration(week.seconds), null),
                        _big('Aktivitas', '${week.count}', null),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: AppColors.navy,
                        color: AppColors.lime,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 64,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 7; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: maxDay <= 0 || days[i] <= 0
                                    ? 4
                                    : math.max(6, 64 * days[i] / maxDay),
                                decoration: BoxDecoration(
                                  color: days[i] > 0 ? AppColors.lime : AppColors.raised,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final d in ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'])
                          Expanded(
                            child: Text(d,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 60,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text('Mulai Aktivitas',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 22),
              const Text('Aktivitas terakhir',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (last == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.charcoal, borderRadius: BorderRadius.circular(18)),
                  child: const Text('Belum ada aktivitas. Mulai rekaman pertama Anda!',
                      style: TextStyle(color: AppColors.muted)),
                )
              else
                ActivityCard(activity: last, showRoute: true),
              const SizedBox(height: 28),
              const Center(
                child: Text(appCredit,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.muted, letterSpacing: 0.3)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _big(String label, String value, String? unit) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: value,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            if (unit != null)
              TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ])),
        ],
      );
}

String activityTitle(Activity a) {
  final h = a.startedAt.hour;
  final part = h < 11 ? 'pagi' : (h < 15 ? 'siang' : (h < 19 ? 'sore' : 'malam'));
  return '${a.sport.label} $part';
}

String activityPerf(Activity a) => a.sport.showsSpeed
    ? '${a.avgSpeedKmh.toStringAsFixed(1).replaceAll('.', ',')} km/j'
    : '${formatPace(a.avgPaceSecondsPerKm)} /km';

class ActivityCard extends StatelessWidget {
  final Activity activity;
  final bool showRoute;
  const ActivityCard({super.key, required this.activity, this.showRoute = false});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final when = DateFormat('EEE d MMM · HH:mm', 'id_ID').format(a.startedAt);
    final hr = a.avgHeartRate == null ? '' : ' · ${a.avgHeartRate} bpm';
    final garmin = a.source != ActivitySource.phone;
    return Material(
      color: AppColors.charcoal,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ActivityDetailScreen(activityId: a.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (showRoute)
                RouteThumbnail(activity: a)
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: AppColors.raised, borderRadius: BorderRadius.circular(14)),
                  child: Icon(a.sport.icon, color: AppColors.lime),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                            '${showRoute ? activityTitle(a) : a.sport.label} · ${formatKm(a.distanceMeters).replaceAll('.', ',')} km',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      if (garmin) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.raised,
                              borderRadius: BorderRadius.circular(99)),
                          child: const Text('Garmin',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.soft)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(when,
                        style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text('${formatDuration(a.movingSeconds)} · ${activityPerf(a)}$hr',
                        style: const TextStyle(fontSize: 13, color: AppColors.soft)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
