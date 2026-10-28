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
import 'home_screen.dart';

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
    final store = context.read<ActivityStore>();
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
      await store.update(updated);
      if (!mounted) return;
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
        backgroundColor: AppColors.charcoal,
        title: const Text('Hapus aktivitas?'),
        content: const Text('Data rute dan metrik akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus', style: TextStyle(color: AppColors.danger))),
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
    final date =
        DateFormat('EEEE, d MMMM yyyy · HH:mm', 'id_ID').format(a.startedAt);
    String km(double m) => formatKm(m).replaceAll('.', ',');
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(activityTitle(a),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(date, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
        actions: [
          IconButton(
              tooltip: 'Hapus',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 240,
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (a.source != ActivitySource.phone)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                        'Sumber: ${a.source == ActivitySource.fitFile ? 'File .FIT' : 'Health Connect'}${a.sourceDevice == null ? '' : ' (${a.sourceDevice})'}',
                        style: const TextStyle(color: AppColors.lime, fontSize: 12)),
                  ),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.9,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 8,
                  children: [
                    StatTile('Jarak', km(a.distanceMeters), unit: 'km'),
                    StatTile('Waktu aktif', formatDuration(a.movingSeconds)),
                    a.sport.showsSpeed
                        ? StatTile('Kecepatan',
                            a.avgSpeedKmh.toStringAsFixed(1).replaceAll('.', ','),
                            unit: 'km/j')
                        : StatTile('Pace rata-rata', formatPace(a.avgPaceSecondsPerKm),
                            unit: '/km'),
                    StatTile('Elevasi naik', a.elevationGainMeters.round().toString(),
                        unit: 'm'),
                    StatTile('Kalori (est.)', '${a.caloriesEstimated ?? '-'}'),
                    StatTile('Waktu total', formatDuration(a.elapsedSeconds)),
                  ],
                ),
                const SizedBox(height: 14),
                Material(
                  color: AppColors.charcoal,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.favorite, color: AppColors.danger),
                      const SizedBox(width: 12),
                      Expanded(
                        child: a.avgHeartRate != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${a.avgHeartRate} bpm rata-rata${a.maxHeartRate == null ? '' : ' · maks ${a.maxHeartRate}'}',
                                      style: const TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.w700)),
                                  Text(
                                      a.source == ActivitySource.fitFile
                                          ? 'Dari file .FIT Garmin'
                                          : 'Dari Garmin Forerunner via Health Connect',
                                      style: const TextStyle(
                                          fontSize: 12, color: AppColors.muted)),
                                ],
                              )
                            : const Text('Belum ada detak jantung',
                                style: TextStyle(fontSize: 14, color: AppColors.soft)),
                      ),
                      if (a.avgHeartRate == null)
                        TextButton(
                          onPressed: _fetchingHr ? null : _fetchHeartRate,
                          child: _fetchingHr
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Ambil dari Garmin'),
                        ),
                    ]),
                  ),
                ),
                if (splits.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Split per km',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ..._splitRows(splits, a.sport),
                  const SizedBox(height: 4),
                  const Text('Split tercepat ditandai hijau.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _splitRows(List<ActivitySplit> splits, SportType sport) {
    final full = splits.where((s) => s.distanceMeters >= 999).toList();
    final paces = (full.isEmpty ? splits : full).map((s) => s.paceSecondsPerKm);
    final fastest = paces.reduce((a, b) => a < b ? a : b);
    return [
      for (final s in splits)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
              width: 34,
              child: Text(
                  s.distanceMeters >= 999 ? '${s.number}' : formatKm(s.distanceMeters),
                  style: TextStyle(
                      fontSize: 13,
                      color: s.paceSecondsPerKm == fastest
                          ? AppColors.lime
                          : AppColors.muted)),
            ),
            SizedBox(
              width: 64,
              child: Text(
                  sport.showsSpeed
                      ? (s.durationSeconds == 0
                          ? '--'
                          : (s.distanceMeters / s.durationSeconds * 3.6)
                              .toStringAsFixed(1)
                              .replaceAll('.', ','))
                      : formatPace(s.paceSecondsPerKm),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: s.paceSecondsPerKm == fastest ? AppColors.lime : null)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: s.paceSecondsPerKm <= 0
                      ? 0
                      : (fastest / s.paceSecondsPerKm).clamp(0.05, 1.0),
                  minHeight: 10,
                  backgroundColor: AppColors.raised,
                  color: s.paceSecondsPerKm == fastest
                      ? AppColors.lime
                      : const Color(0xFF64748B),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 48,
              child: Text(formatDuration(s.durationSeconds),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ]),
        ),
    ];
  }
}
