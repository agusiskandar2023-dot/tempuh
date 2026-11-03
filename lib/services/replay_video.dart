import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/replay.dart';
import '../models/activity.dart';
import 'replay_map.dart';
import '../widgets/replay_painter.dart';

/// Membuat video replay MP4 di HP: setiap frame digambar dengan
/// [ReplayPainter], lalu dikodekan H.264 oleh MediaCodec Android
/// (kanal "tempuh/video", lihat ci/android_kotlin/VideoEncoderChannel.kt).
class ReplayVideoMaker {
  static const _ch = MethodChannel('tempuh/video');
  static const width = 720;
  static const height = 1280;
  static const fps = 30;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  /// Mengembalikan path file MP4, atau null bila dibatalkan.
  Future<String?> make({
    required Activity activity,
    required ReplayData data,
    required ReplayTimeline timeline,
    required ReplayMapView view,
    ReplayMap? map,
    ui.Image? photo,
    bool showHeartRate = true,
    void Function(double progress)? onProgress,
  }) async {
    _cancelled = false;
    try {
      await GoogleFonts.pendingFonts();
    } catch (_) {
      // Tanpa internet: font bawaan dipakai.
    }
    final frames = (timeline.seconds * fps).round();
    await _ch.invokeMethod<String>('start',
        {'width': width, 'height': height, 'fps': fps, 'bitrate': 5000000});
    try {
      for (var i = 0; i < frames; i++) {
        if (_cancelled) {
          await _ch.invokeMethod('cancel');
          return null;
        }
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        ReplayPainter(
          view: view,
          map: map,
          activity: activity,
          data: data,
          timeline: timeline,
          t: i / fps,
          photo: photo,
          showHeartRate: showHeartRate,
        ).paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
        final pic = rec.endRecording();
        final img = await pic.toImage(width, height);
        pic.dispose();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        await _ch.invokeMethod('frame', {'bytes': bytes!.buffer.asUint8List()});
        onProgress?.call((i + 1) / frames);
      }
      return await _ch.invokeMethod<String>('finish');
    } catch (e) {
      try {
        await _ch.invokeMethod('cancel');
      } catch (_) {}
      rethrow;
    }
  }
}
