import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../widgets/stat_tile.dart';
import 'activity_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onStart;
  const HomeScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ActivityStore>();
    final week = store.thisWeek();
    final last = store.items.isEmpty ? null : store.items.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MoveTrack AI',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: store.reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Track. Improve. Be a Better You.',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Minggu ini',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        StatTile('Jarak', formatKm(week.meters), unit: 'km'),
                        StatTile('Waktu', formatDuration(week.seconds)),
                        StatTile('Aktivitas', '${week.count}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Mulai Aktivitas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Aktivitas terakhir',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (last == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Belum ada aktivitas. Mulai rekam pertama Anda!',
                      style: TextStyle(color: AppColors.muted)),
                ),
              )
            else
              ActivityCard(activity: last),
          ],
        ),
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  final Activity activity;
  const ActivityCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final date = DateFormat('EEE, d MMM yyyy • HH:mm', 'id_ID').format(a.startedAt);
    final perf = a.sport.showsSpeed
        ? '${a.avgSpeedKmh.toStringAsFixed(1)} km/j'
        : '${formatPace(a.avgPaceSecondsPerKm)} /km';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: const Color(0x33A3E635),
          foregroundColor: AppColors.lime,
          child: Icon(a.sport.icon),
        ),
        title: Text('${a.sport.label} • ${formatKm(a.distanceMeters)} km',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '$date\n${formatDuration(a.movingSeconds)} • $perf${a.source == ActivitySource.phone ? '' : ' • Garmin'}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ActivityDetailScreen(activityId: a.id))),
      ),
    );
  }
}
