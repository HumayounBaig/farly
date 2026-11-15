import 'package:flutter/material.dart';

import 'screens/room_page.dart';
import 'state/remote_controller.dart';
import 'state/room_model.dart';
import 'storage/device_store.dart';
import 'storage/layout_store.dart';
import 'storage/shortcut_store.dart';
import 'theme/farly_theme.dart';
import 'models/farly_device.dart';

class FarlyApp extends StatefulWidget {
  const FarlyApp({
    super.key,
    this.store,
    this.scanDevices,
    this.readNetwork,
    this.sessions,
    this.shortcuts,
    this.layout,
  });

  final DeviceStore? store;
  final Future<List<FarlyDevice>> Function()? scanDevices;
  final NetworkReader? readNetwork;
  final SessionBuilder? sessions;
  final ShortcutStore? shortcuts;
  final LayoutStore? layout;

  @override
  State<FarlyApp> createState() => _FarlyAppState();
}

class _FarlyAppState extends State<FarlyApp> {
  late final RoomModel room = RoomModel(
    store: widget.store ?? PreferencesDeviceStore(),
    scanDevices: widget.scanDevices,
    readNetwork: widget.readNetwork,
  );

  @override
  void initState() {
    super.initState();
    room.load();
  }

  @override
  void dispose() {
    room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Farly',
      debugShowCheckedModeBanner: false,
      theme: farlyTheme(),
      home: RoomPage(
        room: room,
        sessions: widget.sessions,
        shortcuts: widget.shortcuts,
        layout: widget.layout,
      ),
    );
  }
}
