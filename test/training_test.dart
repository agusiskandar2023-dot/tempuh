import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/domain/training_plan.dart';
import 'package:movetrack_ai/models/activity.dart';

void main() {
  test('kalender: 31 minggu berakhir di hari lomba', () {
    final c = TrainingCalendar(DateTime(2027, 6, 13));
    expect(c.start, DateTime(2026, 11, 9));
    expect(c.start.weekday, DateTime.monday);
    expect(c.dateOf(31, 6), DateTime(2027, 6, 13));
    expect(c.weekOf(DateTime(2026, 11, 7)), 0);
    expect(c.weekOf(DateTime(2026, 11, 10, 6)), 1);
    expect(c.weekOf(DateTime(2027, 6, 13)), 31);
    expect(c.phaseOf(1).name, 'Bangun kembali');
    expect(c.phaseOf(31).name, 'Tapering');
    expect(fmPlan.length, fmWeeks);
    expect(fmPlan.every((w) => w.sessions.length == 4), isTrue);
    expect(fmPlan.last.sessions.last.race, isTrue);
  });

  test('status sesi: manual, otomatis dari aktivitas, sepeda tidak dihitung', () {
    final day = DateTime(2026, 11, 10);
    Activity act(SportType s, double m) => Activity(
        id: 'a$m', sport: s, startedAt: DateTime(2026, 11, 10, 5, 30),
        status: ActivityStatus.finished, distanceMeters: m);
    final items = [act(SportType.running, 4200), act(SportType.cycling, 20000)];
    final same = activitiesOn(items, day);
    expect(same.length, 1);
    final auto = sessionStatus(null, same);
    expect(auto.done, isTrue);
    expect(auto.auto, isTrue);
    expect(auto.km, closeTo(4.2, 1e-9));
    final manual = sessionStatus(TrainingEntry(1, 'tue', true, 5, DateTime.now()), const []);
    expect(manual.done, isTrue);
    expect(manual.km, 5);
    expect(sessionStatus(null, const []).done, isFalse);
  });
}
