import 'package:flutter_test/flutter_test.dart';
import 'package:movetrack_ai/models/activity.dart';
import 'package:movetrack_ai/services/cloud_service.dart';

Activity act(String id) => Activity(
      id: id,
      sport: SportType.running,
      startedAt: DateTime.utc(2025, 10, 28, 8),
      status: ActivityStatus.finished,
    );

void main() {
  test('stableUuid sama dengan versi web (upload .FIT tidak ganda)', () {
    // Nilai pembanding dihitung dengan fungsi stableUuid di web/js/app.js.
    expect(stableUuid('tempuh:fit:u1:1761638400'),
        '539cf9a6-bd0a-54d6-9e8d-a5323153140d');
  });

  test('ID cloud: UUID HP dipakai apa adanya, impor .FIT memakai rumus web', () {
    final c = CloudService()..userId = 'u1';
    const phone = '0b7e3c1a-1234-4abc-9def-0123456789ab';
    expect(c.cloudIdFor(act(phone), null), phone);
    expect(c.cloudIdFor(act('fit-1761638400'), null),
        '539cf9a6-bd0a-54d6-9e8d-a5323153140d');
    final hc = c.cloudIdFor(act('hc-abc'), null);
    expect(hc, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(c.cloudIdFor(act('hc-abc'), null), hc); // deterministik
    expect(c.cloudIdFor(act(phone), 'existing-id'), 'existing-id');
  });
}
