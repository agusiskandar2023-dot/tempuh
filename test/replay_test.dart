import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/domain/replay.dart';
import 'package:movetrack_ai/models/activity.dart';
import 'package:movetrack_ai/services/replay_map.dart';

TrackPoint pt(int seq, int sec, double northMeters, {bool seg = false}) => TrackPoint(
      sequenceNo: seq,
      recordedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
      latitude: -6.2 + northMeters / 111194.93,
      longitude: 106.8,
      segmentStart: seg,
    );

void main() {
  final act = Activity(
    id: 'a',
    sport: SportType.running,
    startedAt: DateTime(2026, 1, 1, 6),
    status: ActivityStatus.finished,
  );

  test('data replay: tanda km, posisi waktu, jeda pause tidak dihitung', () {
    // 2,5 km dengan 3 m/s, lalu pause 10 menit di tengah.
    final pts = <TrackPoint>[];
    for (var i = 0; i <= 400; i++) {
      pts.add(pt(i, i, i * 3.0));
    }
    for (var i = 0; i <= 434; i++) {
      pts.add(pt(401 + i, 1000 + i, 1200 + i * 3.0, seg: i == 0));
    }
    final d = ReplayData.build(act, pts);
    expect(d.totalMeters, closeTo(2502, 2));
    expect(d.totalSeconds, closeTo(834, 0.5)); // 400 + 434, tanpa 600 dtk pause
    expect(d.kms.map((k) => k.km), [1, 2]);
    expect(d.kms.first.paceSecondsPerKm, closeTo(333.3, 1));
    expect(d.metersAt(0.5), closeTo(1251, 5));
    expect(d.metersAt(1), closeTo(d.totalMeters, 0.01));
    expect(d.maxSpeedMps, closeTo(3, 0.05));
    expect(d.maxSpeedFraction, isNotNull);
  });

  test('titik dikurangi untuk animasi tanpa mengubah ujung rute', () {
    final pts = [for (var i = 0; i <= 3000; i++) pt(i, i, i * 3.0)];
    final d = ReplayData.build(act, pts, maxPoints: 500);
    expect(d.length, lessThanOrEqualTo(502));
    expect(d.totalMeters, closeTo(9000, 1));
    expect(ReplayData.canBuild(pts.take(2).toList()), isFalse);
  });

  test('sembunyikan awal & akhir memotong 200 m di tiap ujung', () {
    final pts = [for (var i = 0; i <= 1000; i++) pt(i, i, i * 3.0)];
    final d = ReplayData.build(act, pts, hideEnds: true);
    expect(d.totalMeters, closeTo(2600, 6));
  });

  test('jadwal adegan 15 dan 30 detik', () {
    const a = ReplayTimeline(15, hasPhoto: true);
    expect(a.introEnd, 1.5);
    expect(a.routeFraction(1.5), 0);
    expect(a.routeFraction(a.routeEnd), 1);
    expect(a.finalStart, greaterThan(a.routeEnd));
    const b = ReplayTimeline(30);
    expect(b.finalStart, b.routeEnd);
    expect(b.timeAtFraction(0.5), closeTo((b.introEnd + b.routeEnd) / 2, 1e-9));
  });

  test('peta: rute memenuhi kotak layar, ubin menutup seluruh frame', () {
    final pts = [for (var i = 0; i <= 600; i++) pt(i, i, i * 3.0)];
    final d = ReplayData.build(act, pts);
    final v = ReplayMapView.fit(d);
    final first = v.toLogical(d.lat.first, d.lon.first);
    final last = v.toLogical(d.lat.last, d.lon.last);
    expect((first.dy - last.dy).abs(), closeTo(replayRouteBox.height, 1));
    expect(replayRouteBox.inflate(1).contains(first), isTrue);
    expect(replayRouteBox.inflate(1).contains(last), isTrue);
    final tiles = v.tiles();
    final cover = tiles.map((t) => t.rect).reduce((a, b) => a.expandToInclude(b));
    expect(cover.left, lessThanOrEqualTo(0));
    expect(cover.top, lessThanOrEqualTo(0));
    expect(cover.right, greaterThanOrEqualTo(replayFrame.width));
    expect(cover.bottom, greaterThanOrEqualTo(replayFrame.height));
    expect(tiles.length, lessThan(60));
  });
}
