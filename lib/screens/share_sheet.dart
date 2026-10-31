import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../domain/metrics.dart';
import '../models/activity.dart';
import '../widgets/share_card.dart';
import 'home_screen.dart' show activityTitle;

/// Membuka lembar "Bagikan aktivitas".
Future<void> showShareSheet(
    BuildContext context, Activity activity, List<TrackPoint> points) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.charcoal,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => ShareSheet(activity: activity, points: points),
  );
}

class ShareSheet extends StatefulWidget {
  final Activity activity;
  final List<TrackPoint> points;
  const ShareSheet({super.key, required this.activity, required this.points});

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final _cardKey = GlobalKey();
  bool _withPhoto = false;
  ShareCardSize _size = ShareCardSize.square;
  File? _photo;
  bool _showHr = true;
  bool _hideEnds = false;
  bool _busy = false;

  late final List<RoutePoint> _route = [
    for (final p in widget.points) (lat: p.latitude, lon: p.longitude)
  ];
  List<RoutePoint> get _shownRoute => _hideEnds ? trimRouteEnds(_route) : _route;

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
          source: source, maxWidth: 2160, maxHeight: 3840, imageQuality: 90);
      if (x == null || !mounted) return;
      final file = File(x.path);
      await precacheImage(FileImage(file), context);
      if (!mounted) return;
      setState(() {
        _photo = file;
        _withPhoto = true;
      });
    } catch (e) {
      _snack('Tidak bisa membuka ${source == ImageSource.camera ? 'kamera' : 'galeri'}: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Merender kartu menjadi PNG 1080 px.
  Future<Uint8List?> _render() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  String get _fileName {
    final t = widget.activity.startedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'tempuh_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}';
  }

  String get _caption {
    final a = widget.activity;
    final km = formatKm(a.distanceMeters).replaceAll('.', ',');
    final pace = a.sport.showsSpeed
        ? '${a.avgSpeedKmh.toStringAsFixed(1).replaceAll('.', ',')} km/j'
        : '${formatPace(a.avgPaceSecondsPerKm)} /km';
    final max = (a.maxSpeedMps ?? 0) > 0
        ? ' · maks ${formatSpeedKmh(a.maxSpeedMps!)} km/j'
        : '';
    return '${activityTitle(a)}: $km km · ${formatDuration(a.movingSeconds)} · $pace$max\n'
        'Direkam dengan Tempuh';
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      if (bytes == null) return;
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        _snack('Izin galeri ditolak.');
        return;
      }
      await Gal.putImageBytes(bytes, name: _fileName);
      _snack('Gambar tersimpan di galeri.');
    } catch (e) {
      _snack('Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      if (bytes == null) return;
      await SharePlus.instance.share(ShareParams(
        text: _caption,
        files: [
          XFile.fromData(bytes,
              mimeType: 'image/png', name: '$_fileName.png')
        ],
        fileNameOverrides: ['$_fileName.png'],
      ));
    } catch (e) {
      _snack('Gagal membagikan: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _segment(List<(String, bool, VoidCallback)> items) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (final it in items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: it.$2 ? AppColors.lime : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: it.$3,
                  child: SizedBox(
                    height: 42,
                    child: Center(
                      child: Text(it.$1,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: it.$2 ? AppColors.navy : AppColors.soft)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final photo = _withPhoto ? _photo : null;
    final logical = _size.logical;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFF3B4A6B), borderRadius: BorderRadius.circular(99)),
              ),
            ),
            Row(children: [
              const Expanded(
                child: Text('Bagikan aktivitas',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.muted)),
            ]),
            const SizedBox(height: 6),
            _segment([
              ('Tanpa foto', !_withPhoto, () => setState(() => _withPhoto = false)),
              ('Dengan foto', _withPhoto, () => setState(() => _withPhoto = true)),
            ]),
            const SizedBox(height: 8),
            _segment([
              ('Persegi · chat & feed', _size == ShareCardSize.square,
                  () => setState(() => _size = ShareCardSize.square)),
              ('Story · status', _size == ShareCardSize.story,
                  () => setState(() => _size = ShareCardSize.story)),
            ]),
            const SizedBox(height: 12),
            Container(
              height: 300,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.navy, borderRadius: BorderRadius.circular(18)),
              child: FittedBox(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: SizedBox.fromSize(
                      size: logical,
                      child: ShareCard(
                        activity: a,
                        route: _shownRoute,
                        size: _size,
                        photo: photo,
                        showHeartRate: _showHr,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_withPhoto) ...[
              const SizedBox(height: 10),
              if (_photo == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Pilih foto dulu, dari galeri atau kamera.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                    onPressed: () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, color: AppColors.lime),
                    label: const Text('Galeri'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined, color: AppColors.lime),
                    label: const Text('Kamera'),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 4),
            if (a.avgHeartRate != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tampilkan detak jantung', style: TextStyle(fontSize: 14)),
                value: _showHr,
                onChanged: (v) => setState(() => _showHr = v),
              ),
            if (_route.length >= 3)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sembunyikan awal & akhir rute (privasi)',
                    style: TextStyle(fontSize: 14)),
                value: _hideEnds,
                onChanged: (v) => setState(() => _hideEnds = v),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                flex: 10,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _busy ? null : _save,
                  child: const Text('Simpan ke galeri',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 13,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _busy ? null : _share,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                      : const Icon(Icons.share),
                  label: const Text('Bagikan',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text('Lalu pilih WhatsApp, Instagram, atau aplikasi lain',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
