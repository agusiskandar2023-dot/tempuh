import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'dart:ui' show Color;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ids.dart';
import '../data/database.dart';
import '../domain/auto_pause.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';

enum TrackingState { idle, recording, paused }

/// Mesin tracking: idle -> recording <-> paused -> (finish) idle.
///
/// Lokasi diambil lewat foreground service Android (notifikasi tetap +
/// wake lock), sehingga perekaman tetap berjalan saat layar mati / HP sleep.
/// Titik ditulis ke SQLite secara berkala (checkpoint) supaya sesi bisa
/// dipulihkan bila aplikasi dihentikan sistem.
class TrackingService extends ChangeNotifier {
  TrackingService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  TrackingState state = TrackingState.idle;
  Activity? activity;
  MetricsCalculator? calc;

  /// Posisi terakhir dari GPS (juga saat pause / sebelum mulai).
  Position? lastFix;
  String? error;

  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  final List<TrackPoint> _unsaved = [];
  int _seq = 0;
  bool _nextSegmentStart = false;
  int _pausedSeconds = 0;
  DateTime? _pausedSince;
  DateTime _lastCheckpoint = DateTime.fromMillisecondsSinceEpoch(0);

  /// Auto-pause: jeda otomatis saat diam, lanjut otomatis saat bergerak.
  bool autoPauseEnabled = true;

  /// true bila jeda saat ini dibuat oleh auto-pause (bukan tombol PAUSE).
  bool autoPaused = false;
  AutoPauseDetector? _auto;

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      autoPauseEnabled = prefs.getBool('auto_pause') ?? true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setAutoPause(bool enabled) async {
    autoPauseEnabled = enabled;
    if (!enabled && autoPaused) _autoResume();
    if (enabled) _auto?.reset(DateTime.now());
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_pause', enabled);
    } catch (_) {}
  }

  void _autoPause() {
    final now = DateTime.now();
    state = TrackingState.paused;
    autoPaused = true;
    // Jeda dihitung sejak gerakan terakhir, bukan sejak terdeteksi, agar
    // waktu diam tidak masuk waktu aktif.
    final since = _auto?.lastMove ?? now;
    _pausedSince = since.isAfter(now) ? now : since;
    _auto?.markPaused();
    HapticFeedback.mediumImpact();
    _checkpoint();
    notifyListeners();
  }

  void _autoResume() {
    final now = DateTime.now();
    final since = _pausedSince;
    if (since != null) _pausedSeconds += now.difference(since).inSeconds;
    _pausedSince = null;
    autoPaused = false;
    // Gerak berlanjut dari titik berhenti: jarak tetap dihitung.
    _nextSegmentStart = false;
    state = TrackingState.recording;
    _auto?.markResumed(now);
    HapticFeedback.mediumImpact();
    _checkpoint();
    notifyListeners();
  }

  bool get isActive => state != TrackingState.idle;

  int get elapsedSeconds => activity == null
      ? 0
      : DateTime.now().difference(activity!.startedAt).inSeconds;

  int get pausedSeconds {
    final since = _pausedSince;
    return _pausedSeconds +
        (since == null ? 0 : DateTime.now().difference(since).inSeconds);
  }

  int get movingSeconds =>
      (elapsedSeconds - pausedSeconds).clamp(0, 1 << 31).toInt();

  double get distanceMeters => calc?.distanceMeters ?? 0;

  /// Kualitas sinyal untuk indikator GPS.
  String get gpsQuality {
    final f = lastFix;
    if (f == null) return 'Mencari GPS…';
    if (DateTime.now().difference(f.timestamp).inSeconds > 15) {
      return 'Sinyal GPS hilang';
    }
    if (f.accuracy <= 10) return 'GPS bagus (±${f.accuracy.round()} m)';
    if (f.accuracy <= 25) return 'GPS cukup (±${f.accuracy.round()} m)';
    return 'GPS lemah (±${f.accuracy.round()} m)';
  }

  /// Memeriksa layanan lokasi dan izin. Mengembalikan pesan error atau null.
  Future<String?> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Aktifkan Lokasi/GPS di HP terlebih dahulu.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return 'Izin lokasi ditolak.';
    }
    if (perm == LocationPermission.deniedForever) {
      return 'Izin lokasi ditolak permanen. Buka Pengaturan aplikasi untuk mengizinkan.';
    }
    // Android 13+: notifikasi diperlukan agar foreground service terlihat.
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    return null;
  }

  LocationSettings _settings(SportType sport) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Tempuh sedang merekam',
          notificationText: '${sport.label} — tetap merekam saat layar mati',
          notificationIcon:
              const AndroidResource(name: 'ic_stat_tempuh', defType: 'drawable'),
          color: const Color(0xFFA3E635),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: sport == SportType.cycling
            ? ActivityType.otherNavigation
            : ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best);
  }

  void _listen(SportType sport) {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: _settings(sport))
        .listen(_onPosition, onError: (Object e) {
      error = 'GPS error: $e';
      notifyListeners();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (autoPauseEnabled &&
          state == TrackingState.recording &&
          (_auto?.shouldPause(DateTime.now()) ?? false)) {
        _autoPause();
      }
      notifyListeners();
      if (DateTime.now().difference(_lastCheckpoint).inSeconds >= 10) {
        _checkpoint();
      }
    });
  }

  Future<String?> start(SportType sport) async {
    if (isActive) return 'Masih ada sesi yang berjalan.';
    final err = await ensureReady();
    if (err != null) return err;
    error = null;
    _seq = 0;
    _pausedSeconds = 0;
    _pausedSince = null;
    _nextSegmentStart = false;
    _unsaved.clear();
    calc = MetricsCalculator(sport);
    autoPaused = false;
    _auto = AutoPauseDetector.forSport(sport)..reset(DateTime.now());
    activity = Activity(
      id: newUuid(),
      sport: sport,
      startedAt: DateTime.now(),
      status: ActivityStatus.recording,
    );
    state = TrackingState.recording;
    await _db.upsertActivity(activity!);
    _listen(sport);
    notifyListeners();
    return null;
  }

  void _onPosition(Position pos) {
    lastFix = pos;
    if (state == TrackingState.paused &&
        autoPaused &&
        (_auto?.shouldResume(pos.latitude, pos.longitude, pos.accuracy) ?? false)) {
      _autoResume();
    }
    if (state != TrackingState.recording || calc == null) {
      notifyListeners();
      return;
    }
    final pt = TrackPoint(
      sequenceNo: _seq,
      recordedAt: pos.timestamp,
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      accuracy: pos.accuracy,
      speed: pos.speed,
      segmentStart: _nextSegmentStart,
    );
    if (calc!.add(pt)) {
      _seq++;
      _nextSegmentStart = false;
      _unsaved.add(pt);
      _auto?.moved(DateTime.now(), pt.latitude, pt.longitude);
    }
    notifyListeners();
  }

  void pause() {
    if (state != TrackingState.recording) return;
    autoPaused = false;
    state = TrackingState.paused;
    _pausedSince = DateTime.now();
    _checkpoint();
    notifyListeners();
  }

  void resume() {
    if (state != TrackingState.paused) return;
    final since = _pausedSince;
    if (since != null) {
      _pausedSeconds += DateTime.now().difference(since).inSeconds;
    }
    _pausedSince = null;
    _nextSegmentStart = !autoPaused && calc?.last != null;
    autoPaused = false;
    _auto?.reset(DateTime.now());
    state = TrackingState.recording;
    _checkpoint();
    notifyListeners();
  }

  Activity _snapshot(ActivityStatus status) => activity!.copyWith(
        status: status,
        elapsedSeconds: elapsedSeconds,
        movingSeconds: movingSeconds,
        pausedSeconds: pausedSeconds,
        distanceMeters: distanceMeters,
        elevationGainMeters: calc?.elevationGainMeters ?? 0,
        pausedSince: _pausedSince,
        clearPausedSince: _pausedSince == null,
      );

  Future<void> _checkpoint() async {
    final a = activity;
    if (a == null) return;
    _lastCheckpoint = DateTime.now();
    final batch = List<TrackPoint>.of(_unsaved);
    _unsaved.clear();
    try {
      await _db.insertPoints(a.id, batch);
      await _db.upsertActivity(_snapshot(state == TrackingState.paused
          ? ActivityStatus.paused
          : ActivityStatus.recording));
    } catch (e) {
      // Kembalikan ke buffer agar dicoba lagi pada checkpoint berikutnya.
      _unsaved.insertAll(0, batch);
      error = 'Gagal menyimpan checkpoint: $e';
    }
  }

  /// Menyelesaikan sesi. Mengembalikan ID aktivitas yang tersimpan.
  Future<String?> finish() async {
    final a = activity;
    if (a == null) return null;
    // Bila selesai saat pause, sesi berakhir saat pause dimulai (jeda
    // terakhir tidak ikut dihitung).
    final end = (state == TrackingState.paused ? _pausedSince : null) ??
        DateTime.now();
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    final elapsed = end.difference(a.startedAt).inSeconds;
    final paused = _pausedSeconds;
    final moving = (elapsed - paused).clamp(0, 1 << 31).toInt();
    final dist = distanceMeters;
    final speedKmh = moving > 0 ? dist / moving * 3.6 : 0.0;
    final done = a.copyWith(
      status: ActivityStatus.finished,
      finishedAt: end,
      elapsedSeconds: elapsed,
      movingSeconds: moving,
      pausedSeconds: paused,
      distanceMeters: dist,
      elevationGainMeters: calc?.elevationGainMeters ?? 0,
      caloriesEstimated: estimateCalories(a.sport, moving, speedKmh),
      clearPausedSince: true,
    );
    await _db.insertPoints(a.id, List.of(_unsaved));
    _unsaved.clear();
    await _db.upsertActivity(done);
    _reset();
    return done.id;
  }

  Future<void> discard() async {
    final a = activity;
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    if (a != null) await _db.deleteActivity(a.id);
    _reset();
  }

  void _reset() {
    state = TrackingState.idle;
    activity = null;
    calc = null;
    _unsaved.clear();
    _pausedSince = null;
    _pausedSeconds = 0;
    autoPaused = false;
    _auto = null;
    notifyListeners();
  }

  /// Memulihkan sesi yang terputus. Waktu saat aplikasi mati dihitung
  /// sebagai pause; pengguna lalu memilih lanjutkan atau selesaikan.
  Future<String?> recover(Activity a, {bool startGps = true}) async {
    if (startGps) {
      final err = await ensureReady();
      if (err != null) return err;
    }
    final pts = await _db.points(a.id);
    calc = MetricsCalculator(a.sport)..restore(pts);
    autoPaused = false;
    _auto = AutoPauseDetector.forSport(a.sport)..reset(DateTime.now());
    _seq = pts.isEmpty ? 0 : pts.last.sequenceNo + 1;
    activity = a;
    _pausedSeconds = a.pausedSeconds;
    final lastSeen = a.pausedSince ??
        (pts.isNotEmpty ? pts.last.recordedAt : a.startedAt);
    _pausedSince = lastSeen;
    _nextSegmentStart = pts.isNotEmpty;
    _unsaved.clear();
    state = TrackingState.paused;
    if (startGps) _listen(a.sport);
    await _checkpoint();
    notifyListeners();
    return null;
  }

  /// Membuka pengaturan agar Android tidak mematikan aplikasi demi hemat
  /// baterai (penting untuk HP dengan penghemat baterai agresif).
  Future<bool> requestIgnoreBatteryOptimizations() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  Future<bool> isIgnoringBatteryOptimizations() =>
      Permission.ignoreBatteryOptimizations.isGranted;

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
