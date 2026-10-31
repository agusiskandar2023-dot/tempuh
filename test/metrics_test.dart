import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/domain/metrics.dart';
import 'package:movetrack_ai/models/activity.dart';

TrackPoint pt(int seq, int sec, double northMeters,
        {double acc = 5, bool seg = false, double? alt}) =>
    TrackPoint(
      sequenceNo: seq,
      recordedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
      latitude: -6.2 + northMeters / 111194.93,
      longitude: 106.8,
      accuracy: acc,
      altitude: alt,
      segmentStart: seg,
    );

void main() {
  test('haversine 1 derajat lintang ~ 111,2 km', () {
    expect(haversineMeters(0, 0, 1, 0), closeTo(111195, 1));
  });

  test('jarak bertambah dari titik yang valid', () {
    final c = MetricsCalculator(SportType.running);
    for (var i = 0; i <= 100; i++) {
      expect(c.add(pt(i, i, i * 4.0)), isTrue);
    }
    expect(c.distanceMeters, closeTo(400, 0.5));
  });

  test('titik akurasi buruk, lonjakan, dan drift ditolak', () {
    final c = MetricsCalculator(SportType.running);
    expect(c.add(pt(0, 0, 0)), isTrue);
    expect(c.add(pt(1, 1, 3, acc: 60)), isFalse);
    expect(c.lastReject, RejectReason.poorAccuracy);
    expect(c.add(pt(1, 2, 200)), isFalse); // 100 m/s
    expect(c.lastReject, RejectReason.spike);
    expect(c.add(pt(1, 3, 1)), isFalse); // diam, drift 1 m
    expect(c.lastReject, RejectReason.jitter);
    expect(c.distanceMeters, 0);
  });

  test('jarak saat pause tidak dihitung (awal segmen baru)', () {
    final c = MetricsCalculator(SportType.walking);
    c.add(pt(0, 0, 0));
    c.add(pt(1, 10, 10));
    // pindah 500 m selama pause, lalu lanjut
    expect(c.add(pt(2, 400, 510, seg: true)), isTrue);
    c.add(pt(3, 410, 520));
    expect(c.distanceMeters, closeTo(20, 0.1));
  });

  test('split 1 km memakai waktu bergerak', () {
    final pts = [for (var i = 0; i <= 500; i++) pt(i, i * 1, i * 5.0)];
    final splits = computeSplits(pts);
    expect(splits.length, 3); // 1000, 1000, 500
    expect(splits[0].durationSeconds, 200);
    expect(splits[0].paceSecondsPerKm, closeTo(200, 1));
    expect(splits[2].distanceMeters, closeTo(500, 1));
  });

  test('elevasi memakai histeresis 3 m', () {
    final c = MetricsCalculator(SportType.cycling);
    final alts = <double>[10, 11, 10, 12, 15, 14, 20, 19, 25];
    for (var i = 0; i < alts.length; i++) {
      c.add(pt(i, i * 2, i * 10.0, alt: alts[i]));
    }
    expect(c.elevationGainMeters, closeTo(15, 0.01));
  });

  test('format', () {
    expect(formatDuration(3725), '1:02:05');
    expect(formatDuration(65), '01:05');
    expect(formatPace(330), '5:30');
    expect(formatPace(null), '--:--');
  });

  test('kecepatan maks dihaluskan: lonjakan 2 detik tidak dihitung', () {
    // Lari 3 m/s selama 60 detik, dengan 2 detik 6 m/s di tengah.
    final pts = <TrackPoint>[];
    var north = 0.0;
    for (var i = 0; i <= 60; i++) {
      pts.add(pt(i, i, north));
      north += (i == 30 || i == 31) ? 6 : 3;
    }
    final v = computeMaxSpeedMps(pts, SportType.running)!;
    // Jendela 10 detik: maks (8*3 + 2*6)/10 = 3,6 m/s, bukan 6 m/s.
    expect(v, closeTo(3.6, 0.05));
    expect(computeMaxSpeedMps(pts.take(5).toList(), SportType.running), isNull);
  });

  test('kecepatan maks tidak melewati jeda pause', () {
    final pts = [
      for (var i = 0; i <= 20; i++) pt(i, i, i * 2.0),
      // Resume 5 menit kemudian, 300 m lebih jauh: tidak boleh jadi "cepat".
      for (var i = 0; i <= 20; i++) pt(21 + i, 320 + i, 340 + i * 2.0, seg: i == 0),
    ];
    expect(computeMaxSpeedMps(pts, SportType.walking), closeTo(2.0, 0.01));
  });

  test('kalkulator live mencatat kecepatan maks', () {
    final c = MetricsCalculator(SportType.cycling);
    for (var i = 0; i <= 30; i++) {
      c.add(pt(i, i, i < 15 ? i * 6.0 : 84 + (i - 14) * 8.0));
    }
    expect(c.maxSpeedMps, greaterThan(7.5));
    expect(c.maxSpeedMps, lessThanOrEqualTo(8.01));
  });
}
