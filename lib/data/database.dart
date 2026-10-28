import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/activity.dart';

/// Penyimpanan lokal (offline-first). Semua sesi ditulis ke SQLite lebih
/// dulu, lalu disinkronkan ke Neon bila pengguna login.
///
/// ATURAN MIGRASI: versi baru hanya boleh MENAMBAH (tabel/kolom/indeks),
/// tidak pernah menghapus atau membuat ulang tabel, agar data lama aman.
class AppDatabase {
  AppDatabase._() : _factory = null, _path = null;
  static final AppDatabase instance = AppDatabase._();

  /// Untuk tes: database di [path] memakai [factory] (misalnya sqflite ffi).
  AppDatabase.test(DatabaseFactory factory, String path)
      : _factory = factory,
        _path = path;

  final DatabaseFactory? _factory;
  final String? _path;
  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path = _path ?? p.join(await factory.getDatabasesPath(), 'movetrack.db');
    return factory.openDatabase(path, options: OpenDatabaseOptions(
      version: _schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, newVersion) => _migrate(db, oldVersion),
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
        await _migrate(db, 1);
      },
    ));
  }

  static const _schemaVersion = 2;

  /// Migrasi bertahap dari [from] ke versi terbaru. Hanya menambah.
  static Future<void> _migrate(Database db, int from) async {
    if (from < 2) {
      // v2: sinkronisasi Neon.
      await db.execute('ALTER TABLE activities ADD COLUMN cloud_id TEXT');
      await db.execute('ALTER TABLE activities ADD COLUMN synced_at INTEGER');
      await db.execute(
          'CREATE TABLE IF NOT EXISTS deleted_remote (cloud_id TEXT PRIMARY KEY, deleted_at INTEGER NOT NULL)');
    }
  }

  // ---------------- Sinkronisasi ----------------

  /// Aktivitas selesai yang belum terkirim / berubah sejak sinkron terakhir.
  Future<List<Map<String, Object?>>> activitiesToPush() async {
    final d = await db;
    return d.query('activities',
        where: 'status = ? AND sync_status != ?',
        whereArgs: [ActivityStatus.finished.name, 'synced'],
        orderBy: 'started_at');
  }

  Future<void> markSynced(String id, String cloudId) async {
    final d = await db;
    await d.update(
        'activities',
        {
          'cloud_id': cloudId,
          'sync_status': 'synced',
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<Set<String>> knownCloudIds() async {
    final d = await db;
    final rows = await d.query('activities',
        columns: ['id', 'cloud_id'], where: 'status = ?', whereArgs: [ActivityStatus.finished.name]);
    return {
      for (final r in rows) ...[
        if (r['cloud_id'] != null) r['cloud_id'] as String,
        r['id'] as String,
      ]
    };
  }

  Future<String?> cloudIdOf(String id) async {
    final d = await db;
    final rows = await d.query('activities',
        columns: ['cloud_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first['cloud_id'] as String?;
  }

  /// Aktivitas dari Neon (misalnya upload .FIT lewat web) disimpan lokal
  /// sebagai sudah tersinkron.
  Future<void> insertFromCloud(Activity a, List<TrackPoint> pts) async {
    final d = await db;
    await d.transaction((txn) async {
      final m = a.toMap()
        ..['cloud_id'] = a.id
        ..['sync_status'] = 'synced'
        ..['synced_at'] = DateTime.now().millisecondsSinceEpoch;
      final updated =
          await txn.update('activities', m, where: 'id = ?', whereArgs: [a.id]);
      if (updated == 0) await txn.insert('activities', m);
      final batch = txn.batch();
      for (final pt in pts) {
        batch.insert('activity_points', pt.toMap(a.id),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> addDeletedRemote(String cloudId) async {
    final d = await db;
    await d.insert('deleted_remote',
        {'cloud_id': cloudId, 'deleted_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<String>> pendingRemoteDeletes() async {
    final d = await db;
    final rows = await d.query('deleted_remote', columns: ['cloud_id']);
    return [for (final r in rows) r['cloud_id'] as String];
  }

  Future<void> clearRemoteDelete(String cloudId) async {
    final d = await db;
    await d.delete('deleted_remote', where: 'cloud_id = ?', whereArgs: [cloudId]);
  }

  /// Simpan atau perbarui aktivitas.
  ///
  /// Sengaja TIDAK memakai INSERT OR REPLACE: REPLACE menghapus baris lama
  /// lebih dulu, dan karena activity_points memakai ON DELETE CASCADE,
  /// seluruh titik rute ikut terhapus setiap checkpoint (bug v0.2.3).
  Future<void> upsertActivity(Activity a) async {
    final d = await db;
    final m = a.toMap();
    await d.transaction((txn) async {
      final updated =
          await txn.update('activities', m, where: 'id = ?', whereArgs: [a.id]);
      if (updated == 0) await txn.insert('activities', m);
    });
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

  /// Menghapus aktivitas lokal. Bila sudah pernah tersinkron, catat agar
  /// salinan di Neon ikut dihapus pada sinkron berikutnya (kalau tidak,
  /// aktivitas akan turun lagi dari server).
  Future<void> deleteActivity(String id) async {
    final d = await db;
    final cloudId = await cloudIdOf(id);
    if (cloudId != null) await addDeletedRemote(cloudId);
    await d.delete('activities', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Backup ----------------

  /// Semua aktivitas selesai + rutenya sebagai JSON (file backup).
  Future<String> exportJson() async {
    final d = await db;
    final acts = await d.query('activities',
        where: 'status = ?', whereArgs: [ActivityStatus.finished.name], orderBy: 'started_at');
    final out = <Map<String, Object?>>[];
    for (final a in acts) {
      final pts = await d.query('activity_points',
          where: 'activity_id = ?', whereArgs: [a['id']], orderBy: 'sequence_no');
      out.add({...a, 'points': pts});
    }
    return jsonEncode({
      'app': 'tempuh',
      'format': 1,
      'schema': _schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'activities': out,
    });
  }

  /// Memulihkan backup. Hanya MENAMBAH aktivitas yang belum ada; data yang
  /// sudah ada di HP tidak ditimpa. Mengembalikan jumlah aktivitas baru.
  Future<int> importJson(String json) async {
    final data = jsonDecode(json);
    if (data is! Map || data['app'] != 'tempuh' || data['activities'] is! List) {
      throw const FormatException('Bukan file backup Tempuh.');
    }
    final d = await db;
    final cols = (await d.rawQuery('PRAGMA table_info(activities)'))
        .map((r) => r['name'] as String)
        .toSet();
    var added = 0;
    await d.transaction((txn) async {
      for (final raw in data['activities'] as List) {
        final a = Map<String, Object?>.from(raw as Map);
        final pts = (a.remove('points') as List?) ?? const [];
        final exists = await txn.query('activities',
            columns: ['id'], where: 'id = ?', whereArgs: [a['id']], limit: 1);
        if (exists.isNotEmpty) continue;
        a.removeWhere((k, _) => !cols.contains(k));
        if (a['cloud_id'] == null) a['sync_status'] = 'pending';
        await txn.insert('activities', a);
        final batch = txn.batch();
        for (final pt in pts) {
          batch.insert('activity_points', Map<String, Object?>.from(pt as Map),
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
        added++;
      }
    });
    return added;
  }
}
