import 'package:flutter/foundation.dart';

import '../models/activity.dart';
import 'database.dart';

/// Repository aktivitas selesai untuk layar Beranda dan Riwayat.
class ActivityStore extends ChangeNotifier {
  ActivityStore({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;
  List<Activity> items = [];
  bool loading = false;

  /// Dipanggil setiap data aktivitas dimuat ulang / berubah; dipakai untuk
  /// memicu sinkron ke Neon (lihat main.dart).
  VoidCallback? onChanged;

  Future<void> reload() async {
    loading = true;
    notifyListeners();
    try {
      items = await _db.finishedActivities();
    } finally {
      loading = false;
      notifyListeners();
    }
    onChanged?.call();
  }

  Future<void> delete(String id) async {
    await _db.deleteActivity(id);
    await reload();
  }

  Future<void> save(Activity a, List<TrackPoint> pts) async {
    await _db.upsertActivity(a);
    await _db.insertPoints(a.id, pts);
    await reload();
  }

  Future<bool> exists(String id) => _db.exists(id);

  Future<Activity?> byId(String id) => _db.activity(id);

  Future<void> update(Activity a) async {
    await _db.upsertActivity(a);
    await reload();
  }

  Future<List<TrackPoint>> points(String id) => _db.points(id);

  /// Jarak per hari (meter) minggu berjalan, Senin..Minggu.
  List<double> weekDailyMeters() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final days = List<double>.filled(7, 0);
    for (final a in items) {
      if (a.startedAt.isBefore(monday)) continue;
      final i = a.startedAt.weekday - 1;
      days[i] += a.distanceMeters;
    }
    return days;
  }

  /// Ringkasan minggu berjalan (Senin-Minggu).
  ({int count, double meters, int seconds}) thisWeek() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var count = 0;
    var meters = 0.0;
    var seconds = 0;
    for (final a in items) {
      if (a.startedAt.isBefore(monday)) continue;
      count++;
      meters += a.distanceMeters;
      seconds += a.movingSeconds;
    }
    return (count: count, meters: meters, seconds: seconds);
  }
}
