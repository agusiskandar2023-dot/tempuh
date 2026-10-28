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
    final fmt = DateFormat('EEE d MMM · HH:mm', 'id_ID');
    final connected = _workouts != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          children: [
            const Text('Garmin Forerunner',
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.charcoal, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: AppColors.raised,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.favorite_border, color: AppColors.lime),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Health Connect',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          Text(
                              connected
                                  ? 'Terhubung · ${_workouts!.length} latihan ditemukan'
                                  : 'Ketuk sinkron untuk membaca data jam',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: connected ? AppColors.lime : AppColors.muted)),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Sinkron',
                      style: IconButton.styleFrom(
                          backgroundColor: AppColors.raised,
                          foregroundColor: AppColors.text,
                          fixedSize: const Size(44, 44)),
                      onPressed: _busy ? null : _loadHealthConnect,
                      icon: const Icon(Icons.sync),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Text(
                    'Latihan, jarak, kalori, dan detak jantung dari Garmin Connect. Rute GPS tidak ikut; gunakan impor .FIT untuk rute.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Text(_message!,
                        style: const TextStyle(color: AppColors.amber, fontSize: 13)),
                    if (_message!.contains('belum terpasang'))
                      TextButton(
                        onPressed: () =>
                            context.read<HealthService>().installHealthConnect(),
                        child: const Text('Pasang Health Connect'),
                      ),
                  ],
                ],
              ),
            ),
            if (_workouts != null && _workouts!.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('Latihan dari jam (30 hari)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final w in _workouts!) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  decoration: BoxDecoration(
                      color: AppColors.charcoal,
                      borderRadius: BorderRadius.circular(18)),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${w.sport.label} · ${w.distanceMeters == null ? '-' : formatKm(w.distanceMeters!).replaceAll('.', ',')} km',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          Text(
                              '${fmt.format(w.from)} · ${formatDuration(w.to.difference(w.from).inSeconds)}',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.muted)),
                          Text(w.sourceName,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: w.looksLikeGarmin
                                      ? AppColors.lime
                                      : AppColors.muted)),
                        ],
                      ),
                    ),
                    _imported.contains(w.activityId)
                        ? OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.lime,
                                side: const BorderSide(color: AppColors.lime),
                                shape: const StadiumBorder()),
                            onPressed: null,
                            child: const Text('Diimpor ✓',
                                style: TextStyle(color: AppColors.lime)),
                          )
                        : FilledButton(
                            style: FilledButton.styleFrom(shape: const StadiumBorder()),
                            onPressed: () => _importWorkout(w),
                            child: const Text('Impor',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF3B4A6B)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(children: [
                    Icon(Icons.route, color: AppColors.lime),
                    SizedBox(width: 10),
                    Text('Impor file .FIT (dengan rute)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Garmin Connect web › aktivitas › ikon gerigi › Export Original. Ekstrak .zip, lalu pilih file .fit.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      onPressed: _busy ? null : _importFit,
                      child: const Text('Pilih file .FIT',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 24),
            const Center(
              child: Text('$appName · $appCredit',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ],
        ),
      ),
    );
  }
}
