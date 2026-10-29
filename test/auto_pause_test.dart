import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/domain/auto_pause.dart';
import 'package:movetrack_ai/models/activity.dart';

void main() {
  final t0 = DateTime(2026, 10, 30, 6);
  const lat = -6.2, lon = 106.8;
  const metersPerDegLat = 111194.93;

  test('berhenti terdeteksi setelah diam cukup lama', () {
    final d = AutoPauseDetector.forSport(SportType.running);
    d.reset(t0);
    d.moved(t0, lat, lon);
    expect(d.shouldPause(t0.add(const Duration(seconds: 5))), isFalse);
    expect(d.shouldPause(t0.add(const Duration(seconds: 8))), isTrue);
    d.markPaused();
    expect(d.shouldPause(t0.add(const Duration(seconds: 20))), isFalse);
  });

  test('lanjut otomatis hanya bila benar-benar bergerak', () {
    final d = AutoPauseDetector.forSport(SportType.walking);
    d.reset(t0);
    d.moved(t0, lat, lon);
    d.markPaused();
    // drift GPS 3 m: tetap jeda
    expect(d.shouldResume(lat + 3 / metersPerDegLat, lon, 5), isFalse);
    // pindah 12 m tapi akurasi buruk: tetap jeda
    expect(d.shouldResume(lat + 12 / metersPerDegLat, lon, 60), isFalse);
    // pindah 12 m dengan akurasi baik: lanjut
    expect(d.shouldResume(lat + 12 / metersPerDegLat, lon, 6), isTrue);
    d.markResumed(t0.add(const Duration(seconds: 30)));
    expect(d.paused, isFalse);
  });

  test('sepeda butuh perpindahan lebih jauh untuk lanjut', () {
    final d = AutoPauseDetector.forSport(SportType.cycling);
    d.reset(t0);
    d.moved(t0, lat, lon);
    d.markPaused();
    expect(d.shouldResume(lat + 12 / metersPerDegLat, lon, 6), isFalse);
    expect(d.shouldResume(lat + 25 / metersPerDegLat, lon, 6), isTrue);
  });
}
