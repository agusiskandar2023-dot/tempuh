import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/activity_store.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../services/tracking_service.dart';
import '../widgets/route_map.dart';
import '../widgets/stat_tile.dart';
import 'activity_detail_screen.dart';

class TrackScreen extends StatelessWidget {
  const TrackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final active = context.select<TrackingService, bool>((t) => t.isActive);
    return active ? const _LiveView() : const _SetupView();
  }
}

/// Chip gelap di atas peta.
class _MapChip extends StatelessWidget {
  final Widget leading;
  final String text;
  const _MapChip({required this.leading, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          leading,
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Panel bawah membulat yang sedikit menutupi peta.
class _Sheet extends StatelessWidget {
  final Widget child;
  const _Sheet({required this.child});

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: const Offset(0, -16),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.charcoal,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: child,
        ),
      );
}

class _SetupView extends StatefulWidget {
  const _SetupView();

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  SportType _sport = SportType.running;
  LatLng? _here;
  bool _batteryOk = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final t = context.read<TrackingService>();
    final ok = await t.isIgnoringBatteryOptimizations();
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final p = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition(
                locationSettings:
                    const LocationSettings(accuracy: LocationAccuracy.high));
        if (mounted) setState(() => _here = LatLng(p.latitude, p.longitude));
      }
    } catch (_) {}
    if (mounted) setState(() => _batteryOk = ok);
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final err = await context.read<TrackingService>().start(_sport);
    if (!mounted) return;
    setState(() => _starting = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                  child: RouteMap(route: const [], current: _here, follow: true)),
              const Positioned(
                top: 16,
                left: 16,
                child: SafeArea(
                  child: _MapChip(
                    leading: Icon(Icons.gps_fixed, size: 16, color: AppColors.lime),
                    text: 'Pilih olahraga lalu tekan START',
                  ),
                ),
              ),
            ]),
          ),
          _Sheet(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_batteryOk) ...[
                  Material(
                    color: const Color(0xFF3B2F0B),
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      leading: const Icon(Icons.battery_alert, color: AppColors.amber),
                      title: const Text('Izinkan berjalan di latar belakang',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: const Text(
                          'Agar rekaman tidak dihentikan penghemat baterai saat HP sleep.',
                          style: TextStyle(fontSize: 12)),
                      onTap: () async {
                        final ok = await context
                            .read<TrackingService>()
                            .requestIgnoreBatteryOptimizations();
                        setState(() => _batteryOk = ok);
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(children: [
                  const Icon(Icons.motion_photos_pause_outlined, color: AppColors.muted, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Auto-pause saat berhenti',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  Switch(
                    value: context.watch<TrackingService>().autoPauseEnabled,
                    onChanged: (v) => context.read<TrackingService>().setAutoPause(v),
                  ),
                ]),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                  children: [
                    for (final s in SportType.values) _sportTile(s),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _starting ? null : _start,
                    icon: _starting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow_rounded, size: 30),
                    label: Text('START ${_sport.label.toUpperCase()}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sportTile(SportType s) {
    final on = s == _sport;
    return Material(
      color: on ? AppColors.lime : AppColors.navy,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _sport = s),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(s.icon, color: on ? AppColors.navy : AppColors.lime, size: 28),
            const SizedBox(height: 6),
            Text(s.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on ? AppColors.navy : AppColors.soft)),
          ],
        ),
      ),
    );
  }
}

class _LiveView extends StatelessWidget {
  const _LiveView();

  Future<void> _finish(BuildContext context) async {
    final t = context.read<TrackingService>();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoal,
        title: const Text('Selesaikan aktivitas?'),
        content: Text(
            'Jarak ${formatKm(t.distanceMeters)} km, waktu aktif ${formatDuration(t.movingSeconds)}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Buang', style: TextStyle(color: AppColors.danger))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'discard') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c2) => AlertDialog(
          backgroundColor: AppColors.charcoal,
          title: const Text('Buang aktivitas ini?'),
          content: const Text('Rute dan metrik sesi ini akan dihapus.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c2, false),
                child: const Text('Batal')),
            TextButton(
                onPressed: () => Navigator.pop(c2, true),
                child: const Text('Buang', style: TextStyle(color: AppColors.danger))),
          ],
        ),
      );
      if (sure == true) await t.discard();
      return;
    }
    final id = await t.finish();
    if (!context.mounted) return;
    await context.read<ActivityStore>().reload();
    if (id != null && context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ActivityDetailScreen(activityId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrackingService>();
    final a = t.activity!;
    final calc = t.calc!;
    final route =
        calc.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final fix = t.lastFix;
    final paused = t.state == TrackingState.paused;
    final speed = calc.currentSpeedMps();
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: RouteMap(
                  route: route,
                  current: fix == null ? null : LatLng(fix.latitude, fix.longitude),
                  follow: true,
                  followZoom: a.sport == SportType.cycling ? 16 : 17,
                ),
              ),
              Positioned(
                top: 0,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _MapChip(
                          leading: const Icon(Icons.satellite_alt,
                              size: 16, color: AppColors.lime),
                          text: t.gpsQuality,
                        ),
                        _MapChip(
                          leading: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: paused ? AppColors.amber : AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                          text: t.autoPaused ? 'Auto-pause' : (paused ? 'Dijeda' : 'Merekam'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
          _Sheet(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(a.sport.icon, color: AppColors.lime, size: 20),
                  const SizedBox(width: 8),
                  Text(a.sport.label,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _AutoPauseChip(enabled: t.autoPauseEnabled, onTap: () => t.setAutoPause(!t.autoPauseEnabled)),
                ]),
                if (t.autoPaused)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0x26FBBF24),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Row(children: [
                      Icon(Icons.pause_circle_outline, color: AppColors.amber, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('AUTO-PAUSE · lanjut otomatis saat Anda bergerak',
                            style: TextStyle(
                                color: AppColors.amber,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                if (t.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(t.error!,
                        style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatTile.large('Jarak',
                        formatKm(t.distanceMeters).replaceAll('.', ','),
                        unit: 'km'),
                    StatTile.large('Waktu aktif', formatDuration(t.movingSeconds),
                        align: CrossAxisAlignment.end),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Expanded(
                        child: a.sport.showsSpeed
                            ? StatTile('Kecepatan',
                                speed == null
                                    ? '--'
                                    : (speed * 3.6).toStringAsFixed(1).replaceAll('.', ','),
                                unit: 'km/j',
                                size: 22)
                            : StatTile('Pace', formatPace(calc.currentPaceSecondsPerKm()),
                                unit: '/km', size: 22),
                      ),
                      Expanded(
                          child: StatTile('Total', formatDuration(t.elapsedSeconds),
                              size: 22)),
                      Expanded(
                          child: StatTile('Elevasi',
                              calc.elevationGainMeters.round().toString(),
                              unit: 'm', size: 22)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 64,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: paused ? AppColors.lime : AppColors.raised,
                            foregroundColor: paused ? AppColors.navy : AppColors.text,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: paused ? t.resume : t.pause,
                          icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                              size: 28),
                          label: Text(paused ? 'LANJUT' : 'PAUSE',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 64,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: () => _finish(context),
                          icon: const Icon(Icons.stop_rounded, size: 28),
                          label: const Text('SELESAI',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Saklar kecil auto-pause di panel rekam.
class _AutoPauseChip extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _AutoPauseChip({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        toggled: enabled,
        child: Material(
          color: enabled ? const Color(0x26A3E635) : AppColors.raised,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(enabled ? 'Auto-pause: aktif' : 'Auto-pause: mati',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: enabled ? AppColors.lime : AppColors.muted)),
            ),
          ),
        ),
      );
}
