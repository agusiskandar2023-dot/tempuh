import 'dart:typed_data';

import '../models/activity.dart';

/// Hasil parsing file aktivitas .FIT (format file jam Garmin).
class FitActivity {
  final SportType sport;
  final DateTime? startTime;
  final double? totalElapsedSeconds;
  final double? totalTimerSeconds;
  final double? totalDistanceMeters;
  final int? totalCalories;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final double? totalAscentMeters;
  final int? manufacturer;
  final List<TrackPoint> points;

  /// Semua sampel detak jantung (termasuk record tanpa koordinat).
  final List<int> heartRates;

  const FitActivity({
    required this.sport,
    this.startTime,
    this.totalElapsedSeconds,
    this.totalTimerSeconds,
    this.totalDistanceMeters,
    this.totalCalories,
    this.avgHeartRate,
    this.maxHeartRate,
    this.totalAscentMeters,
    this.manufacturer,
    required this.points,
    required this.heartRates,
  });

  bool get isGarmin => manufacturer == 1;
}

class FitFormatException implements Exception {
  final String message;
  FitFormatException(this.message);
  @override
  String toString() => 'File .FIT tidak valid: $message';
}

class _FieldDef {
  final int num;
  final int size;
  final int baseType;
  const _FieldDef(this.num, this.size, this.baseType);
}

class _MsgDef {
  final int globalNum;
  final Endian endian;
  final List<_FieldDef> fields;
  final int devDataSize;
  const _MsgDef(this.globalNum, this.endian, this.fields, this.devDataSize);
}

/// Parser .FIT minimal tanpa dependensi: membaca file_id, session, event
/// (timer start/stop) dan record (koordinat, waktu, HR, altitude, jarak).
class FitParser {
  static const _fitEpochOffset = 631065600; // 1989-12-31T00:00:00Z
  static const _semicircleToDeg = 180.0 / 2147483648.0;

  static const _msgFileId = 0;
  static const _msgSession = 18;
  static const _msgRecord = 20;
  static const _msgEvent = 21;

  static FitActivity parse(Uint8List bytes) {
    if (bytes.length < 12) throw FitFormatException('file terlalu kecil');
    final bd = ByteData.sublistView(bytes);
    final headerSize = bytes[0];
    if (headerSize != 12 && headerSize != 14) {
      throw FitFormatException('ukuran header $headerSize');
    }
    if (String.fromCharCodes(bytes.sublist(8, 12)) != '.FIT') {
      throw FitFormatException('signature .FIT tidak ditemukan');
    }
    final dataSize = bd.getUint32(4, Endian.little);
    final end = (headerSize + dataSize).clamp(0, bytes.length);

    final defs = <int, _MsgDef>{};
    var pos = headerSize;
    int? lastTimestamp;

    int? sportEnum;
    int? sessionStart;
    double? elapsed, timer, distance, ascent;
    int? calories, avgHr, maxHr, manufacturer;
    final points = <TrackPoint>[];
    final heartRates = <int>[];
    var nextSegmentStart = false;
    var timerStopped = false;

    while (pos < end) {
      final header = bytes[pos++];
      int localType;
      int? compressedTs;
      if (header & 0x80 != 0) {
        // Compressed timestamp header (selalu pesan data).
        localType = (header >> 5) & 0x03;
        final offset = header & 0x1F;
        if (lastTimestamp != null) {
          var ts = (lastTimestamp & ~0x1F) + offset;
          if (offset < (lastTimestamp & 0x1F)) ts += 0x20;
          compressedTs = ts;
          lastTimestamp = ts;
        }
      } else if (header & 0x40 != 0) {
        // Definition message.
        localType = header & 0x0F;
        final hasDev = header & 0x20 != 0;
        if (pos + 5 > end) break;
        final arch = bytes[pos + 1];
        final endian = arch == 1 ? Endian.big : Endian.little;
        final globalNum = bd.getUint16(pos + 2, endian);
        final nFields = bytes[pos + 4];
        pos += 5;
        final fields = <_FieldDef>[];
        for (var i = 0; i < nFields; i++) {
          fields.add(_FieldDef(bytes[pos], bytes[pos + 1], bytes[pos + 2]));
          pos += 3;
        }
        var devSize = 0;
        if (hasDev) {
          final nDev = bytes[pos++];
          for (var i = 0; i < nDev; i++) {
            devSize += bytes[pos + 1];
            pos += 3;
          }
        }
        defs[localType] = _MsgDef(globalNum, endian, fields, devSize);
        continue;
      } else {
        localType = header & 0x0F;
      }

      final def = defs[localType];
      if (def == null) {
        throw FitFormatException('pesan tanpa definisi (local $localType)');
      }
      final values = <int, int>{};
      for (final f in def.fields) {
        final v = _readInt(bd, pos, f, def.endian);
        if (v != null) values[f.num] = v;
        pos += f.size;
      }
      pos += def.devDataSize;

      final ts = values[253];
      if (ts != null) lastTimestamp = ts;
      final when = ts ?? compressedTs;

      switch (def.globalNum) {
        case _msgFileId:
          manufacturer = values[1];
        case _msgEvent:
          // event 0 = timer; event_type 0 = start, 1 = stop, 4 = stop_all
          if (values[0] == 0) {
            final type = values[1];
            if (type == 1 || type == 4) {
              timerStopped = true;
            } else if (type == 0 && timerStopped) {
              timerStopped = false;
              nextSegmentStart = points.isNotEmpty;
            }
          }
        case _msgSession:
          sportEnum = values[5] ?? sportEnum;
          sessionStart = values[2] ?? sessionStart;
          elapsed = _scaled(values[7], 1000) ?? elapsed;
          timer = _scaled(values[8], 1000) ?? timer;
          distance = _scaled(values[9], 100) ?? distance;
          calories = values[11] ?? calories;
          avgHr = values[16] ?? avgHr;
          maxHr = values[17] ?? maxHr;
          ascent = values[22]?.toDouble() ?? ascent;
        case _msgRecord:
          final hr = values[3];
          if (hr != null) heartRates.add(hr);
          final lat = values[0];
          final lon = values[1];
          if (lat == null || lon == null || when == null) break;
          final altRaw = values[78] ?? values[2];
          final speedRaw = values[73] ?? values[6];
          points.add(TrackPoint(
            sequenceNo: points.length,
            recordedAt: _toDate(when),
            latitude: lat * _semicircleToDeg,
            longitude: lon * _semicircleToDeg,
            altitude: altRaw == null ? null : altRaw / 5.0 - 500,
            speed: speedRaw == null ? null : speedRaw / 1000.0,
            heartRate: hr,
            segmentStart: nextSegmentStart,
          ));
          nextSegmentStart = false;
      }
    }

    if (avgHr == null && heartRates.isNotEmpty) {
      avgHr = (heartRates.reduce((a, b) => a + b) / heartRates.length).round();
      maxHr = heartRates.reduce((a, b) => a > b ? a : b);
    }

    return FitActivity(
      sport: _mapSport(sportEnum),
      startTime: sessionStart != null
          ? _toDate(sessionStart)
          : (points.isNotEmpty ? points.first.recordedAt : null),
      totalElapsedSeconds: elapsed,
      totalTimerSeconds: timer,
      totalDistanceMeters: distance,
      totalCalories: calories,
      avgHeartRate: avgHr,
      maxHeartRate: maxHr,
      totalAscentMeters: ascent,
      manufacturer: manufacturer,
      points: points,
      heartRates: heartRates,
    );
  }

  static DateTime _toDate(int fitSeconds) =>
      DateTime.fromMillisecondsSinceEpoch((fitSeconds + _fitEpochOffset) * 1000,
          isUtc: true)
          .toLocal();

  static double? _scaled(int? v, int scale) => v == null ? null : v / scale;

  static SportType _mapSport(int? s) => switch (s) {
        2 => SportType.cycling,
        11 || 17 => SportType.walking,
        _ => SportType.running,
      };

  /// Membaca nilai integer tunggal. null bila tipe bukan integer 1/2/4 byte
  /// atau nilainya "invalid" menurut spesifikasi FIT.
  static int? _readInt(ByteData bd, int pos, _FieldDef f, Endian e) {
    final base = f.baseType & 0x1F;
    if (pos + f.size > bd.lengthInBytes) return null;
    switch (base) {
      case 0: // enum
      case 2: // uint8
      case 10: // uint8z
      case 13: // byte
        if (f.size != 1) return null;
        final v = bd.getUint8(pos);
        if (base == 10 ? v == 0 : v == 0xFF) return null;
        return v;
      case 1: // sint8
        if (f.size != 1) return null;
        final v = bd.getInt8(pos);
        return v == 0x7F ? null : v;
      case 3: // sint16
        if (f.size != 2) return null;
        final v = bd.getInt16(pos, e);
        return v == 0x7FFF ? null : v;
      case 4: // uint16
      case 11: // uint16z
        if (f.size != 2) return null;
        final v = bd.getUint16(pos, e);
        if (base == 11 ? v == 0 : v == 0xFFFF) return null;
        return v;
      case 5: // sint32
        if (f.size != 4) return null;
        final v = bd.getInt32(pos, e);
        return v == 0x7FFFFFFF ? null : v;
      case 6: // uint32
      case 12: // uint32z
        if (f.size != 4) return null;
        final v = bd.getUint32(pos, e);
        if (base == 12 ? v == 0 : v == 0xFFFFFFFF) return null;
        return v;
      default:
        return null;
    }
  }
}
