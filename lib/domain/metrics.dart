import 'dart:math' as math;

import '../models/activity.dart';

/// Jarak great-circle antara dua koordinat, dalam meter.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

double _rad(double deg) => deg * math.pi / 180;

/// Alasan titik GPS ditolak (untuk debug / indikator kualitas sinyal).
enum RejectReason { none, poorAccuracy, jitter, spike, badTimestamp }

/// Menghitung metrik sesi secara bertahap dari titik GPS.
///
/// Hanya titik yang lolos filter yang disimpan, sehingga hasil hitung ulang
/// dari database (saat pemulihan sesi) sama dengan hasil saat merekam.
class MetricsCalculator {
  final SportType sport;

  /// Akurasi horizontal maksimum yang diterima (meter).
  final double maxAccuracy;

  /// Perpindahan minimum agar dianggap bergerak (meter), meredam drift
  /// GPS saat diam.
  final double minStep;

  final List<TrackPoint> points = [];
  double distanceMeters = 0;
  double elevationGainMeters = 0;
  double? _elevRef;
  RejectReason lastReject = RejectReason.none;

  MetricsCalculator(this.sport, {this.maxAccuracy = 25, double? minStep})
      : minStep = minStep ?? (sport == SportType.cycling ? 5 : 3);

  TrackPoint? get last => points.isEmpty ? null : points.last;

  /// Memuat ulang titik tersimpan tanpa filter (sudah difilter saat rekam).
  void restore(List<TrackPoint> stored) {
    points.clear();
    distanceMeters = 0;
    elevationGainMeters = 0;
    _elevRef = null;
    for (final p in stored) {
      _apply(p);
    }
  }

  /// Mencoba menambahkan titik baru. Mengembalikan true bila diterima.
  bool add(TrackPoint p) {
    if (p.accuracy != null && p.accuracy! > maxAccuracy) {
      lastReject = RejectReason.poorAccuracy;
      return false;
    }
    final prev = last;
    if (prev != null && !p.segmentStart) {
      final dt = p.recordedAt.difference(prev.recordedAt).inMilliseconds / 1000;
      if (dt <= 0) {
        lastReject = RejectReason.badTimestamp;
        return false;
      }
      final d = haversineMeters(
          prev.latitude, prev.longitude, p.latitude, p.longitude);
      if (d / dt > sport.maxPlausibleSpeed) {
        lastReject = RejectReason.spike;
        return false;
      }
      if (d < minStep) {
        lastReject = RejectReason.jitter;
        return false;
      }
    }
    lastReject = RejectReason.none;
    _apply(p);
    return true;
  }

  void _apply(TrackPoint p) {
    final prev = last;
    if (prev != null && !p.segmentStart) {
      distanceMeters += haversineMeters(
          prev.latitude, prev.longitude, p.latitude, p.longitude);
    }
    final alt = p.altitude;
    if (alt != null) {
      // Histeresis 3 m agar noise altitude GPS tidak menumpuk jadi elevasi.
      final ref = _elevRef;
      if (ref == null) {
        _elevRef = alt;
      } else if (alt > ref + 3) {
        elevationGainMeters += alt - ref;
        _elevRef = alt;
      } else if (alt < ref - 3) {
        _elevRef = alt;
      }
    }
    points.add(p);
  }

  /// Pace saat ini (detik/km) dari jendela [window] terakhir dalam segmen
  /// yang sama. null bila data belum cukup.
  double? currentPaceSecondsPerKm(
      {Duration window = const Duration(seconds: 30)}) {
    final speed = currentSpeedMps(window: window);
    if (speed == null || speed < 0.3) return null;
    return 1000 / speed;
  }

  double? currentSpeedMps({Duration window = const Duration(seconds: 30)}) {
    if (points.length < 2) return null;
    final end = points.last;
    double d = 0;
    TrackPoint startPoint = end;
    for (var i = points.length - 1; i > 0; i--) {
      final a = points[i - 1];
      final b = points[i];
      if (b.segmentStart) break;
      if (end.recordedAt.difference(a.recordedAt) > window) break;
      d += haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);
      startPoint = a;
    }
    final dt =
        end.recordedAt.difference(startPoint.recordedAt).inMilliseconds / 1000;
    if (dt < 5) return null;
    return d / dt;
  }

  List<ActivitySplit> splits({double splitMeters = 1000}) =>
      computeSplits(points, splitMeters: splitMeters);
}

/// Split per [splitMeters] berdasarkan waktu bergerak antar titik (jeda
/// pause tidak dihitung). Split terakhir yang parsial disertakan bila
/// panjangnya minimal 50 m.
List<ActivitySplit> computeSplits(List<TrackPoint> pts, {double splitMeters = 1000}) {
  final result = <ActivitySplit>[];
  double segDist = 0;
  double segTime = 0;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1];
    final b = pts[i];
    if (b.segmentStart) continue;
    var d = haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);
    var t = b.recordedAt.difference(a.recordedAt).inMilliseconds / 1000;
    while (segDist + d >= splitMeters && d > 0) {
      final need = splitMeters - segDist;
      final frac = need / d;
      segTime += t * frac;
      result.add(ActivitySplit(result.length + 1, splitMeters, segTime.round()));
      d -= need;
      t -= t * frac;
      segDist = 0;
      segTime = 0;
    }
    segDist += d;
    segTime += t;
  }
  if (segDist >= 50) {
    result.add(ActivitySplit(result.length + 1, segDist, segTime.round()));
  }
  return result;
}

/// Estimasi kalori sederhana berbasis MET. Hanya estimasi.
int estimateCalories(SportType sport, int movingSeconds, double avgSpeedKmh,
    {double weightKg = 70}) {
  final met = switch (sport) {
    SportType.walking => avgSpeedKmh < 4.5 ? 3.0 : 4.3,
    SportType.jogging => 7.0,
    SportType.running => avgSpeedKmh < 9.5 ? 9.0 : 11.0,
    SportType.cycling => avgSpeedKmh < 16 ? 4.0 : (avgSpeedKmh < 22 ? 8.0 : 10.0),
  };
  return (met * weightKg * movingSeconds / 3600).round();
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String formatPace(double? secondsPerKm) {
  if (secondsPerKm == null || secondsPerKm <= 0 || secondsPerKm > 3600) {
    return '--:--';
  }
  final total = secondsPerKm.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

String formatKm(double meters) => (meters / 1000).toStringAsFixed(2);
