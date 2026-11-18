import 'device_sync.dart';

class FarlySyncServer {
  const FarlySyncServer();

  String get pin => '';
  int? get port => null;
  String? get host => null;
  String? get endpointLabel => null;
  bool get isRunning => false;
  bool get isAdvertising => false;

  Future<void> start(DeviceSyncPayload payload) async {
    throw UnsupportedError('Device sync needs the iOS or Android app.');
  }

  Future<void> stop() async {}
}

String generateSyncPin() => '000000';
