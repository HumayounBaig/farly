import '../models/farly_device.dart';
import 'remote_session.dart';
import 'session_for_brand.dart';

RemoteSession buildSession(FarlyDevice device, CredentialSink onCredentials) {
  return sessionForBrand(device);
}
