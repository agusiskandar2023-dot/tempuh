import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../models/activity.dart';

/// Gambar kecil rute aktivitas (tanpa peta), untuk kartu daftar.
class RouteThumbnail extends StatefulWidget {
  final Activity activity;
  final double size;
  const RouteThumbnail({super.key, required this.activity, this.size = 72});

  @override
  State<RouteThumbnail> createState() => _RouteThumbnailState();
}

class _RouteThumbnailState extends State<RouteThumbnail> {
  late Future<List<TrackPoint>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ActivityStore>().points(widget.activity.id);
  }

  @override
  void didUpdateWidget(covariant RouteThumbnail old) {
    super.didUpdateWidget(old);
    if (old.activity.id != widget.activity.id) {
      _future = context.read<ActivityStore>().points(widget.activity.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final size = widget.size;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<List<TrackPoint>>(
          future: _future,
          builder: (context, snap) {
            final pts = snap.data ?? const <TrackPoint>[];
            if (pts.length < 2) {
              return Container(
                color: AppColors.raised,
                alignment: Alignment.center,
                child: Icon(activity.sport.icon, color: AppColors.lime),
              );
            }
            return CustomPaint(painter: _RoutePainter(pts));
          },
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<TrackPoint> pts;
  _RoutePainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1B2740));
    final grid = Paint()
      ..color = const Color(0xFF22304D)
      ..strokeWidth = size.width / 16;
    for (final f in [0.3, 0.72]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), grid);
      canvas.drawLine(Offset(size.width * f, 0), Offset(size.width * f, size.height), grid);
    }
    var minLat = pts.first.latitude, maxLat = minLat;
    var minLon = pts.first.longitude, maxLon = minLon;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    final cosLat = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = math.max((maxLon - minLon) * cosLat, 1e-9);
    final h = math.max(maxLat - minLat, 1e-9);
    final pad = size.width * 0.14;
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    Offset map(TrackPoint p) => Offset(
          ox + (p.longitude - minLon) * cosLat * scale,
          size.height - (oy + (p.latitude - minLat) * scale),
        );
    final path = Path()..moveTo(map(pts.first).dx, map(pts.first).dy);
    for (final p in pts.skip(1)) {
      final o = map(p);
      if (p.segmentStart) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.lime
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(map(pts.first), 3.5, Paint()..color = AppColors.text);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) => old.pts != pts;
}
