import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../models/activity.dart';

/// Workout yang dibaca dari Health Connect (misalnya disinkronkan oleh
/// aplikasi Garmin Connect setelah latihan).
class ExternalWorkout {
  final String uuid;
  final SportType sport;
  final DateTime from;
  final DateTime to;
  final double? distanceMeters;
  final int? calories;
  final String sourceName;

  const ExternalWorkout({
    required this.uuid,
    required this.sport,
    required this.from,
    required this.to,
    this.distanceMeters,
    this.calories,
    required this.sourceName,
  });

  bool get looksLikeGarmin =>
      sourceName.toLowerCase().contains('garmin');

  String get activityId => 'hc-$uuid';
}

class HeartRateSummary {
  final int avg;
  final int max;
  final int samples;
  const HeartRateSummary(this.avg, this.max, this.samples);
}

/// Adapter Health Connect (Android) / HealthKit (iOS).
///
/// Garmin Connect mengirim data satu arah ke Health Connect setelah jam
/// tersinkron: sesi latihan, jarak, kalori, detak jantung, langkah. Rute GPS
/// dari Garmin tidak tersedia lewat jalur ini; untuk rute gunakan impor
/// file .FIT.
class HealthService {
  final Health _health = Health();
  bool _configured = false;

  static const _types = [
    HealthDataType.WORKOUT,
    HealthDataType.HEART_RATE,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
  ];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// null = siap; selain itu pesan untuk pengguna.
  Future<String?> availability() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    await _ensureConfigured();
    final status = await _health.getHealthConnectSdkStatus();
    if (status == HealthConnectSdkStatus.sdkAvailable) return null;
    return 'Health Connect belum terpasang atau perlu diperbarui.';
  }

  Future<void> installHealthConnect() async {
    await _ensureConfigured();
    await _health.installHealthConnect();
  }

  Future<bool> authorize() async {
    await _ensureConfigured();
    final perms = List.filled(_types.length, HealthDataAccess.READ);
    final has = await _health.hasPermissions(_types, permissions: perms);
    if (has == true) return true;
    return _health.requestAuthorization(_types, permissions: perms);
  }

  Future<List<ExternalWorkout>> workouts({int days = 30}) async {
    await _ensureConfigured();
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    final points = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.WORKOUT],
      startTime: start,
      endTime: end,
    );
    final result = <ExternalWorkout>[];
    for (final p in points) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      final sport = _mapType(v.workoutActivityType);
      if (sport == null) continue;
      double? dist = v.totalDistance?.toDouble();
      if (dist == null || dist == 0) {
        dist = await _sumNumeric(HealthDataType.DISTANCE_DELTA, p.dateFrom, p.dateTo);
      }
      result.add(ExternalWorkout(
        uuid: p.uuid,
        sport: sport,
        from: p.dateFrom,
        to: p.dateTo,
        distanceMeters: dist,
        calories: v.totalEnergyBurned,
        sourceName: p.sourceName,
      ));
    }
    result.sort((a, b) => b.from.compareTo(a.from));
    return result;
  }

  Future<double?> _sumNumeric(HealthDataType type, DateTime from, DateTime to) async {
    try {
      final pts = await _health.getHealthDataFromTypes(
          types: [type], startTime: from, endTime: to);
      double sum = 0;
      for (final p in pts) {
        final v = p.value;
        if (v is NumericHealthValue) sum += v.numericValue.toDouble();
      }
      return sum > 0 ? sum : null;
    } catch (_) {
      return null;
    }
  }

  /// Ringkasan detak jantung pada rentang waktu sesi.
  Future<HeartRateSummary?> heartRate(DateTime from, DateTime to) async {
    await _ensureConfigured();
    final pts = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.HEART_RATE], startTime: from, endTime: to);
    final values = <int>[];
    for (final p in pts) {
      final v = p.value;
      if (v is NumericHealthValue) values.add(v.numericValue.round());
    }
    if (values.isEmpty) return null;
    final sum = values.fold<int>(0, (a, b) => a + b);
    final max = values.reduce((a, b) => a > b ? a : b);
    return HeartRateSummary((sum / values.length).round(), max, values.length);
  }

  SportType? _mapType(HealthWorkoutActivityType t) {
    switch (t) {
      case HealthWorkoutActivityType.RUNNING:
      case HealthWorkoutActivityType.RUNNING_TREADMILL:
        return SportType.running;
      case HealthWorkoutActivityType.WALKING:
      case HealthWorkoutActivityType.HIKING:
        return SportType.walking;
      case HealthWorkoutActivityType.BIKING:
      case HealthWorkoutActivityType.BIKING_STATIONARY:
        return SportType.cycling;
      default:
        return null;
    }
  }
}
