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

  const RouteMap({
    super.key,
    required this.route,
    this.current,
    this.follow = false,
    this.interactive = true,
  });

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final _controller = MapController();
  bool _ready = false;
  bool _userMoved = false;

  static const _fallback = LatLng(-6.2, 106.816666); // Jakarta

  LatLng get _center =>
      widget.current ??
      (widget.route.isNotEmpty ? widget.route.last : _fallback);

  @override
  void didUpdateWidget(covariant RouteMap old) {
    super.didUpdateWidget(old);
    if (!_ready || !widget.follow || _userMoved) return;
    final c = widget.current;
    if (c != null && c != old.current) {
      _controller.move(c, _controller.camera.zoom);
    }
  }

  void _recenter() {
    setState(() => _userMoved = false);
    _controller.move(_center, _controller.camera.zoom < 14 ? 16 : _controller.camera.zoom);
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
                    padding: const EdgeInsets.all(36),
                  )
                : null,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : InteractiveFlag.none,
            ),
            onMapReady: () => _ready = true,
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && widget.follow && !_userMoved) {
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
        if (widget.follow && _userMoved)
          Positioned(
            right: 12,
            bottom: 48,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: AppColors.navy,
              foregroundColor: AppColors.lime,
              onPressed: _recenter,
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }

  Widget _dot(Color fill, Color border) => Container(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
        ),
      );
}
