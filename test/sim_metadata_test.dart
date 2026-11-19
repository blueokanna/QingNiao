import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/messaging/models.dart';

void main() {
  test('subscription identity is independent of the eSIM logical slot', () {
    final sim = SimCard.fromMap({
      'id': 81,
      'slot': 2,
      'name': 'Travel',
      'carrier': 'Carrier',
      'isEmbedded': true,
    });
    expect(sim.id, 81);
    expect(sim.slot, 2);
    expect(sim.isEmbedded, isTrue);
    expect(sim.label, 'eSIM 2 · Travel');
  });

  test('missing slot metadata never becomes SIM 1', () {
    final sim = SimCard.fromMap({'id': 37, 'name': 'Personal'});
    expect(sim.slot, 0);
    expect(sim.isEmbedded, isFalse);
    expect(sim.label, 'SIM · Personal');
    expect(SimCard.fromMap({'slot': -1}).slot, 0);
  });

  test('number permission and phone-state permission remain independent', () {
    final access = AccessState.fromMap({
      'defaultApp': true,
      'readSms': true,
      'sendSms': true,
      'receiveSms': true,
      'readPhoneState': true,
      'readPhoneNumbers': false,
    });
    expect(access.ready, isTrue);
    expect(access.readPhoneState, isTrue);
    expect(access.readPhoneNumbers, isFalse);
    expect(AccessState.fromMap(null).readPhoneState, isFalse);
    expect(AccessState.fromMap(null).readPhoneNumbers, isFalse);
  });
}
