import 'package:flutter/material.dart';

import '../models/farly_device.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../theme/farly_colors.dart';
import '../widgets/farly_press.dart';
import '../widgets/scan_button.dart';
import 'climate_page.dart';
import 'remote_page.dart';

class RoomPage extends StatelessWidget {
  const RoomPage({
    super.key,
    required this.room,
    this.sessions,
  });

  final RoomModel room;
  final SessionBuilder? sessions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListenableBuilder(
              listenable: room,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  children: [
                    Text('Farly', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Across the room',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    ScanButton(
                      scanning: room.scanning,
                      onPressed: room.scan,
                    ),
                    if (room.notice != null) ...[
                      const SizedBox(height: 14),
                      Text(room.notice!, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 22),
                    _DeviceList(room: room, sessions: sessions),
                    const SizedBox(height: 12),
                    FarlyPress(
                      label: 'Add by address',
                      onPressed: () => _addByAddress(context),
                    ),
                    const SizedBox(height: 8),
                    FarlyPress(
                      label: 'Preview the pad',
                      onPressed: () => _open(context, FarlyDevice.preview),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addByAddress(BuildContext context) async {
    final device = await showModalBottomSheet<FarlyDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FarlyColors.field,
      builder: (context) => const _AddressSheet(),
    );
    if (device == null) return;
    await room.remember(device);
  }

  void _open(BuildContext context, FarlyDevice device) {
    final page = device.kind == DeviceKind.climate
        ? ClimatePage(device: device)
        : RemotePage(device: device, room: room, sessions: sessions);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.room, required this.sessions});

  final RoomModel room;
  final SessionBuilder? sessions;

  @override
  Widget build(BuildContext context) {
    if (room.devices.isEmpty) {
      return Text(
        'One tap looks for televisions and air conditioners on this Wi-Fi.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      children: [
        for (final device in room.devices) ...[
          _DeviceCard(
            device: device,
            answered: device.lastSeen != null && device.lastSeen == room.lastScanAt,
            onOpen: () => _open(context, device),
            onForget: () => _forget(context, device),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  void _open(BuildContext context, FarlyDevice device) {
    final page = device.kind == DeviceKind.climate
        ? ClimatePage(device: device)
        : RemotePage(device: device, room: room, sessions: sessions);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _forget(BuildContext context, FarlyDevice device) async {
    final forget = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${device.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (forget == true) await room.forget(device);
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.answered,
    required this.onOpen,
    required this.onForget,
  });

  final FarlyDevice device;
  final bool answered;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final ready = device.brand.commandsReady;
    return Material(
      color: FarlyColors.field,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpen,
        onLongPress: onForget,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 42,
                color: ready ? FarlyColors.horizon : FarlyColors.mist,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      [
                        device.brand.label,
                        if (device.host != null) device.host!,
                        if (answered) 'Answered',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressSheet extends StatefulWidget {
  const _AddressSheet();

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  final _address = TextEditingController();
  final _name = TextEditingController();
  DeviceBrand _brand = DeviceBrand.roku;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add by address', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          _Field(controller: _address, hint: '192.168.1.20'),
          const SizedBox(height: 10),
          _Field(controller: _name, hint: 'Name, optional'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final brand in _manualBrands)
                ChoiceChip(
                  label: Text(brand.label),
                  selected: _brand == brand,
                  onSelected: (_) => setState(() => _brand = brand),
                  selectedColor: FarlyColors.horizon,
                  labelStyle: TextStyle(
                    color: _brand == brand ? FarlyColors.night : FarlyColors.bone,
                  ),
                  backgroundColor: FarlyColors.raised,
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: FarlyColors.clay)),
          ],
          const SizedBox(height: 16),
          FarlyPress(label: 'Save', filled: true, expand: true, onPressed: _save),
        ],
      ),
    );
  }

  void _save() {
    final host = _address.text.trim();
    if (!isIpv4Address(host)) {
      setState(() => _error = 'Enter an IPv4 address.');
      return;
    }
    final name = _name.text.trim();
    Navigator.pop(
      context,
      FarlyDevice(
        id: FarlyDevice.idFor(_brand, host),
        name: name.isEmpty ? _brand.label : name,
        kind: _brand.kind,
        brand: _brand,
        host: host,
        port: _brand.defaultPort,
        source: 'manual',
      ),
    );
  }
}

const _manualBrands = [
  DeviceBrand.roku,
  DeviceBrand.samsung,
  DeviceBrand.lg,
  DeviceBrand.androidTv,
  DeviceBrand.appleTv,
  DeviceBrand.broadlink,
];

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: FarlyColors.bone),
      cursorColor: FarlyColors.horizon,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: FarlyColors.mist),
        filled: true,
        fillColor: FarlyColors.raised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
