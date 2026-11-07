import '../models/activity.dart';

/// Program latihan full marathon 31 minggu (JAKIM 2027).
/// Lari: Selasa, Kamis, Sabtu, Minggu. Latihan kekuatan 10–15 menit tiap hari.
/// Rencana yang sama ada di web (web/js/training.js) — ubah keduanya bersamaan.

class PlanSession {
  final String title;
  final String detail;
  final double km; // perkiraan
  final bool long;
  final bool race;
  const PlanSession(this.title, this.detail, this.km, {this.long = false, this.race = false});
}

class PlanWeek {
  final List<PlanSession> sessions; // Selasa, Kamis, Sabtu, Minggu
  final String? note;
  final bool recovery;
  const PlanWeek(this.sessions, {this.note, this.recovery = false});
  double get km => sessions.fold(0, (t, s) => t + s.km);
}

class PlanPhase {
  final String name;
  final int from, to;
  const PlanPhase(this.name, this.from, this.to);
}

class RunDay {
  final String key;
  final String label;
  final int offset; // hari dari Senin
  const RunDay(this.key, this.label, this.offset);
}

const runDays = [
  RunDay('tue', 'Selasa', 1),
  RunDay('thu', 'Kamis', 3),
  RunDay('sat', 'Sabtu', 5),
  RunDay('sun', 'Minggu', 6),
];

/// Hari latihan kekuatan: kunci slot, label, kode rutinitas.
const strengthDays = [
  ('str_mon', 'Sen', 'A'),
  ('str_tue', 'Sel', 'M'),
  ('str_wed', 'Rab', 'B'),
  ('str_thu', 'Kam', 'M'),
  ('str_fri', 'Jum', 'A'),
  ('str_sat', 'Sab', 'C'),
  ('str_sun', 'Min', 'M'),
];

const strengthRoutines = {
  'A': ('Kaki & pinggul', 'Squat 2×12 · reverse lunge 2×8/kaki · glute bridge 2×15 · calf raise 2×15'),
  'B': ('Core', 'Plank 3×30 dtk · side plank 2×20 dtk/sisi · dead bug 2×10 · bird dog 2×10'),
  'C': ('Keseimbangan', 'Berdiri 1 kaki 3×30 dtk · step-up 2×10/kaki · single-leg calf raise 2×10'),
  'M': ('Mobilitas', '10 menit setelah lari: ayunan kaki, hip flexor, betis, hamstring'),
};

PlanSession _e(double km, [String d = 'Santai, bisa ngobrol']) =>
    PlanSession('Lari mudah ${_k(km)} km', d, km);
PlanSession _m(int min, [String d = 'Lari 3 mnt, jalan 1 mnt']) =>
    PlanSession('Lari-jalan $min menit', d, (min / 10 * 10).round() / 10);
PlanSession _w(int min) =>
    PlanSession('Jalan cepat $min menit', 'Atau lari sangat ringan', (min / 11 * 10).round() / 10);
PlanSession _l(double km, [String d = 'Pelan, boleh lari-jalan']) =>
    PlanSession('Long run ${_k(km)} km', d, km, long: true);
PlanSession _q(double km, String t, String d) => PlanSession(t, d, km);
String _k(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ',');

const fmPhases = [
  PlanPhase('Bangun kembali', 1, 6),
  PlanPhase('Dasar aerobik', 7, 14),
  PlanPhase('Kekuatan & tempo', 15, 22),
  PlanPhase('Puncak', 23, 28),
  PlanPhase('Tapering', 29, 31),
];

final List<PlanWeek> fmPlan = [
  PlanWeek([_m(30), _m(30), _w(45), _l(6, 'Lari 3 mnt, jalan 1 mnt')],
      note: 'Tujuannya membiasakan lagi. Jangan kejar pace.'),
  PlanWeek([_m(30), _m(35), _w(45), _l(7, 'Lari 3 mnt, jalan 1 mnt')]),
  PlanWeek([_m(35), _m(35), _w(50), _l(8, 'Lari 4 mnt, jalan 1 mnt')]),
  PlanWeek([_m(30), _m(30), _w(40), _l(6)], recovery: true),
  PlanWeek([_m(40, 'Lari 4 mnt, jalan 1 mnt'), _m(40, 'Lari 4 mnt, jalan 1 mnt'),
    _m(30, 'Lari ringan, jalan bila perlu'), _l(9, 'Lari 5 mnt, jalan 1 mnt')]),
  PlanWeek([_m(40, 'Lari 5 mnt, jalan 1 mnt'), _m(40, 'Lari 5 mnt, jalan 1 mnt'),
    _m(35, 'Lari ringan'), _l(10, 'Lari 5 mnt, jalan 1 mnt')]),
  PlanWeek([_e(6), _e(6), _e(4), _l(11)],
      note: 'Mulai lari terus-menerus di sesi pendek. Long run masih boleh lari-jalan.'),
  PlanWeek([_e(6), _q(7, 'Mudah 7 km + strides', '6× 20 dtk agak cepat di akhir'), _e(4), _l(12)]),
  PlanWeek([_e(7), _e(7), _e(5), _l(13)]),
  PlanWeek([_e(5), _e(5), _e(4), _l(10)], recovery: true),
  PlanWeek([_e(7), _q(8, 'Fartlek 8 km', '6× 1 mnt agak cepat, 2 mnt santai'), _e(5), _l(14)]),
  PlanWeek([_e(8), _e(8), _e(5), _l(16)]),
  PlanWeek([_e(8), _q(8, 'Tempo 8 km', 'Pemanasan 2 km, 3 km tempo, sisanya santai'), _e(5), _l(17)]),
  PlanWeek([_e(6), _e(6), _e(4), _l(12)], recovery: true),
  PlanWeek([_e(8), _q(9, 'Tempo 9 km', '4 km tempo di tengah'), _e(5),
    _l(18, 'Latih minum & gel tiap 40 mnt')],
      note: 'Kamis jadi sesi kualitas. Mulai latih asupan di long run.'),
  PlanWeek([_e(8), _q(9, 'Bukit 9 km', '6× 1 mnt tanjakan, turun jalan/jog'), _e(6), _l(20)]),
  PlanWeek([_e(9), _q(10, 'Tempo 10 km', '5 km tempo di tengah'), _e(6), _l(22)]),
  PlanWeek([_e(6), _e(7), _e(5), _l(14)], recovery: true),
  PlanWeek([_e(9), _q(10, 'Pace maraton 10 km', '6 km di pace MP'), _e(6), _l(24)]),
  PlanWeek([_e(9), _q(10, 'Tempo 10 km', '6 km tempo'), _e(6),
    _l(21, 'Atau ikut lomba HM sebagai uji coba')]),
  PlanWeek([_e(10), _q(11, 'Pace maraton 11 km', '8 km di pace MP'), _e(6), _l(26)]),
  PlanWeek([_e(7), _e(8), _e(5), _l(16)], recovery: true),
  PlanWeek([_e(10), _q(12, 'Pace maraton 12 km', '10 km di pace MP'), _e(6), _l(28)],
      note: 'Fase puncak. Long run pakai baju, sepatu, dan gel yang sama dengan hari H.'),
  PlanWeek([_e(10), _q(12, 'Tempo 12 km', '6 km tempo'), _e(6),
    _l(30, 'Jam 04.00 kalau bisa, simulasi start')]),
  PlanWeek([_e(8), _e(8), _e(5), _l(18)], recovery: true),
  PlanWeek([_e(10), _q(13, 'Pace maraton 13 km', '12 km di pace MP'), _e(6), _l(30)]),
  PlanWeek([_e(10), _q(12, 'Tempo 12 km', '6 km tempo'), _e(6), _l(24)]),
  PlanWeek([_e(10), _q(12, 'Pace maraton 12 km', '10 km di pace MP'), _e(6),
    _l(32, 'Long run terjauh. Tentukan target finis setelah ini.')]),
  PlanWeek([_e(8), _q(10, 'Pace maraton 10 km', '8 km di pace MP'), _e(5), _l(22)],
      note: 'Volume turun, intensitas tetap sedikit. Badan sedang mengisi ulang.'),
  PlanWeek([_e(7), _q(8, 'Pace maraton 8 km', '5 km di pace MP'), _e(5), _l(14)]),
  PlanWeek([
    _q(6, 'Mudah 6 km + strides', '4× 20 dtk'),
    _q(5, 'Mudah 5 km', '3× 1 mnt di pace MP'),
    _q(3, 'Shakeout 3 km', 'Sangat santai, ambil racepack'),
    const PlanSession('LOMBA · 42,195 km', 'Start 04.00 · lari-jalan dari awal', 42.2,
        long: true, race: true),
  ], note: 'Minggu lomba. Tidur cukup, banyak karbohidrat Jumat–Sabtu, jangan coba hal baru.'),
];

const fmWeeks = 31;
final defaultRaceDate = DateTime(2027, 6, 13);

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

/// Kalender program berdasarkan tanggal lomba (hari Minggu minggu ke-31).
class TrainingCalendar {
  final DateTime raceDate;
  TrainingCalendar(DateTime race) : raceDate = _d(race);

  /// Senin minggu ke-1.
  DateTime get start => DateTime(raceDate.year, raceDate.month, raceDate.day - (30 * 7 + 6));
  DateTime weekStart(int w) => DateTime(start.year, start.month, start.day + (w - 1) * 7);
  DateTime dateOf(int w, int offset) {
    final s = weekStart(w);
    return DateTime(s.year, s.month, s.day + offset);
  }

  /// 0 = belum mulai, 1..31, 32 = sudah lewat.
  int weekOf(DateTime now) {
    final diff = _d(now).difference(start).inDays;
    if (diff < 0) return 0;
    return (diff ~/ 7 + 1).clamp(1, fmWeeks + 1);
  }

  int daysToRace(DateTime now) => raceDate.difference(_d(now)).inDays;

  PlanPhase phaseOf(int w) =>
      fmPhases.firstWhere((p) => w >= p.from && w <= p.to, orElse: () => fmPhases.last);
}

/// Catatan satu slot latihan (sesi lari atau latihan kekuatan).
class TrainingEntry {
  final int week;
  final String slot;
  final bool done;
  final double? km;
  final DateTime updatedAt;
  const TrainingEntry(this.week, this.slot, this.done, this.km, this.updatedAt);
}

/// Aktivitas Tempuh pada tanggal itu yang dihitung sebagai sesi lari
/// (lari, jogging, jalan kaki; sepeda tidak).
List<Activity> activitiesOn(List<Activity> items, DateTime day) => [
      for (final a in items)
        if (a.sport != SportType.cycling &&
            a.startedAt.year == day.year &&
            a.startedAt.month == day.month &&
            a.startedAt.day == day.day)
          a
    ];

/// Status sesi lari: selesai bila ditandai manual atau ada aktivitas Tempuh
/// di hari itu. Km: isian manual, atau jumlah km aktivitas hari itu.
({bool done, double? km, bool auto}) sessionStatus(
    TrainingEntry? e, List<Activity> sameDay) {
  final actKm = sameDay.fold<double>(0, (t, a) => t + a.distanceMeters / 1000);
  final manualKm = (e?.km ?? 0) > 0 ? e!.km : null;
  if (e?.done == true) return (done: true, km: manualKm ?? (actKm > 0 ? actKm : null), auto: false);
  if (sameDay.isNotEmpty) return (done: true, km: manualKm ?? actKm, auto: true);
  return (done: false, km: manualKm, auto: false);
}
