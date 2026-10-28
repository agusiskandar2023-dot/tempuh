import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/activity.dart';

/// Penyimpanan lokal (offline-first). Semua sesi ditulis ke SQLite lebih
/// dulu; kolom sync_status disiapkan untuk sinkronisasi Supabase nanti.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'movetrack.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE activities (
            id TEXT PRIMARY KEY,
            sport_type TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            finished_at INTEGER,
            status TEXT NOT NULL,
            elapsed_seconds INTEGER NOT NULL DEFAULT 0 CHECK (elapsed_seconds >= 0),
            moving_seconds INTEGER NOT NULL DEFAULT 0 CHECK (moving_seconds >= 0),
            paused_seconds INTEGER NOT NULL DEFAULT 0 CHECK (paused_seconds >= 0),
            distance_meters REAL NOT NULL DEFAULT 0 CHECK (distance_meters >= 0),
            elevation_gain_meters REAL NOT NULL DEFAULT 0,
            avg_heart_rate INTEGER,
            max_heart_rate INTEGER,
            calories_estimated INTEGER,
            source TEXT NOT NULL,
            source_device TEXT,
            paused_since INTEGER,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE activity_points (
            activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
            sequence_no INTEGER NOT NULL,
            recorded_at INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            altitude REAL,
            accuracy REAL,
            speed REAL,
            heart_rate INTEGER,
            segment_start INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (activity_id, sequence_no)
          )''');
        await db.execute(
            'CREATE INDEX idx_activities_started ON activities(started_at)');
      },
    );
  }

  Future<void> upsertActivity(Activity a) async {
    final d = await db;
    await d.insert('activities', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Menulis sekumpulan titik dalam satu transaksi (checkpoint).
  /// IGNORE pada konflik membuat penulisan ulang aman (idempoten).
  Future<void> insertPoints(String activityId, List<TrackPoint> pts) async {
    if (pts.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final pt in pts) {
      batch.insert('activity_points', pt.toMap(activityId),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<List<TrackPoint>> points(String activityId) async {
    final d = await db;
    final rows = await d.query('activity_points',
        where: 'activity_id = ?',
        whereArgs: [activityId],
        orderBy: 'sequence_no');
    return rows.map(TrackPoint.fromMap).toList();
  }

  Future<List<Activity>> finishedActivities() async {
    final d = await db;
    final rows = await d.query('activities',
        where: 'status = ?',
        whereArgs: [ActivityStatus.finished.name],
        orderBy: 'started_at DESC');
    return rows.map(Activity.fromMap).toList();
  }

  /// Sesi yang belum selesai (misalnya aplikasi dimatikan sistem).
  Future<Activity?> unfinishedActivity() async {
    final d = await db;
    final rows = await d.query('activities',
        where: 'status != ?',
        whereArgs: [ActivityStatus.finished.name],
        orderBy: 'started_at DESC',
        limit: 1);
    return rows.isEmpty ? null : Activity.fromMap(rows.first);
  }

  Future<Activity?> activity(String id) async {
    final d = await db;
    final rows =
        await d.query('activities', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Activity.fromMap(rows.first);
  }

  Future<bool> exists(String id) async {
    final d = await db;
    final rows = await d.query('activities',
        columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> deleteActivity(String id) async {
    final d = await db;
    await d.delete('activities', where: 'id = ?', whereArgs: [id]);
  }
}
