import 'package:flutter/material.dart';

import '../models/device_icon.dart';
import '../models/farly_device.dart';
import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';

class DeviceGlyph extends StatelessWidget {
  const DeviceGlyph({super.key, required this.device, this.size = 48});

  final FarlyDevice device;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ready =
        device.brand.commandsReady || device.brand == DeviceBrand.preview;
    final chosen =
        DeviceIcon.byId(device.icon) ??
        DeviceIcon.byId(DeviceIcon.suggestedId(device));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: FarlyColors.raised.withValues(alpha: ready ? 0.95 : 0.7),
        border: Border.all(color: FarlyColors.edge),
        boxShadow: FarlySurfaces.shadow,
      ),
      alignment: Alignment.center,
      child: _face(chosen, ready),
    );
  }

  Widget _face(DeviceIcon? chosen, bool ready) {
    final ink = ready ? FarlyColors.bone : FarlyColors.mist;
    if (chosen?.emoji != null) {
      return Text(chosen!.emoji!, style: TextStyle(fontSize: size * 0.52));
    }
    if (chosen?.brand != null) {
      final short = chosen!.brand!.length <= 3
          ? chosen.brand!
          : chosen.brand!.substring(0, 1);
      return Text(
        short,
        style: TextStyle(
          color: ink,
          fontSize: short.length > 2 ? size * 0.28 : size * 0.42,
          fontWeight: FontWeight.w800,
          letterSpacing: short.length > 2 ? 0.4 : 0,
          height: 1,
        ),
      );
    }
    final icon = switch ((device.kind, device.brand)) {
      (DeviceKind.climate, _) => Icons.ac_unit_rounded,
      (_, DeviceBrand.preview) => Icons.touch_app_rounded,
      _ => Icons.tv_rounded,
    };
    return Icon(icon, size: size * 0.56, color: ink);
  }
}
