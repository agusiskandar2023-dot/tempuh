import '../models/activity.dart';
import 'metrics.dart';

/// Deteksi berhenti / bergerak lagi untuk auto-pause.
///
/// - Berhenti: tidak ada perpindahan berarti (titik GPS diterima) selama
///   [stillAfter].
/// - Bergerak lagi: posisi dengan akurasi cukup baik berada minimal
///   [resumeMeters] dari titik tempat berhenti.
class AutoPauseDetector {
  final Duration stillAfter;
  final double resumeMeters;
  final double maxAccuracy;

  DateTime? _lastMove;
  double? _anchorLat;
  double? _anchorLon;
  bool paused = false;

  AutoPauseDetector({
    required this.stillAfter,
    required this.resumeMeters,
    this.maxAccuracy = 25,
  });

  factory AutoPauseDetector.forSport(SportType sport) => switch (sport) {
        SportType.walking => AutoPauseDetector(
            stillAfter: const Duration(seconds: 12), resumeMeters: 8),
        SportType.jogging || SportType.running => AutoPauseDetector(
            stillAfter: const Duration(seconds: 8), resumeMeters: 10),
        SportType.cycling => AutoPauseDetector(
            stillAfter: const Duration(seconds: 8), resumeMeters: 20),
      };

  /// Waktu gerakan terakhir; dipakai sebagai awal jeda agar waktu diam
  /// sebelum terdeteksi tidak ikut terhitung sebagai waktu aktif.
  DateTime? get lastMove => _lastMove;

  /// Dipanggil setiap ada titik GPS yang diterima (artinya bergerak).
  void moved(DateTime t, double lat, double lon) {
    _lastMove = t;
    _anchorLat = lat;
    _anchorLon = lon;
  }

  /// Mulai hitung ulang (misalnya setelah start atau lanjut manual).
  void reset(DateTime now) {
    _lastMove = now;
    paused = false;
  }

  bool shouldPause(DateTime now) =>
      !paused && _lastMove != null && now.difference(_lastMove!) >= stillAfter;

  void markPaused() => paused = true;

  bool shouldResume(double lat, double lon, double? accuracy) {
    if (!paused || _anchorLat == null) return false;
    if (accuracy != null && accuracy > maxAccuracy) return false;
    return haversineMeters(_anchorLat!, _anchorLon!, lat, lon) >= resumeMeters;
  }

  void markResumed(DateTime now) {
    paused = false;
    _lastMove = now;
  }
}
