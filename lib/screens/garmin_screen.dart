import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
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
import '../services/track_import.dart';
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
  String? _progress;
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

  Future<void> _importFile() async {
    final store = context.read<ActivityStore>();
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    final files = res?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    var added = 0, existed = 0, failed = 0, skipped = 0;
    String? lastId;

    Future<void> save(ImportedTrack t, {bool replace = false}) async {
      if (await store.exists(t.id)) {
        if (!replace) {
          existed++;
          return;
        }
        await store.delete(t.id);
      }
      await store.save(t.toActivity(), t.data.points);
      lastId = t.id;
      added++;
      if (mounted) setState(() => _progress = '$added aktivitas diimpor…');
    }

    try {
      for (final f in files) {
        final path = f.path;
        final name = f.name;
        final head = path != null
            ? await File(path).openRead(0, 4096).fold<List<int>>([], (a, b) => a..addAll(b))
            : (f.bytes ?? const <int>[]);
        if (sniffTrack(Uint8List.fromList(head), name) == 'zip') {
          if (path == null) throw ImportException('File ZIP tidak bisa dibuka.');
          final input = InputFileStream(path);
          try {
            final archive = ZipDecoder().decodeStream(input);
            final r = await readZip(archive, (t) => save(t));
            failed += r.failed;
            skipped += r.skipped;
          } finally {
            await input.close();
          }
        } else {
          try {
            final bytes = f.bytes ?? await File(path!).readAsBytes();
            await save(parseTrackFile(name, bytes), replace: files.length == 1);
          } catch (e) {
            if (files.length == 1) rethrow;
            failed++;
          }
        }
      }
      if (!mounted) return;
      if (files.length == 1 && added == 1 && lastId != null && existed == 0 && failed == 0 && skipped == 0) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ActivityDetailScreen(activityId: lastId!)));
      } else {
        final parts = [
          '$added diimpor',
          if (existed > 0) '$existed sudah ada',
          if (skipped > 0) '$skipped bukan lari/jalan/sepeda',
          if (failed > 0) '$failed gagal dibaca',
        ];
        messenger.showSnackBar(SnackBar(content: Text('Impor selesai: ${parts.join(', ')}.')));
      }
    } on FitFormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal impor: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
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
                    Text('Impor file (dengan rute)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Format .FIT, .GPX, .TCX, atau .ZIP (boleh beberapa file sekaligus).\n'
                    '• Garmin Connect web › aktivitas › ikon gerigi › Export Original.\n'
                    '• Strava: Settings › My Account › Download or Delete Your Account › Request your archive. '
                    'Pilih ZIP dari email Strava; semua lari, jalan, dan sepeda masuk sekaligus, yang sudah ada dilewati.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      onPressed: _busy ? null : _importFile,
                      child: const Text('Pilih file',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const CircularProgressIndicator(),
                  if (_progress != null) ...[
                    const SizedBox(height: 10),
                    Text(_progress!, style: const TextStyle(color: AppColors.muted)),
                  ],
                ]),
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
