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
    final alts = [10.0, 11, 10, 12, 15, 14, 20, 19, 25];
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
}
