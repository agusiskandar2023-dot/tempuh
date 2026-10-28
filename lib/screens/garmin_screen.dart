import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../services/fit_parser.dart';
import '../services/health_service.dart';
import 'activity_detail_screen.dart';

/// Integrasi Garmin Forerunner:
/// 1. Health Connect: Garmin Connect menyalin sesi latihan + detak jantung
///    ke Health Connect setelah jam tersinkron.
/// 2. File .FIT: ekspor "Original" dari Garmin Connect, lengkap dengan rute.
class GarminScreen extends StatefulWidget {
  const GarminScreen({super.key});

  @override
  State<GarminScreen> createState() => _GarminScreenState();
}

class _GarminScreenState extends State<GarminScreen> {
  List<ExternalWorkout>? _workouts;
  final Set<String> _imported = {};
  bool _busy = false;
  String? _message;

  Future<void> _loadHealthConnect() async {
    final health = context.read<HealthService>();
    final store = context.read<ActivityStore>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final avail = await health.availability();
      if (avail != null) {
        setState(() => _message = avail);
        return;
      }
      if (!await health.authorize()) {
        setState(() => _message =
            'Izin Health Connect ditolak. Buka Health Connect > Izin aplikasi > MoveTrack AI.');
        return;
      }
      final list = await health.workouts(days: 30);
      _imported.clear();
      for (final w in list) {
        if (await store.exists(w.activityId)) _imported.add(w.activityId);
      }
      setState(() {
        _workouts = list;
        if (list.isEmpty) {
          _message =
              'Belum ada sesi latihan 30 hari terakhir. Di aplikasi Garmin Connect: Pengaturan > Aplikasi Terhubung > Health Connect, lalu aktifkan sinkron.';
        }
      });
    } catch (e) {
      setState(() => _message = 'Gagal membaca Health Connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importWorkout(ExternalWorkout w) async {
    final health = context.read<HealthService>();
    final store = context.read<ActivityStore>();
    HeartRateSummary? hr;
    try {
      hr = await health.heartRate(w.from, w.to);
    } catch (_) {}
    final elapsed = w.to.difference(w.from).inSeconds;
    final dist = w.distanceMeters ?? 0;
    final a = Activity(
      id: w.activityId,
      sport: w.sport,
      startedAt: w.from,
      finishedAt: w.to,
      status: ActivityStatus.finished,
      elapsedSeconds: elapsed,
      movingSeconds: elapsed,
      distanceMeters: dist,
      avgHeartRate: hr?.avg,
      maxHeartRate: hr?.max,
      caloriesEstimated: w.calories ??
          estimateCalories(w.sport, elapsed, elapsed > 0 ? dist / elapsed * 3.6 : 0),
      source: ActivitySource.healthConnect,
      sourceDevice: w.sourceName,
    );
    await store.save(a, const []);
    setState(() => _imported.add(w.activityId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${w.sport.label} diimpor ke Riwayat.')));
  }

  Future<void> _importFit() async {
    final store = context.read<ActivityStore>();
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final file = res?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    setState(() => _busy = true);
    try {
      final fit = FitParser.parse(bytes);
      final start = fit.startTime ??
          (fit.points.isNotEmpty ? fit.points.first.recordedAt : DateTime.now());
      final id = 'fit-${start.toUtc().millisecondsSinceEpoch ~/ 1000}';
      final calc = MetricsCalculator(fit.sport)..restore(fit.points);
      final elapsed = (fit.totalElapsedSeconds ??
              (fit.points.length >= 2
                  ? fit.points.last.recordedAt
                      .difference(fit.points.first.recordedAt)
                      .inSeconds
                  : 0))
          .round();
      final moving = (fit.totalTimerSeconds ?? elapsed).round();
      final dist = fit.totalDistanceMeters ?? calc.distanceMeters;
      final a = Activity(
        id: id,
        sport: fit.sport,
        startedAt: start,
        finishedAt: start.add(Duration(seconds: elapsed)),
        status: ActivityStatus.finished,
        elapsedSeconds: elapsed,
        movingSeconds: moving,
        pausedSeconds: (elapsed - moving).clamp(0, elapsed),
        distanceMeters: dist,
        elevationGainMeters: fit.totalAscentMeters ?? calc.elevationGainMeters,
        avgHeartRate: fit.avgHeartRate,
        maxHeartRate: fit.maxHeartRate,
        caloriesEstimated: fit.totalCalories ??
            estimateCalories(fit.sport, moving, moving > 0 ? dist / moving * 3.6 : 0),
        source: ActivitySource.fitFile,
        sourceDevice: fit.isGarmin ? 'Garmin' : file.name,
      );
      if (await store.exists(id)) await store.delete(id);
      await store.save(a, fit.points);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ActivityDetailScreen(activityId: id)));
    } on FitFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal impor: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE d MMM • HH:mm', 'id_ID');
    return Scaffold(
      appBar: AppBar(title: const Text('Garmin Forerunner')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.favorite, color: AppColors.lime),
                    SizedBox(width: 8),
                    Text('Lewat Health Connect',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Sesi latihan, jarak, kalori, dan detak jantung yang disinkronkan Garmin Connect ke Health Connect. Rute GPS tidak ikut; untuk rute pakai impor .FIT.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _loadHealthConnect,
                    icon: const Icon(Icons.sync),
                    label: const Text('Baca latihan 30 hari terakhir'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Text(_message!, style: const TextStyle(color: Colors.amber, fontSize: 13)),
                    if (_message!.contains('belum terpasang'))
                      TextButton(
                        onPressed: () => context.read<HealthService>().installHealthConnect(),
                        child: const Text('Pasang Health Connect'),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (_workouts != null && _workouts!.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final w in _workouts!)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(w.sport.icon,
                      color: w.looksLikeGarmin ? AppColors.lime : AppColors.muted),
                  title: Text(
                      '${w.sport.label} • ${w.distanceMeters == null ? '-' : formatKm(w.distanceMeters!)} km'),
                  subtitle: Text(
                      '${fmt.format(w.from)} • ${formatDuration(w.to.difference(w.from).inSeconds)}\n${w.sourceName}'),
                  isThreeLine: true,
                  trailing: _imported.contains(w.activityId)
                      ? const Icon(Icons.check_circle, color: AppColors.lime)
                      : IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _importWorkout(w),
                        ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.route, color: AppColors.lime),
                    SizedBox(width: 8),
                    Text('Impor file .FIT (dengan rute)',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Di Garmin Connect (web): buka aktivitas > ikon gerigi > Export Original. Ekstrak .zip, lalu pilih file .fit di sini.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _importFit,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Pilih file .FIT'),
                  ),
                ],
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
