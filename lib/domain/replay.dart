import 'dart:math' as math;

import '../models/activity.dart';
import 'metrics.dart';

/// Tanda kilometer di video replay.
class ReplayKm {
  final int km;
  final double fraction; // posisi waktu 0..1 saat km ini tercapai
  final double paceSecondsPerKm;
  const ReplayKm(this.km, this.fraction, this.paceSecondsPerKm);
}

/// Data rute yang sudah disiapkan untuk animasi replay: titik (lat, lon),
/// jarak & waktu bergerak kumulatif, tanda km, dan lokasi kecepatan maks.
class ReplayData {
  final List<double> lat;
  final List<double> lon;
  final List<double> cumMeters;
  final List<double> cumSeconds;
  final List<ReplayKm> kms;
  final double? maxSpeedMps;
  final double? maxSpeedFraction;

  ReplayData._(this.lat, this.lon, this.cumMeters, this.cumSeconds, this.kms,
      this.maxSpeedMps, this.maxSpeedFraction);

  int get length => lat.length;
  double get totalMeters => cumMeters.isEmpty ? 0 : cumMeters.last;
  double get totalSeconds => cumSeconds.isEmpty ? 0 : cumSeconds.last;

  /// Butuh minimal beberapa titik GPS dengan waktu yang berjalan.
  static bool canBuild(List<TrackPoint> pts) =>
      pts.length >= 3 &&
      pts.last.recordedAt.isAfter(pts.first.recordedAt);

  /// [hideEnds]: buang 200 m pertama & terakhir (privasi rumah).
  factory ReplayData.build(Activity a, List<TrackPoint> input,
      {bool hideEnds = false, int maxPoints = 700}) {
    var pts = input;
    if (hideEnds) pts = trimTrackEnds(pts, 200);

    // Jarak & waktu bergerak kumulatif (lompatan saat pause tidak dihitung).
    final n = pts.length;
    final cumM = List<double>.filled(n, 0);
    final cumS = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      final p = pts[i - 1], q = pts[i];
      if (q.segmentStart) {
        cumM[i] = cumM[i - 1];
        cumS[i] = cumS[i - 1];
      } else {
        cumM[i] = cumM[i - 1] +
            haversineMeters(p.latitude, p.longitude, q.latitude, q.longitude);
        cumS[i] = cumS[i - 1] +
            math.max(0, q.recordedAt.difference(p.recordedAt).inMilliseconds / 1000);
      }
    }
    final totalS = n == 0 ? 0.0 : cumS.last;
    double frac(double sec) => totalS > 0 ? (sec / totalS).clamp(0.0, 1.0) : 0;

    // Tanda km dari split penuh.
    final kms = <ReplayKm>[];
    var nextKm = 1;
    for (var i = 1; i < n && nextKm * 1000 <= cumM.last; i++) {
      final target = nextKm * 1000.0;
      if (cumM[i] >= target) {
        final d0 = cumM[i - 1], d1 = cumM[i];
        final f = d1 > d0 ? (target - d0) / (d1 - d0) : 0.0;
        final sec = cumS[i - 1] + (cumS[i] - cumS[i - 1]) * f;
        final prevSec = kms.isEmpty ? 0.0 : kms.last.fraction * totalS;
        kms.add(ReplayKm(nextKm, frac(sec), sec - prevSec));
        nextKm++;
        i--; // satu segmen bisa melewati lebih dari 1 km
      }
    }

    final max = maxSpeedWithIndex(pts, a.sport);

    // Kurangi jumlah titik agar animasi ringan (urutan & ujung tetap).
    final step = n > maxPoints ? (n / maxPoints).ceil() : 1;
    final keep = <int>[
      for (var i = 0; i < n; i++)
        if (i % step == 0 || i == n - 1 || pts[i].segmentStart) i
    ];
    return ReplayData._(
      [for (final i in keep) pts[i].latitude],
      [for (final i in keep) pts[i].longitude],
      [for (final i in keep) cumM[i]],
      [for (final i in keep) cumS[i]],
      kms,
      max?.speed,
      max == null ? null : frac(cumS[max.index]),
    );
  }

  /// Indeks titik terakhir yang sudah dilewati pada fraksi waktu [f], dan
  /// bobot interpolasi ke titik berikutnya.
  (int, double) locate(double f) {
    if (length < 2) return (0, 0);
    final sec = f.clamp(0.0, 1.0) * totalSeconds;
    var lo = 0, hi = length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cumSeconds[mid] <= sec) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (lo >= length - 1) return (length - 1, 0);
    final span = cumSeconds[lo + 1] - cumSeconds[lo];
    return (lo, span > 0 ? ((sec - cumSeconds[lo]) / span).clamp(0.0, 1.0) : 0);
  }

  double metersAt(double f) {
    final (i, w) = locate(f);
    if (i >= length - 1) return totalMeters;
    return cumMeters[i] + (cumMeters[i + 1] - cumMeters[i]) * w;
  }

  double secondsAt(double f) => f.clamp(0.0, 1.0) * totalSeconds;
}

/// Membuang [meters] pertama & terakhir dari titik rute (minimal tersisa
/// separuh rute).
List<TrackPoint> trimTrackEnds(List<TrackPoint> pts, double meters) {
  if (pts.length < 3) return pts;
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last +
        haversineMeters(pts[i - 1].latitude, pts[i - 1].longitude,
            pts[i].latitude, pts[i].longitude));
  }
  final cut = math.min(meters, cum.last / 4);
  final out = [
    for (var i = 0; i < pts.length; i++)
      if (cum[i] >= cut && cum[i] <= cum.last - cut) pts[i]
  ];
  return out.length >= 3 ? out : pts;
}

/// Jadwal adegan video replay untuk durasi [seconds] (15 atau 30).
class ReplayTimeline {
  final double seconds;
  final bool hasPhoto;
  const ReplayTimeline(this.seconds, {this.hasPhoto = false});

  double get introEnd => seconds * 0.10;
  double get routeEnd => seconds * (hasPhoto ? 0.70 : 0.75);
  double get photoEnd => hasPhoto ? seconds * 0.835 : routeEnd;
  double get finalStart => photoEnd;

  /// Fraksi rute (0..1) yang sudah tergambar pada detik [t].
  double routeFraction(double t) =>
      ((t - introEnd) / (routeEnd - introEnd)).clamp(0.0, 1.0);

  /// Detik video saat fraksi rute [f] tercapai.
  double timeAtFraction(double f) => introEnd + f * (routeEnd - introEnd);
}
