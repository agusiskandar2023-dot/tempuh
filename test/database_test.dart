import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/data/database.dart';
import 'package:movetrack_ai/models/activity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tes "data lama tidak boleh hilang": penyimpanan ulang, update aplikasi
/// (migrasi skema), hapus, dan backup/pulihkan.
void main() {
  late Directory tmp;
  var n = 0;

  setUpAll(() {
    sqfliteFfiInit();
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tempuh_db_');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  AppDatabase newDb([String? path]) =>
      AppDatabase.test(databaseFactoryFfi, path ?? '${tmp.path}/db${n++}.sqlite');

  Activity act(String id, {double dist = 1000}) => Activity(
        id: id,
        sport: SportType.running,
        startedAt: DateTime(2026, 10, 28, 6),
        finishedAt: DateTime(2026, 10, 28, 6, 30),
        status: ActivityStatus.finished,
        elapsedSeconds: 1800,
        movingSeconds: 1700,
        pausedSeconds: 100,
        distanceMeters: dist,
      );

  List<TrackPoint> pts(int count) => [
        for (var i = 0; i < count; i++)
          TrackPoint(
            sequenceNo: i,
            recordedAt: DateTime(2026, 10, 28, 6).add(Duration(seconds: i)),
            latitude: -6.2 + i * 0.0001,
            longitude: 106.8,
          )
      ];

  test('menyimpan ulang aktivitas (checkpoint) tidak menghapus rute', () async {
    final db = newDb();
    await db.upsertActivity(act('a1'));
    await db.insertPoints('a1', pts(50));
    for (var i = 0; i < 5; i++) {
      await db.upsertActivity(act('a1', dist: 1000.0 + i));
    }
    expect((await db.points('a1')).length, 50);
    expect((await db.activity('a1'))!.distanceMeters, 1004);
    await db.close();
  });

  test('update aplikasi (migrasi v1 -> v2) mempertahankan data lama', () async {
    final path = '${tmp.path}/old.sqlite';
    // Database versi 1 persis seperti di aplikasi v0.1 - v0.2.
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE activities (
              id TEXT PRIMARY KEY, sport_type TEXT NOT NULL, started_at INTEGER NOT NULL,
              finished_at INTEGER, status TEXT NOT NULL,
              elapsed_seconds INTEGER NOT NULL DEFAULT 0, moving_seconds INTEGER NOT NULL DEFAULT 0,
              paused_seconds INTEGER NOT NULL DEFAULT 0, distance_meters REAL NOT NULL DEFAULT 0,
              elevation_gain_meters REAL NOT NULL DEFAULT 0, avg_heart_rate INTEGER,
              max_heart_rate INTEGER, calories_estimated INTEGER, source TEXT NOT NULL,
              source_device TEXT, paused_since INTEGER,
              sync_status TEXT NOT NULL DEFAULT 'pending', updated_at INTEGER NOT NULL)''');
            await d.execute('''CREATE TABLE activity_points (
              activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
              sequence_no INTEGER NOT NULL, recorded_at INTEGER NOT NULL,
              latitude REAL NOT NULL, longitude REAL NOT NULL, altitude REAL, accuracy REAL,
              speed REAL, heart_rate INTEGER, segment_start INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (activity_id, sequence_no))''');
          },
        ));
    await old.insert('activities', act('lama').toMap());
    for (final p in pts(30)) {
      await old.insert('activity_points', p.toMap('lama'));
    }
    await old.close();

    final db = newDb(path);
    final list = await db.finishedActivities();
    expect(list.map((a) => a.id), ['lama']);
    expect((await db.points('lama')).length, 30);
    // Kolom baru tersedia dan bisa dipakai.
    await db.markSynced('lama', 'cloud-1');
    expect(await db.cloudIdOf('lama'), 'cloud-1');
    await db.close();
  });

  test('perubahan lokal setelah sinkron tidak menghapus cloud_id', () async {
    final db = newDb();
    await db.upsertActivity(act('a1'));
    await db.markSynced('a1', 'c1');
    expect(await db.activitiesToPush(), isEmpty);
    await db.upsertActivity(act('a1', dist: 2000)); // misal ambil HR Garmin
    expect(await db.cloudIdOf('a1'), 'c1');
    expect((await db.activitiesToPush()).length, 1);
    await db.close();
  });

  test('hapus aktivitas tersinkron dicatat untuk dihapus di server', () async {
    final db = newDb();
    await db.upsertActivity(act('a1'));
    await db.upsertActivity(act('a2'));
    await db.markSynced('a1', 'c1');
    await db.deleteActivity('a1');
    await db.deleteActivity('a2');
    expect(await db.pendingRemoteDeletes(), ['c1']);
    await db.close();
  });

  test('backup lalu pulihkan: semua kembali, pulihkan ulang tidak menggandakan', () async {
    final src = newDb();
    await src.upsertActivity(act('a1'));
    await src.insertPoints('a1', pts(20));
    await src.upsertActivity(act('a2', dist: 5000));
    await src.insertPoints('a2', pts(7));
    final json = await src.exportJson();
    await src.close();

    final dst = newDb();
    await dst.upsertActivity(act('a2', dist: 9999)); // data HP yang sudah ada
    expect(await dst.importJson(json), 1);
    expect(await dst.importJson(json), 0);
    expect((await dst.points('a1')).length, 20);
    expect((await dst.activity('a2'))!.distanceMeters, 9999); // tidak ditimpa
    expect(() => dst.importJson('{"foo":1}'), throwsFormatException);
    await dst.close();
  });
}
