import '../models/farly_device.dart';
import 'android_tv_session.dart';
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
    // Google TV sets such as TCL often announce only Cast, so try the
    // Android TV remote for Cast devices too.
    DeviceBrand.androidTv || DeviceBrand.chromecast => AndroidTvSession(
      device: device,
      onCredentials: onCredentials,
    ),
    _ => sessionForBrand(device),
  };
}
