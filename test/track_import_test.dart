import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/models/activity.dart';
import 'package:movetrack_ai/services/track_import.dart';

const gpx = '''<?xml version="1.0"?>
<gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
<trk><name>Lari pagi &amp; santai</name><type>running</type><trkseg>
<trkpt lat="-6.2000" lon="106.8"><ele>10</ele><time>2026-11-01T22:00:00Z</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>130</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions></trkpt>
<trkpt lat="-6.2010" lon="106.8"><ele>11</ele><time>2026-11-01T22:00:40Z</time></trkpt>
<trkpt lat="-6.2020" lon="106.8"><time>2026-11-01T22:05:00Z</time></trkpt>
</trkseg></trk></gpx>''';

const tcx = '''<TrainingCenterDatabase><Activities><Activity Sport="Biking"><Lap StartTime="x">
<TotalTimeSeconds>100</TotalTimeSeconds><DistanceMeters>500</DistanceMeters><Calories>20</Calories><Track>
<Trackpoint><Time>2026-11-01T22:00:00Z</Time><Position><LatitudeDegrees>-6.2</LatitudeDegrees><LongitudeDegrees>106.8</LongitudeDegrees></Position><HeartRateBpm><Value>120</Value></HeartRateBpm></Trackpoint>
<Trackpoint><Time>2026-11-01T22:01:40Z</Time><Position><LatitudeDegrees>-6.205</LatitudeDegrees><LongitudeDegrees>106.8</LongitudeDegrees></Position></Trackpoint>
</Track></Lap></Activity></Activities></TrainingCenterDatabase>''';

void main() {
  test('GPX: titik, nama, jenis, detak jantung, jeda jadi pause', () {
    final t = parseTrackFile('a.gpx', Uint8List.fromList(utf8.encode(gpx)));
    expect(t.title, 'Lari pagi & santai');
    expect(t.data.sport, SportType.running);
    expect(t.data.points.length, 3);
    expect(t.data.points[2].segmentStart, isTrue);
    expect(t.data.totalTimerSeconds, 40);
    expect(t.data.avgHeartRate, 130);
    final a = t.toActivity();
    expect(a.id, 'fit-${DateTime.utc(2026, 11, 1, 22).millisecondsSinceEpoch ~/ 1000}');
    expect(a.title, 'Lari pagi & santai');
    expect(a.distanceMeters, greaterThan(100));
  });

  test('TCX (juga .gz): jenis sepeda dan total dari lap', () {
    final gz = Uint8List.fromList(gzip.encode(utf8.encode(tcx)));
    final t = parseTrackFile('b.tcx.gz', gz);
    expect(t.data.sport, SportType.cycling);
    expect(t.data.totalDistanceMeters, 500);
    expect(t.data.totalTimerSeconds, 100);
    expect(t.data.totalCalories, 20);
    expect(t.data.avgHeartRate, 120);
  });

  test('ZIP ekspor Strava: nama & jenis dari activities.csv, renang dilewati', () async {
    final csv = 'Activity ID,Activity Date,Activity Name,Activity Type,Filename\n'
        '1,"Nov 1, 2026, 10:00:00 PM",Jalan sore,Walk,activities/1.gpx\n'
        '2,"Nov 2, 2026",Renang,Swim,activities/2.tcx\n';
    final arc = Archive()
      ..addFile(ArchiveFile.bytes('activities.csv', utf8.encode(csv)))
      ..addFile(ArchiveFile.bytes('activities/1.gpx', utf8.encode(gpx)))
      ..addFile(ArchiveFile.bytes('activities/2.tcx', utf8.encode(tcx)))
      ..addFile(ArchiveFile.bytes('media/foto.jpg', [1, 2, 3]));
    final zipped = ZipEncoder().encodeBytes(arc);
    final got = <ImportedTrack>[];
    final r = await readZip(ZipDecoder().decodeBytes(zipped), (t) async => got.add(t));
    expect(r.ok, 1);
    expect(r.skipped, 1);
    expect(got.single.title, 'Jalan sore');
    expect(got.single.data.sport, SportType.walking);
  });

  test('format tidak dikenal ditolak dengan pesan jelas', () {
    expect(() => parseTrackFile('x.kml', Uint8List(0)), throwsA(isA<ImportException>()));
  });

  test('nama file berubah saat unduh ulang (x.gpx-2) tetap terbaca dari isinya', () {
    final t = parseTrackFile('Morning_Run.gpx-2', Uint8List.fromList(utf8.encode(gpx)));
    expect(t.data.points.length, 3);
    expect(isTrackFileName('activities/Lari.gpx-2'), isTrue);
    expect(isTrackFileName('activities/Lari (1).gpx'), isTrue);
    expect(isTrackFileName('media/foto.jpg'), isFalse);
  });
}
