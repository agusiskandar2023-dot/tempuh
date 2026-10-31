import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../screens/home_screen.dart' show activityTitle;

/// Ukuran kartu bagikan. Digambar pada ukuran logis 360 px lebar lalu
/// diekspor dengan pixelRatio 3 → 1080 px.
enum ShareCardSize { square, story }

extension ShareCardSizeX on ShareCardSize {
  Size get logical =>
      this == ShareCardSize.square ? const Size(360, 360) : const Size(360, 640);
}

/// Titik rute sederhana (lat, lon) untuk kartu.
typedef RoutePoint = ({double lat, double lon});

/// Membuang [meters] pertama dan terakhir dari rute agar lokasi awal/akhir
/// (sering rumah) tidak terlihat. Rute pendek (< 4×[meters]) tidak dipotong
/// habis: dipotong seperempat panjangnya di tiap ujung.
List<RoutePoint> trimRouteEnds(List<RoutePoint> pts, {double meters = 200}) {
  if (pts.length < 3) return pts;
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last +
        haversineMeters(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon));
  }
  final total = cum.last;
  final cut = math.min(meters, total / 4);
  final out = <RoutePoint>[];
  for (var i = 0; i < pts.length; i++) {
    if (cum[i] >= cut && cum[i] <= total - cut) out.add(pts[i]);
  }
  return out.length >= 2 ? out : pts;
}

/// Kartu aktivitas untuk dibagikan ke WhatsApp / Instagram.
class ShareCard extends StatelessWidget {
  final Activity activity;
  final List<RoutePoint> route;
  final ShareCardSize size;
  final File? photo;
  final bool showHeartRate;

  const ShareCard({
    super.key,
    required this.activity,
    required this.route,
    required this.size,
    this.photo,
    this.showHeartRate = true,
  });

  bool get _hasPhoto => photo != null;

  List<(String, String, String?, bool)> _stats() {
    final a = activity;
    String km(double m) => formatKm(m).replaceAll('.', ',');
    final hasMax = (a.maxSpeedMps ?? 0) > 0;
    return [
      ('Jarak', km(a.distanceMeters), 'km', false),
      ('Waktu', formatDuration(a.movingSeconds), null, false),
      a.sport.showsSpeed
          ? ('Kecepatan', a.avgSpeedKmh.toStringAsFixed(1).replaceAll('.', ','), 'km/j', false)
          : ('Pace', formatPace(a.avgPaceSecondsPerKm), '/km', false),
      hasMax
          ? ('Kec. maks', formatSpeedKmh(a.maxSpeedMps!), 'km/j', true)
          : ('Elevasi', a.elevationGainMeters.round().toString(), 'm', false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = size.logical;
    return SizedBox(
      width: s.width,
      height: s.height,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.text, decoration: TextDecoration.none),
        child: ClipRect(
          child: Container(
            color: AppColors.navy,
            child: size == ShareCardSize.square ? _square() : _story(),
          ),
        ),
      ),
    );
  }

  Widget _photoLayer() => Positioned.fill(
        child: Image.file(photo!, fit: BoxFit.cover, gaplessPlayback: true),
      );

  Widget _gridLayer() => Positioned.fill(
        child: CustomPaint(painter: _GridPainter()),
      );

  Widget _header(double logo, double font, {bool datePill = true}) {
    final date = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(activity.startedAt);
    return Row(children: [
      TempuhLogo(size: logo),
      SizedBox(width: logo * 0.25),
      Text(appName,
          style: TextStyle(
              fontSize: font,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              shadows: const [Shadow(color: Color(0x73000000), blurRadius: 4)])),
      const Spacer(),
      if (datePill)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
              color: const Color(0xBF0B1220), borderRadius: BorderRadius.circular(99)),
          child: Text(date,
              style: const TextStyle(
                  fontSize: 7.5, fontWeight: FontWeight.w600, color: AppColors.soft)),
        ),
    ]);
  }

  Widget _stat((String, String, String?, bool) st, double label, double value, double unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(st.$1, style: TextStyle(fontSize: label, color: AppColors.muted)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: st.$2,
                style: TextStyle(
                    fontSize: value,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: st.$4 ? AppColors.lime : AppColors.text)),
            if (st.$3 != null)
              TextSpan(
                  text: ' ${st.$3}',
                  style: TextStyle(
                      fontSize: unit, color: AppColors.muted, fontWeight: FontWeight.w600)),
          ])),
        ),
      ],
    );
  }

  Widget _footer(double font) {
    final hr = showHeartRate ? activity.avgHeartRate : null;
    return Row(children: [
      if (hr != null) ...[
        Icon(Icons.favorite, size: font * 1.2, color: AppColors.danger),
        SizedBox(width: font * 0.4),
        Text('$hr bpm rata-rata', style: TextStyle(fontSize: font, color: AppColors.muted)),
      ],
      const Spacer(),
      Text(appCredit, style: TextStyle(fontSize: font, color: AppColors.muted)),
    ]);
  }

  Widget _square() {
    final stats = _stats();
    return Stack(children: [
      if (_hasPhoto) _photoLayer() else ...[
        _gridLayer(),
        Positioned(
          left: 40,
          top: 60,
          right: 40,
          height: 165,
          child: CustomPaint(painter: RoutePainter(route, strokeWidth: 4.5, markers: true)),
        ),
      ],
      Positioned(top: 18, left: 21, right: 21, child: _header(19, 11.5)),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          color: _hasPhoto ? const Color(0xD10B1220) : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(21, 13, 21, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                if (_hasPhoto && route.length >= 2) ...[
                  SizedBox(
                      width: 50,
                      height: 30,
                      child: CustomPaint(painter: RoutePainter(route, strokeWidth: 3))),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(activityTitle(activity),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                ),
              ]),
              const SizedBox(height: 7),
              Row(children: [
                for (final st in stats)
                  Expanded(child: _stat(st, 7.3, 16, 7.3)),
              ]),
              const SizedBox(height: 7),
              _footer(6.7),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _story() {
    final stats = _stats();
    final date =
        DateFormat('EEEE, d MMM yyyy · HH:mm', 'id_ID').format(activity.startedAt);
    return Stack(children: [
      if (_hasPhoto) _photoLayer() else ...[
        _gridLayer(),
        Positioned(
          left: 30,
          top: 100,
          right: 30,
          height: 250,
          child: CustomPaint(painter: RoutePainter(route, strokeWidth: 4.5, markers: true)),
        ),
      ],
      Positioned(top: 32, left: 24, right: 24, child: _header(25, 15.5, datePill: false)),
      Positioned(
        left: 16,
        right: 16,
        bottom: 40,
        child: Container(
          padding: const EdgeInsets.fromLTRB(17, 16, 17, 14),
          decoration: BoxDecoration(
              color: const Color(0xDB0B1220), borderRadius: BorderRadius.circular(15)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                if (route.length >= 2) ...[
                  SizedBox(
                      width: 66,
                      height: 40,
                      child: CustomPaint(painter: RoutePainter(route, strokeWidth: 3))),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(activityTitle(activity),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 23,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6)),
                      const SizedBox(height: 2),
                      Text(date,
                          style: const TextStyle(fontSize: 9.3, color: AppColors.muted)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 11),
              Row(children: [
                Expanded(child: _stat(stats[0], 9.3, 28, 10.7)),
                Expanded(child: _stat(stats[1], 9.3, 28, 10.7)),
              ]),
              const SizedBox(height: 9),
              Row(children: [
                Expanded(child: _stat(stats[2], 9.3, 21, 9.3)),
                Expanded(child: _stat(stats[3], 9.3, 21, 9.3)),
              ]),
              const SizedBox(height: 8),
              Container(height: 0.7, color: AppColors.raised),
              const SizedBox(height: 8),
              _footer(8.7),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF111A2C)
      ..strokeWidth = 7;
    for (final f in [0.3, 0.7]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), p);
    }
    for (final f in [0.24, 0.72]) {
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Menggambar garis rute (tanpa peta) agar pas di dalam kotak, menjaga
/// rasio aspek (proyeksi equirectangular sederhana).
class RoutePainter extends CustomPainter {
  final List<RoutePoint> route;
  final double strokeWidth;
  final bool markers;

  RoutePainter(this.route, {this.strokeWidth = 4, this.markers = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (route.length < 2) return;
    final lat0 = route.map((p) => p.lat).reduce((a, b) => a + b) / route.length;
    final k = math.cos(lat0 * math.pi / 180);
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in route) {
      final x = p.lon * k, y = -p.lat;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final pad = strokeWidth * 2;
    final w = math.max(maxX - minX, 1e-9), h = math.max(maxY - minY, 1e-9);
    final scale = math.min((size.width - pad * 2) / w, (size.height - pad * 2) / h);
    final ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2;
    Offset pt(RoutePoint p) =>
        Offset(ox + (p.lon * k - minX) * scale, oy + (-p.lat - minY) * scale);
    final path = Path()..moveTo(pt(route.first).dx, pt(route.first).dy);
    for (final p in route.skip(1)) {
      final o = pt(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.lime
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    if (markers) {
      final ring = Paint()
        ..color = AppColors.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final r = strokeWidth * 1.2;
      canvas.drawCircle(pt(route.first), r, Paint()..color = AppColors.text);
      canvas.drawCircle(pt(route.first), r, ring);
      canvas.drawCircle(pt(route.last), r, Paint()..color = AppColors.danger);
      canvas.drawCircle(pt(route.last), r, ring);
    }
  }

  @override
  bool shouldRepaint(covariant RoutePainter old) =>
      old.route != route || old.strokeWidth != strokeWidth;
}
