import '../models/activity.dart';

/// Periode ringkasan di Beranda.
enum StatPeriod { week, month, year }

extension StatPeriodX on StatPeriod {
  String get label => switch (this) {
        StatPeriod.week => 'Minggu',
        StatPeriod.month => 'Bulan',
        StatPeriod.year => 'Tahun',
      };
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Awal (inklusif) dan akhir (eksklusif) periode yang memuat [now],
/// serta periode sebelumnya. Minggu dimulai Senin.
({DateTime start, DateTime end, DateTime prevStart}) periodRange(
    StatPeriod p, DateTime now) {
  switch (p) {
    case StatPeriod.week:
      final start = _day(now).subtract(Duration(days: now.weekday - 1));
      return (
        start: start,
        end: DateTime(start.year, start.month, start.day + 7),
        prevStart: DateTime(start.year, start.month, start.day - 7),
      );
    case StatPeriod.month:
      return (
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
        prevStart: DateTime(now.year, now.month - 1),
      );
    case StatPeriod.year:
      return (
        start: DateTime(now.year),
        end: DateTime(now.year + 1),
        prevStart: DateTime(now.year - 1),
      );
  }
}

class PeriodSummary {
  final int count;
  final double meters;
  final int movingSeconds;
  final int calories;
  final double elevation;
  final int activeDays;
  const PeriodSummary(this.count, this.meters, this.movingSeconds, this.calories,
      this.elevation, this.activeDays);
}

PeriodSummary summarize(List<Activity> items, DateTime start, DateTime end) {
  var count = 0, secs = 0, kcal = 0;
  var meters = 0.0, elev = 0.0;
  final days = <DateTime>{};
  for (final a in items) {
    if (a.startedAt.isBefore(start) || !a.startedAt.isBefore(end)) continue;
    count++;
    meters += a.distanceMeters;
    secs += a.movingSeconds;
    kcal += a.caloriesEstimated ?? 0;
    elev += a.elevationGainMeters;
    days.add(_day(a.startedAt));
  }
  return PeriodSummary(count, meters, secs, kcal, elev, days.length);
}

/// Jumlah hari berturut-turut ada aktivitas, berakhir hari ini (atau
/// kemarin, bila hari ini belum bergerak).
int dayStreak(List<Activity> items, DateTime now) {
  final days = {for (final a in items) _day(a.startedAt)};
  var d = _day(now);
  if (!days.contains(d)) d = DateTime(d.year, d.month, d.day - 1);
  var n = 0;
  while (days.contains(d)) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// Jenis rekor pribadi.
enum RecordKind { farthest, longest, fastest, maxSpeed }

extension RecordKindX on RecordKind {
  String get label => switch (this) {
        RecordKind.farthest => 'Terjauh',
        RecordKind.longest => 'Terlama',
        RecordKind.fastest => 'Tercepat',
        RecordKind.maxSpeed => 'Kecepatan maks',
      };
}

class PersonalRecord {
  final RecordKind kind;
  final SportType sport;
  final Activity activity;

  /// Nilai mentah: meter, detik, detik/km (jalan/lari) atau m/s.
  final double value;

  /// true bila rekor dibuat dalam 7 hari terakhir dan memecahkan rekor lama.
  final bool isNew;

  const PersonalRecord(this.kind, this.sport, this.activity, this.value, this.isNew);
}

/// Jarak minimum agar pace/kecepatan rata-rata dihitung sebagai rekor
/// "Tercepat" (aktivitas pendek sekali tidak adil dibandingkan).
const _minFastestMeters = 1000.0;

/// Rekor pribadi untuk satu jenis olahraga: terjauh, terlama, tercepat
/// (pace rata-rata, atau kecepatan rata-rata untuk sepeda), kecepatan maks.
List<PersonalRecord> personalRecords(List<Activity> items, SportType sport,
    {DateTime? now}) {
  final list = items.where((a) => a.sport == sport).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  if (list.isEmpty) return const [];
  final recent = (now ?? DateTime.now()).subtract(const Duration(days: 7));

  // value(a): makin besar makin baik; null = tidak dihitung.
  PersonalRecord? best(RecordKind kind, double? Function(Activity) value,
      double Function(double) raw) {
    Activity? top;
    double? topV;
    var beatOlder = false; // rekor teratas mengalahkan rekor sebelumnya
    for (final a in list) {
      final v = value(a);
      if (v == null || v <= 0) continue;
      if (topV == null || v > topV) {
        beatOlder = topV != null;
        topV = v;
        top = a;
      }
    }
    if (top == null) return null;
    final isNew = beatOlder && !top.startedAt.isBefore(recent);
    return PersonalRecord(kind, sport, top, raw(topV!), isNew);
  }

  return [
    best(RecordKind.farthest, (a) => a.distanceMeters, (v) => v),
    best(RecordKind.longest, (a) => a.movingSeconds.toDouble(), (v) => v),
    sport.showsSpeed
        ? best(
            RecordKind.fastest,
            (a) => a.distanceMeters >= _minFastestMeters && a.movingSeconds > 0
                ? a.distanceMeters / a.movingSeconds
                : null,
            (v) => v)
        : best(
            RecordKind.fastest,
            (a) => a.distanceMeters >= _minFastestMeters && a.movingSeconds > 0
                ? a.distanceMeters / a.movingSeconds
                : null,
            (v) => 1000 / v), // simpan sebagai detik/km
    best(RecordKind.maxSpeed, (a) => a.maxSpeedMps, (v) => v),
  ].whereType<PersonalRecord>().toList();
}

/// Olahraga yang paling sering dilakukan (untuk rekor di Beranda).
SportType? mainSport(List<Activity> items) {
  final n = <SportType, int>{};
  for (final a in items) {
    n[a.sport] = (n[a.sport] ?? 0) + 1;
  }
  if (n.isEmpty) return null;
  return (n.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}
