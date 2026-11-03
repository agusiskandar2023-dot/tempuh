import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../domain/replay.dart';

/// Ukuran logis frame video replay (9:16).
const replayFrame = Size(360, 640);

/// Area tempat rute dipaskan: hampir satu layar penuh, di bawah panel angka.
const replayRouteBox = Rect.fromLTWH(22, 150, 316, 456);

/// Proyeksi Web Mercator (sama dengan ubin peta OpenStreetMap) yang
/// memaskan rute ke [replayRouteBox]. Koordinat hasil dalam satuan logis.
class ReplayMapView {
  /// Zoom pecahan; 1 piksel mercator = 1 piksel perangkat pada [ref].
  final double zoom;
  final double cx, cy; // pusat rute, piksel mercator pada [zoom]
  final double bx, by; // pusat kotak, satuan logis
  final double ref; // piksel perangkat per satuan logis (video 720 px = 2)

  const ReplayMapView._(this.zoom, this.cx, this.cy, this.bx, this.by, this.ref);

  static double mercX(double lon, double z) => (lon + 180) / 360 * 256 * math.pow(2, z);
  static double mercY(double lat, double z) {
    final r = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
    final y = math.log(math.tan(r) + 1 / math.cos(r));
    return (1 - y / math.pi) / 2 * 256 * math.pow(2, z);
  }

  factory ReplayMapView.fit(ReplayData d, {Rect box = replayRouteBox, double ref = 2}) {
    if (d.length == 0) {
      return ReplayMapView._(2, 0, 0, box.center.dx, box.center.dy, ref);
    }
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (var i = 0; i < d.length; i++) {
      final x = mercX(d.lon[i], 0), y = mercY(d.lat[i], 0);
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final w = math.max(maxX - minX, 1e-9), h = math.max(maxY - minY, 1e-9);
    final scale = math.min(box.width * ref / w, box.height * ref / h);
    // Zoom 18 untuk rute sangat pendek agar tidak terlalu dekat.
    final zoom = (math.log(scale) / math.ln2).clamp(2.0, 18.0);
    final k = math.pow(2, zoom).toDouble();
    return ReplayMapView._(zoom, (minX + maxX) / 2 * k, (minY + maxY) / 2 * k,
        box.center.dx, box.center.dy, ref);
  }

  Offset toLogical(double lat, double lon) => Offset(
      bx + (mercX(lon, zoom) - cx) / ref, by + (mercY(lat, zoom) - cy) / ref);

  /// Zoom ubin bulat yang dipakai.
  int get tileZoom => zoom.round().clamp(1, 19);

  /// Ubin yang menutupi seluruh frame, beserta posisinya (satuan logis).
  List<({int z, int x, int y, Rect rect})> tiles() {
    final z = tileZoom;
    final tileDev = 256 * math.pow(2, zoom - z).toDouble();
    final n = 1 << z;
    // Batas frame dalam piksel mercator (perangkat) pada [zoom].
    final left = cx + (0 - bx) * ref, right = cx + (replayFrame.width - bx) * ref;
    final top = cy + (0 - by) * ref, bottom = cy + (replayFrame.height - by) * ref;
    final out = <({int z, int x, int y, Rect rect})>[];
    for (var ty = (top / tileDev).floor(); ty <= (bottom / tileDev).floor(); ty++) {
      if (ty < 0 || ty >= n) continue;
      for (var tx = (left / tileDev).floor(); tx <= (right / tileDev).floor(); tx++) {
        final rect = Rect.fromLTWH(bx + (tx * tileDev - cx) / ref,
            by + (ty * tileDev - cy) / ref, tileDev / ref, tileDev / ref);
        out.add((z: z, x: ((tx % n) + n) % n, y: ty, rect: rect));
      }
    }
    return out;
  }
}

/// Ubin peta OpenStreetMap untuk satu video replay.
class ReplayMap {
  final ReplayMapView view;
  final List<({ui.Image image, Rect rect})> tiles;
  const ReplayMap(this.view, this.tiles);

  bool get hasTiles => tiles.isNotEmpty;

  static const attribution = '© OpenStreetMap contributors';

  /// Mengunduh ubin (sekitar 20-30 buah). Ubin yang gagal dilewati;
  /// tanpa internet hasilnya kosong dan video memakai latar sederhana.
  static Future<ReplayMap> load(ReplayMapView view) async {
    final client = http.Client();
    try {
      final list = view.tiles();
      final results = await Future.wait(list.map((t) async {
        try {
          final res = await client.get(
            Uri.parse('https://tile.openstreetmap.org/${t.z}/${t.x}/${t.y}.png'),
            headers: const {'User-Agent': 'Tempuh/0.8 (aplikasi Android; github.com/agusiskandar2023-dot/tempuh)'},
          ).timeout(const Duration(seconds: 10));
          if (res.statusCode != 200) return null;
          final codec = await ui.instantiateImageCodec(res.bodyBytes);
          final frame = await codec.getNextFrame();
          return (image: frame.image, rect: t.rect);
        } catch (_) {
          return null;
        }
      }));
      final ok = results.whereType<({ui.Image image, Rect rect})>().toList();
      return ReplayMap(view, ok);
    } finally {
      client.close();
    }
  }

  void dispose() {
    for (final t in tiles) {
      t.image.dispose();
    }
  }
}
