import 'package:flutter/material.dart';

import '../models/farly_device.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../storage/layout_store.dart';
import '../storage/shortcut_store.dart';
import 'climate_page.dart';
import 'remote_page.dart';

void openDevice(
  BuildContext context,
  FarlyDevice device, {
  required RoomModel room,
  SessionBuilder? sessions,
  ShortcutStore? shortcuts,
  LayoutStore? layout,
}) {
  final page = device.kind == DeviceKind.climate
      ? ClimatePage(device: device)
      : RemotePage(
          device: device,
          room: room,
          sessions: sessions,
          shortcuts: shortcuts,
          layout: layout,
        );
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
