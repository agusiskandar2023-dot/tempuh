import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';

/// Peta OpenStreetMap dengan garis rute, titik start, dan posisi saat ini.
///
/// [follow] = kamera mengikuti posisi terbaru (mode rekam). Bila false dan
/// rute tersedia, kamera menyesuaikan agar seluruh rute terlihat.
class RouteMap extends StatefulWidget {
  final List<LatLng> route;
  final LatLng? current;
  final bool follow;
  final bool interactive;

  /// Zoom saat mengikuti posisi (tingkat jalan). Diterapkan begitu GPS
  /// pertama kali mengunci posisi.
  final double followZoom;

  /// Jarak tombol zoom dari bawah (agar tidak tertutup panel lain).
  final double? controlsBottom;

  const RouteMap({
    super.key,
    required this.route,
    this.current,
    this.follow = false,
    this.interactive = true,
    this.followZoom = 17,
    this.controlsBottom,
  });

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final _controller = MapController();
  bool _ready = false;
  bool _userMoved = false;

  /// Sudah memperbesar ke [RouteMap.followZoom] setelah fix GPS pertama.
  bool _zoomedToStreet = false;

  static const _fallback = LatLng(-6.2, 106.816666); // Jakarta

  LatLng get _center =>
      widget.current ??
      (widget.route.isNotEmpty ? widget.route.last : _fallback);

  @override
  void didUpdateWidget(covariant RouteMap old) {
    super.didUpdateWidget(old);
    if (!_ready || !widget.follow || _userMoved) return;
    final c = widget.current;
    if (c != null && c != old.current) _follow(c);
  }

  /// Ikuti posisi. Fix GPS pertama langsung memperbesar ke tingkat jalan;
  /// setelah itu zoom pilihan pengguna dipertahankan.
  void _follow(LatLng c) {
    if (!_zoomedToStreet) {
      _zoomedToStreet = true;
      _controller.move(c, widget.followZoom);
    } else {
      _controller.move(c, _controller.camera.zoom);
    }
  }

  void _onReady() {
    _ready = true;
    final c = widget.current;
    if (widget.follow && c != null) _follow(c);
  }

  void _recenter() {
    setState(() => _userMoved = false);
    final z = _controller.camera.zoom;
    _controller.move(_center, z < 15 ? widget.followZoom : z);
  }

  void _zoomBy(double delta) {
    final cam = _controller.camera;
    final z = (cam.zoom + delta).clamp(3.0, 19.0);
    final center = widget.follow && !_userMoved && widget.current != null
        ? widget.current!
        : cam.center;
    _controller.move(center, z);
  }

  @override
  Widget build(BuildContext context) {
    final fitRoute = !widget.follow && widget.route.length >= 2;
    final start = widget.route.isNotEmpty ? widget.route.first : null;
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: widget.current == null && widget.route.isEmpty ? 11 : 16,
            initialCameraFit: fitRoute
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(widget.route),
                    padding: const EdgeInsets.all(24),
                  )
                : null,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : InteractiveFlag.none,
            ),
            onMapReady: _onReady,
            onMapEvent: (e) {
              // Hanya geser (drag) yang menghentikan mode ikuti; cubit-zoom
              // tetap mengikuti posisi.
              final dragged = e.source == MapEventSource.dragStart ||
                  e.source == MapEventSource.onDrag;
              if (dragged && widget.follow && !_userMoved) {
                setState(() => _userMoved = true);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.agus.movetrack_ai',
              maxZoom: 19,
            ),
            if (widget.route.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.route,
                    strokeWidth: 5,
                    color: AppColors.route,
                    borderStrokeWidth: 1.5,
                    borderColor: Colors.black54,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (start != null)
                  Marker(
                    point: start,
                    width: 18,
                    height: 18,
                    child: _dot(Colors.white, AppColors.lime),
                  ),
                if (widget.current != null)
                  Marker(
                    point: widget.current!,
                    width: 24,
                    height: 24,
                    child: _dot(AppColors.lime, AppColors.navy),
                  )
                else if (!widget.follow && widget.route.length >= 2)
                  Marker(
                    point: widget.route.last,
                    width: 18,
                    height: 18,
                    child: _dot(Colors.redAccent, Colors.white),
                  ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        if (widget.interactive)
          Positioned(
            right: 12,
            bottom: widget.controlsBottom ?? (widget.follow ? 48 : 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _mapButton(Icons.add, 'Perbesar', () => _zoomBy(1)),
                const SizedBox(height: 8),
                _mapButton(Icons.remove, 'Perkecil', () => _zoomBy(-1)),
                if (widget.follow && _userMoved) ...[
                  const SizedBox(height: 8),
                  _mapButton(Icons.my_location, 'Kembali ke posisi saya', _recenter),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _mapButton(IconData icon, String tooltip, VoidCallback onTap) => Material(
        color: AppColors.navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: AppColors.lime),
            ),
          ),
        ),
      );

  Widget _dot(Color fill, Color border) => Container(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
        ),
      );
}
