import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../domain/metrics.dart';
import '../domain/replay.dart';
import '../models/activity.dart';
import '../services/replay_map.dart';
import '../services/replay_video.dart';
import '../widgets/replay_painter.dart';
import 'home_screen.dart' show activityTitle;

/// Bagian "Video replay" di lembar Bagikan: pratinjau animasi, pilihan
/// durasi 15/30 detik, foto opsional, lalu buat MP4 dan bagikan/simpan.
class ReplayPanel extends StatefulWidget {
  final Activity activity;
  final List<TrackPoint> points;
  const ReplayPanel({super.key, required this.activity, required this.points});

  @override
  State<ReplayPanel> createState() => _ReplayPanelState();
}

class _ReplayPanelState extends State<ReplayPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final _maker = ReplayVideoMaker();
  int _seconds = 15;
  bool _usePhoto = false;
  ui.Image? _photo;
  bool _hideEnds = false;
  bool _showHr = true;
  bool _busy = false;
  double _progress = 0;
  ReplayData? _data;
  ReplayMapView? _view;
  ReplayMap? _map;
  Future<void>? _mapLoading;
  bool _mapFailed = false;
  String? _videoPath;
  String? _videoKey;

  bool get _canReplay => ReplayData.canBuild(widget.points);
  ReplayTimeline get _timeline =>
      ReplayTimeline(_seconds.toDouble(), hasPhoto: _usePhoto && _photo != null);

  String get _settingsKey =>
      '$_seconds|${_usePhoto && _photo != null}|${_photo.hashCode}|$_hideEnds|$_showHr|${_map?.hasTiles}';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: Duration(seconds: _seconds));
    if (_canReplay) {
      _rebuildData();
      _anim.repeat();
    }
  }

  @override
  void dispose() {
    _maker.cancel();
    _anim.dispose();
    _photo?.dispose();
    _map?.dispose();
    super.dispose();
  }

  void _rebuildData() {
    _data = ReplayData.build(widget.activity, widget.points, hideEnds: _hideEnds);
    final view = ReplayMapView.fit(_data!);
    _view = view;
    _map?.dispose();
    _map = null;
    _mapFailed = false;
    _mapLoading = ReplayMap.load(view).then((m) {
      if (!mounted || _view != view) {
        m.dispose();
        return;
      }
      setState(() {
        _map = m;
        _mapFailed = !m.hasTiles;
      });
    });
  }

  void _setSeconds(int s) {
    setState(() => _seconds = s);
    _anim
      ..duration = Duration(seconds: s)
      ..repeat();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
          source: source, maxWidth: 1440, maxHeight: 2560, imageQuality: 90);
      if (x == null) return;
      final codec = await ui.instantiateImageCodec(await File(x.path).readAsBytes(),
          targetWidth: 1080);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _photo?.dispose();
        _photo = frame.image;
        _usePhoto = true;
      });
    } catch (e) {
      _snack('Tidak bisa membuka ${source == ImageSource.camera ? 'kamera' : 'galeri'}: $e');
    }
  }

  /// Membuat video (atau memakai hasil sebelumnya bila pengaturan sama).
  Future<String?> _ensureVideo() async {
    if (_videoPath != null && _videoKey == _settingsKey && File(_videoPath!).existsSync()) {
      return _videoPath;
    }
    setState(() {
      _busy = true;
      _progress = 0;
    });
    _anim.stop();
    try {
      // Tunggu peta selesai dimuat agar video memakai peta asli.
      await _mapLoading;
      final path = await _maker.make(
        view: _view!,
        map: _map,
        activity: widget.activity,
        data: _data!,
        timeline: _timeline,
        photo: _usePhoto ? _photo : null,
        showHeartRate: _showHr,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (path != null) {
        _videoPath = path;
        _videoKey = _settingsKey;
      }
      return path;
    } catch (e) {
      _snack('Gagal membuat video: $e');
      return null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _anim.repeat();
      }
    }
  }

  String get _fileName {
    final t = widget.activity.startedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'tempuh_replay_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}';
  }

  Future<void> _save() async {
    final path = await _ensureVideo();
    if (path == null) return;
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        _snack('Izin galeri ditolak.');
        return;
      }
      // Gal memakai nama file; salin dengan nama yang jelas.
      final named = File('${File(path).parent.path}/$_fileName.mp4');
      if (named.path != path) await File(path).copy(named.path);
      await Gal.putVideo(named.path);
      _snack('Video tersimpan di galeri.');
    } catch (e) {
      _snack('Gagal menyimpan: $e');
    }
  }

  Future<void> _share() async {
    final path = await _ensureVideo();
    if (path == null) return;
    final a = widget.activity;
    final km = formatKm(a.distanceMeters).replaceAll('.', ',');
    try {
      await SharePlus.instance.share(ShareParams(
        text: '${activityTitle(a)}: $km km · ${formatDuration(a.movingSeconds)}\nDirekam dengan Tempuh',
        files: [XFile(path, mimeType: 'video/mp4', name: '$_fileName.mp4')],
        fileNameOverrides: ['$_fileName.mp4'],
      ));
    } catch (e) {
      _snack('Gagal membagikan: $e');
    }
  }

  Widget _segment(List<(String, bool, VoidCallback?)> items) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
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
                    height: 40,
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
    if (!_canReplay) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(18)),
        child: const Text(
          'Video replay butuh rute GPS. Aktivitas ini tidak punya rute (misalnya dari Health Connect), jadi hanya bisa dibagikan sebagai gambar.',
          style: TextStyle(color: AppColors.soft),
        ),
      );
    }
    final data = _data!;
    final tl = _timeline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 340,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(18)),
          child: Center(
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (_, __) => CustomPaint(
                    painter: ReplayPainter(
                      view: _view!,
                      map: _map,
                      activity: widget.activity,
                      data: data,
                      timeline: tl,
                      t: _anim.value * _seconds,
                      photo: _usePhoto ? _photo : null,
                      showHeartRate: _showHr,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
            _map == null && !_mapFailed
                ? 'Memuat peta…'
                : _mapFailed
                    ? 'Peta tidak bisa dimuat (tanpa internet?). Video memakai latar sederhana.'
                    : 'Peta: OpenStreetMap',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, color: _mapFailed ? AppColors.amber : AppColors.muted)),
        const SizedBox(height: 8),
        _segment([
          ('15 detik', _seconds == 15, _busy ? null : () => _setSeconds(15)),
          ('30 detik', _seconds == 30, _busy ? null : () => _setSeconds(30)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sisipkan foto sebelum ringkasan', style: TextStyle(fontSize: 14)),
          value: _usePhoto,
          onChanged: _busy ? null : (v) => setState(() => _usePhoto = v),
        ),
        if (_usePhoto) ...[
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
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, color: AppColors.lime),
                label: const Text('Galeri'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, color: AppColors.lime),
                label: const Text('Kamera'),
              ),
            ),
          ]),
        ],
        if (widget.activity.avgHeartRate != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tampilkan detak jantung', style: TextStyle(fontSize: 14)),
            value: _showHr,
            onChanged: _busy ? null : (v) => setState(() => _showHr = v),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sembunyikan awal & akhir rute (privasi)',
              style: TextStyle(fontSize: 14)),
          value: _hideEnds,
          onChanged: _busy
              ? null
              : (v) => setState(() {
                    _hideEnds = v;
                    _rebuildData();
                  }),
        ),
        const SizedBox(height: 8),
        if (_busy) ...[
          Row(children: [
            const Expanded(child: Text('Membuat video…', style: TextStyle(fontSize: 13))),
            Text('${(_progress * 100).round()}%',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
                value: _progress, minHeight: 8, backgroundColor: AppColors.navy, color: AppColors.lime),
          ),
          TextButton(onPressed: _maker.cancel, child: const Text('Batal')),
        ],
        Row(children: [
          Expanded(
            flex: 10,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: _busy ? null : _save,
              child: const Text('Simpan video', style: TextStyle(fontWeight: FontWeight.w700)),
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
              icon: const Icon(Icons.share),
              label: const Text('Bagikan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Video ${tl.seconds.round()} detik, 9:16 (720×1280), dibuat di HP',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}
