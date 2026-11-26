import 'device_sync.dart';

class FarlySyncServer {
  const FarlySyncServer();

  String get pin => '';
  int? get port => null;
  String? get host => null;
  String? get endpointLabel => null;
  bool get isRunning => false;
  bool get isAdvertising => false;

  Future<void> start(
    DeviceSyncPayload payload, {
    Duration ttl = const Duration(minutes: 2),
  }) async {
    throw UnsupportedError('Device sync needs the iOS or Android app.');
  }

  Future<void> stop() async {}
}

String generateSyncPin() => '000000';

const maxSyncPinFailures = 5;

bool constantTimeEquals(String a, String b) => a == b;
