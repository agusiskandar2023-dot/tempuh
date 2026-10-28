import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/domain/metrics.dart';
import 'package:movetrack_ai/models/activity.dart';
import 'package:movetrack_ai/services/fit_parser.dart';

void main() {
  // Fixture sintetis berformat Garmin: 2 segmen x 61 titik (3 m/detik),
  // pause 30 detik di tengah, 1 record tanpa posisi dengan compressed
  // timestamp, field developer yang harus dilewati, dan pesan session.
  final bytes = File('test/fixtures/sample_run.fit').readAsBytesSync();

  test('membaca ringkasan session', () {
    final fit = FitParser.parse(bytes);
    expect(fit.sport, SportType.running);
    expect(fit.isGarmin, isTrue);
    expect(fit.totalDistanceMeters, closeTo(360, 0.01));
    expect(fit.totalTimerSeconds, closeTo(120, 0.01));
    expect(fit.totalElapsedSeconds, closeTo(150, 0.01));
    expect(fit.totalCalories, 210);
    expect(fit.avgHeartRate, 149);
    expect(fit.maxHeartRate, 159);
    expect(fit.totalAscentMeters, 12);
    expect(fit.startTime!.toUtc(), DateTime.utc(2025, 10, 28, 8));
  });

  test('membaca titik rute, HR, dan segmen setelah pause', () {
    final fit = FitParser.parse(bytes);
    expect(fit.points.length, 122);
    expect(fit.heartRates.length, 123);
    expect(fit.points.first.latitude, closeTo(-6.2, 1e-6));
    expect(fit.points.first.longitude, closeTo(106.8, 1e-6));
    expect(fit.points.first.altitude, closeTo(10.0, 0.01));
    expect(fit.points.first.heartRate, 140);
    final segStarts = [
      for (var i = 0; i < fit.points.length; i++)
        if (fit.points[i].segmentStart) i
    ];
    expect(segStarts, [61]);
    final calc = MetricsCalculator(SportType.running)..restore(fit.points);
    expect(calc.distanceMeters, closeTo(360, 2));
  });

  test('menolak file bukan FIT', () {
    expect(() => FitParser.parse(bytes.sublist(0, 8)),
        throwsA(isA<FitFormatException>()));
  });
}
