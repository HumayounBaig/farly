import 'device_sync.dart';

Future<DeviceSyncPayload> pullDeviceSync({
  required String pin,
  String? endpoint,
  Duration timeout = const Duration(seconds: 10),
}) async {
  throw UnsupportedError('Device sync needs the Mac, iOS, or Android app.');
}
