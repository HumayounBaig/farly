import 'package:farly/models/remote_action.dart';
import 'package:farly/widgets/phone_volume_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone volume bridge stays idle under the test binding', (
    tester,
  ) async {
    expect(PhoneVolumeBridge.supported, isFalse);
    final sent = <RemoteAction>[];
    final bridge = PhoneVolumeBridge(onAction: sent.add);
    await bridge.start();
    await bridge.stop();
    expect(sent, isEmpty);
  });
}
