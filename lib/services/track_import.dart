import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/metrics.dart';
import '../models/activity.dart';
import 'fit_parser.dart';

/// Satu aktivitas hasil impor file (FIT, GPX, TCX, atau dari ZIP Strava).
class ImportedTrack {
  final FitActivity data;
  final String fileName;
  final String? title;
  const ImportedTrack(this.data, this.fileName, {this.title});

  DateTime get start =>
      data.startTime ?? (data.points.isNotEmpty ? data.points.first.recordedAt : DateTime.now());

  /// Id lokal; sama untuk file yang sama (FIT/GPX/TCX) agar tidak dobel.
  String get id => 'fit-${start.toUtc().millisecondsSinceEpoch ~/ 1000}';

  Activity toActivity({String? device}) {
    final fit = data;
    final calc = MetricsCalculator(fit.sport)..restore(fit.points);
    final elapsed = (fit.totalElapsedSeconds ??
            (fit.points.length >= 2
                ? fit.points.last.recordedAt.difference(fit.points.first.recordedAt).inSeconds
                : 0))
        .round();
    final moving = (fit.totalTimerSeconds ?? elapsed).round().clamp(0, elapsed > 0 ? elapsed : 1 << 30);
    final dist = (fit.totalDistanceMeters ?? 0) > 0 ? fit.totalDistanceMeters! : calc.distanceMeters;
    return Activity(
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
      sourceDevice: device ?? (fit.isGarmin ? 'Garmin' : fileName),
      title: title,
      maxSpeedMps: computeMaxSpeedMps(fit.points, fit.sport) ?? 0,
    );
  }
}

class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Jenis olahraga dari teks bebas (GPX <type>, TCX Sport, CSV Strava).
SportType? sportFromText(String? s) {
  if (s == null) return null;
  final t = s.trim().toLowerCase();
  if (t.isEmpty) return null;
  // Kode angka tipe GPX Strava: 1 ride, 4 hike, 9 run, 10 walk.
  switch (t) {
    case '1':
      return SportType.cycling;
    case '4':
    case '10':
      return SportType.walking;
    case '9':
      return SportType.running;
  }
  if (t.contains('jog')) return SportType.jogging;
  if (t.contains('run') || t.contains('lari')) return SportType.running;
  if (t.contains('walk') || t.contains('hike') || t.contains('jalan')) return SportType.walking;
  if (t.contains('ride') || t.contains('bik') || t.contains('cycl') || t.contains('sepeda')) {
    return SportType.cycling;
  }
  return null;
}

double? _d(String? s) => s == null ? null : double.tryParse(s.trim());
String? _tag(String block, String name) =>
    RegExp('<(?:\\w+:)?$name\\b[^>]*>([^<]*)</(?:\\w+:)?$name>').firstMatch(block)?.group(1);

/// Titik dengan jeda lebih dari ini dianggap pause (segmen baru).
const _gapSeconds = 60;

FitActivity _build(SportType sport, List<TrackPoint> raw, {
  double? distance,
  double? timer,
  int? calories,
}) {
  raw.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  final pts = <TrackPoint>[];
  var paused = 0;
  for (var i = 0; i < raw.length; i++) {
    final p = raw[i];
    var seg = false;
    if (i > 0) {
      final gap = p.recordedAt.difference(raw[i - 1].recordedAt).inSeconds;
      if (gap > _gapSeconds) {
        seg = true;
        paused += gap;
      }
    }
    pts.add(TrackPoint(
      sequenceNo: i,
      recordedAt: p.recordedAt,
      latitude: p.latitude,
      longitude: p.longitude,
      altitude: p.altitude,
      heartRate: p.heartRate,
      segmentStart: seg,
    ));
  }
  if (pts.length < 2) throw ImportException('File tidak berisi rute GPS dengan waktu.');
  final elapsed = pts.last.recordedAt.difference(pts.first.recordedAt).inSeconds.toDouble();
  final hrs = [for (final p in pts) if (p.heartRate != null && p.heartRate! > 0) p.heartRate!];
  return FitActivity(
    sport: sport,
    startTime: pts.first.recordedAt,
    totalElapsedSeconds: elapsed,
    totalTimerSeconds: timer ?? (elapsed - paused).clamp(0.0, elapsed),
    totalDistanceMeters: distance,
    totalCalories: calories,
    avgHeartRate: hrs.isEmpty ? null : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
    maxHeartRate: hrs.isEmpty ? null : hrs.reduce((a, b) => a > b ? a : b),
    points: pts,
    heartRates: hrs,
  );
}

/// GPX (Strava, Garmin, aplikasi lain).
({FitActivity data, String? title}) parseGpx(String xml, {SportType? sport}) {
  final pts = <TrackPoint>[];
  for (final m in RegExp(r'<trkpt\b([^>]*)>(.*?)</trkpt>', dotAll: true).allMatches(xml)) {
    final attrs = m.group(1)!;
    final body = m.group(2)!;
    final lat = _d(RegExp(r'lat="([^"]+)"').firstMatch(attrs)?.group(1));
    final lon = _d(RegExp(r'lon="([^"]+)"').firstMatch(attrs)?.group(1));
    final time = DateTime.tryParse(_tag(body, 'time') ?? '');
    if (lat == null || lon == null || time == null) continue;
    pts.add(TrackPoint(
      sequenceNo: 0,
      recordedAt: time.toLocal(),
      latitude: lat,
      longitude: lon,
      altitude: _d(_tag(body, 'ele')),
      heartRate: int.tryParse(_tag(body, 'hr') ?? ''),
    ));
  }
  final trk = RegExp(r'<trk\b[^>]*>(.*?)<trkseg', dotAll: true).firstMatch(xml)?.group(1) ?? '';
  final s = sport ?? sportFromText(_tag(trk, 'type')) ?? SportType.running;
  final name = _tag(trk, 'name')?.trim();
  return (data: _build(s, pts), title: (name == null || name.isEmpty) ? null : _unescape(name));
}

/// TCX (Garmin Training Center, Strava).
({FitActivity data, String? title}) parseTcx(String xml, {SportType? sport}) {
  final s = sport ??
      sportFromText(RegExp(r'<Activity\b[^>]*Sport="([^"]*)"').firstMatch(xml)?.group(1)) ??
      SportType.running;
  final pts = <TrackPoint>[];
  for (final m in RegExp(r'<Trackpoint\b[^>]*>(.*?)</Trackpoint>', dotAll: true).allMatches(xml)) {
    final b = m.group(1)!;
    final lat = _d(_tag(b, 'LatitudeDegrees'));
    final lon = _d(_tag(b, 'LongitudeDegrees'));
    final time = DateTime.tryParse(_tag(b, 'Time') ?? '');
    if (lat == null || lon == null || time == null) continue;
    final hrBlock = RegExp(r'<HeartRateBpm\b[^>]*>(.*?)</HeartRateBpm>', dotAll: true).firstMatch(b)?.group(1);
    pts.add(TrackPoint(
      sequenceNo: 0,
      recordedAt: time.toLocal(),
      latitude: lat,
      longitude: lon,
      altitude: _d(_tag(b, 'AltitudeMeters')),
      heartRate: hrBlock == null ? null : int.tryParse(_tag(hrBlock, 'Value') ?? ''),
    ));
  }
  double? dist, timer;
  int? kcal;
  for (final lap in RegExp(r'<Lap\b[^>]*>(.*?)</Lap>', dotAll: true).allMatches(xml)) {
    final l = lap.group(1)!.split('<Track>').first;
    final t = _d(_tag(l, 'TotalTimeSeconds'));
    final d = _d(_tag(l, 'DistanceMeters'));
    final c = int.tryParse(_tag(l, 'Calories') ?? '');
    if (t != null) timer = (timer ?? 0) + t;
    if (d != null) dist = (dist ?? 0) + d;
    if (c != null) kcal = (kcal ?? 0) + c;
  }
  return (data: _build(s, pts, distance: dist, timer: timer, calories: kcal), title: null);
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'");

/// Jenis file dari isinya; nama bisa berubah saat diunduh ulang ("x.gpx-2").
String? sniffTrack(Uint8List b, [String name = '']) {
  if (b.length >= 4 && b[0] == 0x50 && b[1] == 0x4b && b[2] == 0x03 && b[3] == 0x04) return 'zip';
  if (b.length >= 2 && b[0] == 0x1f && b[1] == 0x8b) return 'gz';
  if (b.length >= 12 && String.fromCharCodes(b.sublist(8, 12)) == '.FIT') return 'fit';
  final head = utf8.decode(b.length > 4096 ? b.sublist(0, 4096) : b, allowMalformed: true).toLowerCase();
  if (head.contains('<gpx')) return 'gpx';
  if (head.contains('<trainingcenterdatabase')) return 'tcx';
  return RegExp(r'\.(fit|gpx|tcx|zip)').firstMatch(name.toLowerCase())?.group(1);
}

/// Satu file (bukan ZIP). Formatnya dikenali dari isi file; .gz dibuka otomatis.
ImportedTrack parseTrackFile(String name, Uint8List bytes, {SportType? sport, String? title}) {
  var data = bytes;
  var n = sniffTrack(data, name);
  if (n == 'gz') {
    data = Uint8List.fromList(gzip.decode(bytes));
    n = sniffTrack(data, name.replaceAll(RegExp(r'\.gz$', caseSensitive: false), ''));
  }
  final base = name.split('/').last;
  if (n == 'fit') {
    var fit = FitParser.parse(data);
    if (sport != null && sport != fit.sport) {
      fit = FitActivity(
        sport: sport,
        startTime: fit.startTime,
        totalElapsedSeconds: fit.totalElapsedSeconds,
        totalTimerSeconds: fit.totalTimerSeconds,
        totalDistanceMeters: fit.totalDistanceMeters,
        totalCalories: fit.totalCalories,
        avgHeartRate: fit.avgHeartRate,
        maxHeartRate: fit.maxHeartRate,
        totalAscentMeters: fit.totalAscentMeters,
        manufacturer: fit.manufacturer,
        points: fit.points,
        heartRates: fit.heartRates,
      );
    }
    return ImportedTrack(fit, base, title: title);
  }
  final text = utf8.decode(data, allowMalformed: true);
  if (n == 'gpx') {
    final r = parseGpx(text, sport: sport);
    return ImportedTrack(r.data, base, title: title ?? r.title);
  }
  if (n == 'tcx') {
    final r = parseTcx(text.trimLeft(), sport: sport);
    return ImportedTrack(r.data, base, title: title ?? r.title);
  }
  throw ImportException('Isi $base bukan aktivitas (.fit, .gpx, .tcx, atau .zip).');
}

/// Baris CSV sederhana (mendukung tanda kutip & koma di dalam kutip).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// Data per file dari activities.csv ekspor Strava: nama & jenis aktivitas.
Map<String, ({String? title, SportType? sport, bool skip})> stravaMeta(String csv) {
  final rows = parseCsv(csv);
  if (rows.isEmpty) return {};
  final h = rows.first.map((e) => e.trim().toLowerCase()).toList();
  final iName = h.indexOf('activity name');
  final iType = h.indexOf('activity type');
  final iFile = h.indexOf('filename');
  if (iFile < 0) return {};
  final out = <String, ({String? title, SportType? sport, bool skip})>{};
  for (final r in rows.skip(1)) {
    if (r.length <= iFile || r[iFile].trim().isEmpty) continue;
    final type = iType >= 0 && iType < r.length ? r[iType] : null;
    final sport = sportFromText(type);
    out[r[iFile].trim()] = (
      title: iName >= 0 && iName < r.length && r[iName].trim().isNotEmpty ? r[iName].trim() : null,
      sport: sport,
      // Jenis lain (renang, yoga, dll.) dilewati bila CSV menyebut jenisnya.
      skip: type != null && type.trim().isNotEmpty && sport == null,
    );
  }
  return out;
}

bool isTrackFileName(String n) => RegExp(r'\.(fit|gpx|tcx)(\.gz)?(-\d+)?$', caseSensitive: false)
    .hasMatch(n.replaceAll(RegExp(r' \(\d+\)(?=\.)'), ''));

/// Membuka ZIP (misalnya ekspor akun Strava atau Garmin). [onTrack]
/// dipanggil untuk tiap aktivitas yang berhasil dibaca; file yang gagal
/// dihitung di hasil.
Future<({int ok, int failed, int skipped})> readZip(
  Archive archive,
  Future<void> Function(ImportedTrack t) onTrack,
) async {
  Map<String, ({String? title, SportType? sport, bool skip})> meta = {};
  for (final f in archive.files) {
    if (f.isFile && f.name.toLowerCase().endsWith('activities.csv')) {
      meta = stravaMeta(utf8.decode(f.content, allowMalformed: true));
      break;
    }
  }
  var ok = 0, failed = 0, skipped = 0;
  for (final f in archive.files) {
    if (!f.isFile || !isTrackFileName(f.name)) continue;
    final m = meta[f.name] ??
        meta.entries.where((e) => f.name.endsWith(e.key)).map((e) => e.value).firstOrNull;
    if (m?.skip == true) {
      skipped++;
      continue;
    }
    try {
      final t = parseTrackFile(f.name, f.content, sport: m?.sport, title: m?.title);
      await onTrack(t);
      ok++;
    } catch (_) {
      failed++;
    }
  }
  return (ok: ok, failed: failed, skipped: skipped);
}
