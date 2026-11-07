import 'package:flutter/foundation.dart';

import '../domain/training_plan.dart';
import 'database.dart';

/// Catatan program latihan FM: tanggal lomba + status tiap slot latihan.
/// Disimpan di HP lebih dulu, lalu ikut tersinkron ke Neon (dan web).
class TrainingStore extends ChangeNotifier {
  TrainingStore({AppDatabase? db}) : _db = db ?? AppDatabase.instance;
  final AppDatabase _db;

  DateTime raceDate = defaultRaceDate;
  final Map<String, TrainingEntry> _entries = {};
  bool loaded = false;

  /// Dipanggil setelah perubahan lokal (untuk meminta sinkron).
  VoidCallback? onChanged;

  TrainingCalendar get calendar => TrainingCalendar(raceDate);

  TrainingEntry? entry(int week, String slot) => _entries['$week|$slot'];

  Future<void> reload() async {
    final st = await _db.trainingSettings();
    if (st != null) {
      final d = DateTime.tryParse(st['race_date'] as String);
      if (d != null) raceDate = d;
    }
    _entries.clear();
    for (final r in await _db.trainingRows()) {
      final e = TrainingEntry(
        r['week'] as int,
        r['slot'] as String,
        r['done'] == 1,
        (r['km'] as num?)?.toDouble(),
        DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      );
      _entries['${e.week}|${e.slot}'] = e;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> setEntry(int week, String slot, {required bool done, double? km}) async {
    final now = DateTime.now();
    _entries['$week|$slot'] = TrainingEntry(week, slot, done, km, now);
    notifyListeners();
    await _db.putTraining(week, slot, done, km, now);
    onChanged?.call();
  }

  Future<void> toggle(int week, String slot) async {
    final e = entry(week, slot);
    await setEntry(week, slot, done: !(e?.done ?? false), km: e?.km);
  }

  Future<void> setRaceDate(DateTime d) async {
    raceDate = DateTime(d.year, d.month, d.day);
    notifyListeners();
    final s = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await _db.putTrainingSettings(s, DateTime.now());
    onChanged?.call();
  }
}
