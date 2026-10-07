import '../models/farly_device.dart';
import 'lg_session.dart';
import 'remote_session.dart';
import 'roku_session.dart';
import 'samsung_session.dart';
import 'session_for_brand.dart';

RemoteSession buildSession(FarlyDevice device, CredentialSink onCredentials) {
  return switch (device.brand) {
    DeviceBrand.roku => RokuSession(device: device),
    DeviceBrand.samsung => SamsungSession(
      device: device,
      onCredentials: onCredentials,
    ),
    DeviceBrand.lg => LgSession(device: device, onCredentials: onCredentials),
    _ => sessionForBrand(device),
  };
}
