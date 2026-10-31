import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/domain/stats.dart';
import 'package:movetrack_ai/models/activity.dart';

Activity a(String id, DateTime start,
        {SportType sport = SportType.running,
        double dist = 5000,
        int secs = 1800,
        double? max}) =>
    Activity(
      id: id,
      sport: sport,
      startedAt: start,
      status: ActivityStatus.finished,
      distanceMeters: dist,
      movingSeconds: secs,
      elapsedSeconds: secs,
      maxSpeedMps: max,
    );

void main() {
  final now = DateTime(2026, 11, 1, 9); // Minggu

  test('rentang periode minggu, bulan, tahun', () {
    final w = periodRange(StatPeriod.week, now);
    expect(w.start, DateTime(2026, 10, 26));
    expect(w.end, DateTime(2026, 11, 2));
    expect(w.prevStart, DateTime(2026, 10, 19));
    final m = periodRange(StatPeriod.month, DateTime(2026, 1, 15));
    expect(m.prevStart, DateTime(2025, 12));
    expect(periodRange(StatPeriod.year, now).start, DateTime(2026));
  });

  test('ringkasan periode dan hari beruntun', () {
    final items = [
      a('1', DateTime(2026, 11, 1, 6)),
      a('2', DateTime(2026, 10, 31, 6)),
      a('3', DateTime(2026, 10, 31, 18)),
      a('4', DateTime(2026, 10, 30, 6)),
      a('5', DateTime(2026, 10, 25, 6)),
    ];
    final r = periodRange(StatPeriod.week, now);
    final s = summarize(items, r.start, r.end);
    expect(s.count, 4);
    expect(s.meters, 20000);
    expect(s.activeDays, 3);
    expect(dayStreak(items, now), 3);
    // Hari ini belum bergerak: streak dihitung sampai kemarin.
    expect(dayStreak(items.skip(1).toList(), now), 2);
    expect(dayStreak(items, DateTime(2026, 11, 5)), 0);
  });

  test('rekor pribadi: terjauh, terlama, tercepat, kecepatan maks, rekor baru', () {
    final items = [
      a('lama', DateTime(2026, 9, 1), dist: 10000, secs: 3600, max: 4.0),
      a('cepat', DateTime(2026, 10, 30), dist: 5000, secs: 1500, max: 4.5),
      a('pendek', DateTime(2026, 10, 31), dist: 500, secs: 100), // < 1 km
      a('sepeda', DateTime(2026, 10, 31), sport: SportType.cycling, dist: 30000),
    ];
    final rec = {
      for (final r in personalRecords(items, SportType.running, now: now)) r.kind: r
    };
    expect(rec[RecordKind.farthest]!.activity.id, 'lama');
    expect(rec[RecordKind.farthest]!.isNew, isFalse);
    expect(rec[RecordKind.longest]!.value, 3600);
    expect(rec[RecordKind.fastest]!.activity.id, 'cepat');
    expect(rec[RecordKind.fastest]!.value, closeTo(300, 0.01)); // 5:00 /km
    expect(rec[RecordKind.fastest]!.isNew, isTrue);
    expect(rec[RecordKind.maxSpeed]!.value, 4.5);
    expect(rec[RecordKind.maxSpeed]!.isNew, isTrue);
    // Aktivitas pertama sebuah olahraga bukan "rekor baru".
    final bike = personalRecords(items, SportType.cycling, now: now);
    expect(bike.every((r) => !r.isNew), isTrue);
    expect(mainSport(items), SportType.running);
  });
}
