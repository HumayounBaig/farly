import 'package:flutter/material.dart';

import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../storage/device_store.dart';
import '../theme/farly_theme.dart';
import '../models/farly_device.dart';
import 'companion_page.dart';

/// Menu-bar Farly: talks to TVs on Wi-Fi directly (no phone relay).
class FarlyCompanionApp extends StatefulWidget {
  const FarlyCompanionApp({
    super.key,
    this.store,
    this.scanDevices,
    this.readNetwork,
    this.sessions,
  });

  final DeviceStore? store;
  final Future<List<FarlyDevice>> Function()? scanDevices;
  final NetworkReader? readNetwork;
  final SessionBuilder? sessions;

  @override
  State<FarlyCompanionApp> createState() => _FarlyCompanionAppState();
}

class _FarlyCompanionAppState extends State<FarlyCompanionApp> {
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
      home: CompanionPage(room: room, sessions: widget.sessions),
    );
  }
}
