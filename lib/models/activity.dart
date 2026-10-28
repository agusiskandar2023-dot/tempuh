import 'package:flutter/material.dart';

enum SportType { running, jogging, walking, cycling }

extension SportTypeX on SportType {
  String get label => switch (this) {
        SportType.running => 'Lari',
        SportType.jogging => 'Jogging',
        SportType.walking => 'Jalan Kaki',
        SportType.cycling => 'Sepeda',
      };

  IconData get icon => switch (this) {
        SportType.running => Icons.directions_run,
        SportType.jogging => Icons.directions_run_outlined,
        SportType.walking => Icons.directions_walk,
        SportType.cycling => Icons.directions_bike,
      };

  /// Kecepatan maksimum yang masih masuk akal (m/s). Titik GPS yang
  /// menyiratkan kecepatan di atas ini dianggap lonjakan dan dibuang.
  double get maxPlausibleSpeed => switch (this) {
        SportType.walking => 4.0,
        SportType.jogging => 7.0,
        SportType.running => 9.0,
        SportType.cycling => 25.0,
      };

  /// Sepeda menampilkan kecepatan (km/jam), lainnya pace (menit/km).
  bool get showsSpeed => this == SportType.cycling;

  static SportType fromName(String name) =>
      SportType.values.firstWhere((s) => s.name == name,
          orElse: () => SportType.running);
}

enum ActivityStatus { recording, paused, finished }

/// Sumber data aktivitas.
class ActivitySource {
  static const phone = 'phone_gps';
  static const healthConnect = 'health_connect';
  static const fitFile = 'fit_file';
}

class TrackPoint {
  final int sequenceNo;
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final int? heartRate;

  /// true = titik pertama setelah resume; jarak dari titik sebelumnya
  /// (sebelum pause) tidak dihitung.
  final bool segmentStart;

  const TrackPoint({
    required this.sequenceNo,
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.heartRate,
    this.segmentStart = false,
  });

  Map<String, Object?> toMap(String activityId) => {
        'activity_id': activityId,
        'sequence_no': sequenceNo,
        'recorded_at': recordedAt.millisecondsSinceEpoch,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'accuracy': accuracy,
        'speed': speed,
        'heart_rate': heartRate,
        'segment_start': segmentStart ? 1 : 0,
      };

  factory TrackPoint.fromMap(Map<String, Object?> m) => TrackPoint(
        sequenceNo: m['sequence_no'] as int,
        recordedAt:
            DateTime.fromMillisecondsSinceEpoch(m['recorded_at'] as int),
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        altitude: (m['altitude'] as num?)?.toDouble(),
        accuracy: (m['accuracy'] as num?)?.toDouble(),
        speed: (m['speed'] as num?)?.toDouble(),
        heartRate: m['heart_rate'] as int?,
        segmentStart: (m['segment_start'] as int? ?? 0) == 1,
      );
}

class ActivitySplit {
  final int number;
  final double distanceMeters;
  final int durationSeconds;

  const ActivitySplit(this.number, this.distanceMeters, this.durationSeconds);

  /// detik per km
  double get paceSecondsPerKm =>
      distanceMeters > 0 ? durationSeconds / (distanceMeters / 1000) : 0;
}

class Activity {
  final String id;
  final SportType sport;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final ActivityStatus status;
  final int elapsedSeconds;
  final int movingSeconds;
  final int pausedSeconds;
  final double distanceMeters;
  final double elevationGainMeters;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? caloriesEstimated;
  final String source;
  final String? sourceDevice;

  /// Waktu pause terakhir dimulai (untuk pemulihan sesi yang sedang pause).
  final DateTime? pausedSince;

  const Activity({
    required this.id,
    required this.sport,
    required this.startedAt,
    this.finishedAt,
    required this.status,
    this.elapsedSeconds = 0,
    this.movingSeconds = 0,
    this.pausedSeconds = 0,
    this.distanceMeters = 0,
    this.elevationGainMeters = 0,
    this.avgHeartRate,
    this.maxHeartRate,
    this.caloriesEstimated,
    this.source = ActivitySource.phone,
    this.sourceDevice,
    this.pausedSince,
  });

  double get avgPaceSecondsPerKm => distanceMeters > 0
      ? movingSeconds / (distanceMeters / 1000)
      : 0;

  double get avgSpeedKmh =>
      movingSeconds > 0 ? (distanceMeters / movingSeconds) * 3.6 : 0;

  Activity copyWith({
    DateTime? finishedAt,
    ActivityStatus? status,
    int? elapsedSeconds,
    int? movingSeconds,
    int? pausedSeconds,
    double? distanceMeters,
    double? elevationGainMeters,
    int? avgHeartRate,
    int? maxHeartRate,
    int? caloriesEstimated,
    DateTime? pausedSince,
    bool clearPausedSince = false,
  }) =>
      Activity(
        id: id,
        sport: sport,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        status: status ?? this.status,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        movingSeconds: movingSeconds ?? this.movingSeconds,
        pausedSeconds: pausedSeconds ?? this.pausedSeconds,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
        avgHeartRate: avgHeartRate ?? this.avgHeartRate,
        maxHeartRate: maxHeartRate ?? this.maxHeartRate,
        caloriesEstimated: caloriesEstimated ?? this.caloriesEstimated,
        source: source,
        sourceDevice: sourceDevice,
        pausedSince:
            clearPausedSince ? null : (pausedSince ?? this.pausedSince),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'sport_type': sport.name,
        'started_at': startedAt.millisecondsSinceEpoch,
        'finished_at': finishedAt?.millisecondsSinceEpoch,
        'status': status.name,
        'elapsed_seconds': elapsedSeconds,
        'moving_seconds': movingSeconds,
        'paused_seconds': pausedSeconds,
        'distance_meters': distanceMeters,
        'elevation_gain_meters': elevationGainMeters,
        'avg_heart_rate': avgHeartRate,
        'max_heart_rate': maxHeartRate,
        'calories_estimated': caloriesEstimated,
        'source': source,
        'source_device': sourceDevice,
        'paused_since': pausedSince?.millisecondsSinceEpoch,
        'sync_status': 'pending',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory Activity.fromMap(Map<String, Object?> m) => Activity(
        id: m['id'] as String,
        sport: SportTypeX.fromName(m['sport_type'] as String),
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        finishedAt: m['finished_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['finished_at'] as int),
        status: ActivityStatus.values.firstWhere(
            (s) => s.name == m['status'],
            orElse: () => ActivityStatus.finished),
        elapsedSeconds: m['elapsed_seconds'] as int? ?? 0,
        movingSeconds: m['moving_seconds'] as int? ?? 0,
        pausedSeconds: m['paused_seconds'] as int? ?? 0,
        distanceMeters: (m['distance_meters'] as num? ?? 0).toDouble(),
        elevationGainMeters:
            (m['elevation_gain_meters'] as num? ?? 0).toDouble(),
        avgHeartRate: m['avg_heart_rate'] as int?,
        maxHeartRate: m['max_heart_rate'] as int?,
        caloriesEstimated: m['calories_estimated'] as int?,
        source: m['source'] as String? ?? ActivitySource.phone,
        sourceDevice: m['source_device'] as String?,
        pausedSince: m['paused_since'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['paused_since'] as int),
      );
}
