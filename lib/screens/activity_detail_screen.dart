import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../services/health_service.dart';
import '../widgets/route_map.dart';
import '../widgets/stat_tile.dart';

class ActivityDetailScreen extends StatefulWidget {
  final String activityId;
  const ActivityDetailScreen({super.key, required this.activityId});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  Activity? _a;
  List<TrackPoint> _pts = [];
  bool _loading = true;
  bool _fetchingHr = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<ActivityStore>();
    final a = await store.byId(widget.activityId);
    final pts = await store.points(widget.activityId);
    if (!mounted) return;
    setState(() {
      _a = a;
      _pts = pts;
      _loading = false;
    });
  }

  Future<void> _fetchHeartRate() async {
    final a = _a!;
    final health = context.read<HealthService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _fetchingHr = true);
    try {
      final avail = await health.availability();
      if (avail != null) {
        messenger.showSnackBar(SnackBar(content: Text(avail)));
        return;
      }
      if (!await health.authorize()) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Izin Health Connect ditolak.')));
        return;
      }
      final hr = await health.heartRate(a.startedAt, a.finishedAt ?? DateTime.now());
      if (hr == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Belum ada data detak jantung pada rentang waktu ini. Pastikan jam Garmin sudah tersinkron ke Garmin Connect.')));
        return;
      }
      final updated = a.copyWith(avgHeartRate: hr.avg, maxHeartRate: hr.max);
      await context.read<ActivityStore>().update(updated);
      setState(() => _a = updated);
      messenger.showSnackBar(SnackBar(
          content: Text('Detak jantung ditambahkan dari ${hr.samples} sampel.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal membaca data: $e')));
    } finally {
      if (mounted) setState(() => _fetchingHr = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus aktivitas?'),
        content: const Text('Data rute dan metrik akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<ActivityStore>().delete(widget.activityId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final a = _a;
    if (a == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Aktivitas tidak ditemukan.')));
    }
    final route = _pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final splits = computeSplits(_pts);
    final date = DateFormat('EEEE, d MMMM yyyy • HH:mm', 'id_ID').format(a.startedAt);
    return Scaffold(
      appBar: AppBar(
        title: Text(a.sport.label),
        actions: [
          IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 300,
            child: route.length >= 2
                ? RouteMap(route: route)
                : Container(
                    color: AppColors.charcoal,
                    alignment: Alignment.center,
                    child: const Text('Tidak ada rute GPS untuk aktivitas ini',
                        style: TextStyle(color: AppColors.muted)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: const TextStyle(color: AppColors.muted)),
                if (a.source != ActivitySource.phone)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        'Sumber: ${a.source == ActivitySource.fitFile ? 'File .FIT' : 'Health Connect'}${a.sourceDevice == null ? '' : ' (${a.sourceDevice})'}',
                        style: const TextStyle(color: AppColors.lime, fontSize: 12)),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 28,
                  runSpacing: 16,
                  children: [
                    StatTile('Jarak', formatKm(a.distanceMeters), unit: 'km'),
                    StatTile('Waktu aktif', formatDuration(a.movingSeconds)),
                    a.sport.showsSpeed
                        ? StatTile('Kecepatan rata-rata',
                            a.avgSpeedKmh.toStringAsFixed(1), unit: 'km/j')
                        : StatTile('Pace rata-rata',
                            formatPace(a.avgPaceSecondsPerKm), unit: '/km'),
                    StatTile('Waktu total', formatDuration(a.elapsedSeconds)),
                    StatTile('Elevasi naik',
                        a.elevationGainMeters.round().toString(), unit: 'm'),
                    StatTile('Kalori (estimasi)',
                        '${a.caloriesEstimated ?? '-'}', unit: 'kkal'),
                    if (a.avgHeartRate != null)
                      StatTile('HR rata-rata', '${a.avgHeartRate}', unit: 'bpm'),
                    if (a.maxHeartRate != null)
                      StatTile('HR maks', '${a.maxHeartRate}', unit: 'bpm'),
                  ],
                ),
                if (a.avgHeartRate == null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _fetchingHr ? null : _fetchHeartRate,
                    icon: _fetchingHr
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.favorite_border),
                    label: const Text('Ambil detak jantung dari Garmin'),
                  ),
                ],
                if (splits.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Split per km',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _splitTable(splits, a.sport),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitTable(List<ActivitySplit> splits, SportType sport) {
    final fastest = splits
        .where((s) => s.distanceMeters >= 999)
        .fold<double?>(null, (m, s) => m == null || s.paceSecondsPerKm < m ? s.paceSecondsPerKm : m);
    return Card(
      child: Column(
        children: [
          for (final s in splits)
            ListTile(
              dense: true,
              leading: Text('${s.distanceMeters >= 999 ? s.number : formatKm(s.distanceMeters)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              title: Text(sport.showsSpeed
                  ? '${s.durationSeconds == 0 ? '--' : (s.distanceMeters / s.durationSeconds * 3.6).toStringAsFixed(1)} km/j'
                  : '${formatPace(s.paceSecondsPerKm)} /km'),
              trailing: Text(formatDuration(s.durationSeconds)),
              tileColor: s.paceSecondsPerKm == fastest ? const Color(0x22A3E635) : null,
            ),
        ],
      ),
    );
  }
}
