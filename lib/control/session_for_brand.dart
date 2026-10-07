import '../models/farly_device.dart';
import 'remote_session.dart';

RemoteSession sessionForBrand(FarlyDevice device) {
  if (device.brand == DeviceBrand.preview) {
    return NotedSession(
      phase: SessionPhase.limited,
      detail: 'Preview. Nothing is connected.',
      preview: true,
    );
  }
  final limitation = device.brand.limitation;
  if (limitation == null) {
    return NotedSession(
      phase: SessionPhase.limited,
      detail: 'Farly does not have a control path for this device yet.',
    );
  }
  return NotedSession(phase: SessionPhase.limited, detail: limitation);
}
