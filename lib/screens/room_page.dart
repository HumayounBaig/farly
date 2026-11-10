import 'package:flutter/material.dart';

import '../models/farly_device.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import '../widgets/bottom_aligned.dart';
import '../widgets/device_glyph.dart';
import '../widgets/farly_backdrop.dart';
import '../widgets/farly_mark.dart';
import '../widgets/farly_pill.dart';
import '../widgets/farly_press.dart';
import '../widgets/keys.dart';
import '../widgets/scan_orb.dart';
import '../widgets/edit_device_sheet.dart';
import '../widgets/tv_maker_badge.dart';
import 'open_device.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.room, this.sessions});

  final RoomModel room;
  final SessionBuilder? sessions;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  RoomModel get room => widget.room;
  SessionBuilder? get sessions => widget.sessions;

  @override
  void initState() {
    super.initState();
    room.addListener(_reopenLastRemote);
    _reopenLastRemote();
  }

  @override
  void dispose() {
    room.removeListener(_reopenLastRemote);
    super.dispose();
  }

  void _reopenLastRemote() {
    final device = room.takeAutoOpen();
    if (device == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openDevice(context, device, room: room, sessions: sessions);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FarlyBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListenableBuilder(
                listenable: room,
                builder: (context, _) {
                  return Column(
                    children: [
                      _Header(count: room.devices.length),
                      Expanded(
                        child: BottomAligned(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                          children: [
                            if (room.devices.isEmpty)
                              const _EmptyHorizon()
                            else
                              ..._deviceSection(context),
                            if (room.notice != null) ...[
                              const SizedBox(height: 14),
                              _Notice(text: room.notice!),
                            ],
                          ],
                        ),
                      ),
                      _Dock(
                        scanning: room.scanning,
                        onScan: room.scan,
                        onAdd: () => _addByAddress(context),
                        onPreview: () => openDevice(
                          context,
                          FarlyDevice.preview,
                          room: room,
                          sessions: sessions,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _deviceSection(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(
          'ON THIS WI-FI',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      for (final device in room.devices) ...[
        _DeviceCard(
          device: device,
          answered:
              device.lastSeen != null && device.lastSeen == room.lastScanAt,
          onOpen: () =>
              openDevice(context, device, room: room, sessions: sessions),
          onLongPress: () => _deviceActions(context, device),
        ),
        const SizedBox(height: 10),
      ],
      Padding(
        padding: const EdgeInsets.only(left: 4, top: 2),
        child: Text(
          'Hold a device to rename it, change its icon, or forget it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
  }

  Future<void> _deviceActions(BuildContext context, FarlyDevice device) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DeviceActionsSheet(name: device.name),
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      final edited = await showEditDeviceSheet(context, device);
      if (edited != null) await room.updateDevice(edited);
    } else if (action == 'forget') {
      await _forget(context, device);
    }
  }

  Future<void> _addByAddress(BuildContext context) async {
    final device = await showModalBottomSheet<FarlyDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddressSheet(),
    );
    if (device == null) return;
    await room.remember(device);
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

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          const FarlyMark(size: 36),
          const SizedBox(width: 12),
          Text('Farly', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          if (count > 0)
            FarlyPill(
              label: count == 1 ? '1 device' : '$count devices',
              color: FarlyColors.horizon,
              dot: true,
            ),
        ],
      ),
    );
  }
}

class _EmptyHorizon extends StatelessWidget {
  const _EmptyHorizon();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  FarlyColors.horizon.withValues(alpha: 0.18),
                  FarlyColors.horizon.withValues(alpha: 0),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: const FarlyMark(size: 168, background: false),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Find what’s\nacross the room.',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 10),
        Text(
          'One tap looks for televisions and air conditioners on this Wi-Fi.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: FarlyColors.horizon.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FarlyColors.horizon.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: FarlyColors.horizon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _DeviceActionsSheet extends StatelessWidget {
  const _DeviceActionsSheet({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF243731), FarlyColors.night],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: FarlyColors.edge)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: FarlyColors.mist.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            FarlyPress(
              label: 'Rename or change icon',
              icon: Icons.edit_rounded,
              expand: true,
              onPressed: () => Navigator.pop(context, 'edit'),
            ),
            const SizedBox(height: 10),
            FarlyPress(
              label: 'Forget',
              icon: Icons.delete_outline_rounded,
              expand: true,
              onPressed: () => Navigator.pop(context, 'forget'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.answered,
    required this.onOpen,
    required this.onLongPress,
  });

  final FarlyDevice device;
  final bool answered;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ready = device.brand.commandsReady;
    return Pressable(
      onPressed: onOpen,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: FarlySurfaces.glass(),
        child: Row(
          children: [
            DeviceGlyph(device: device),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      device.brand.label,
                      if (device.host != null) device.host!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TvMakerBadge(device: device),
            const SizedBox(width: 8),
            FarlyPill(
              label: ready ? 'Ready' : 'Seen',
              color: ready ? FarlyColors.horizon : FarlyColors.mist,
              dot: answered,
            ),
            const Icon(Icons.chevron_right_rounded, color: FarlyColors.mist),
          ],
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.scanning,
    required this.onScan,
    required this.onAdd,
    required this.onPreview,
  });

  final bool scanning;
  final VoidCallback onScan;
  final VoidCallback onAdd;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: FarlySurfaces.glass(radius: 36),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _DockAction(
              icon: Icons.add_rounded,
              label: 'Add by address',
              onPressed: onAdd,
            ),
          ),
          ScanOrb(scanning: scanning, onPressed: onScan),
          Expanded(
            child: _DockAction(
              icon: Icons.touch_app_rounded,
              label: 'Preview the pad',
              onPressed: onPreview,
            ),
          ),
        ],
      ),
    );
  }
}

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyFace(icon: icon, size: 52, tint: FarlyColors.horizon),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              color: FarlyColors.mist,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
        ],
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF243731), FarlyColors.night],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: FarlyColors.edge)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: FarlyColors.mist.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Add by address',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Find the IP address in the TV’s network settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _Field(
              controller: _address,
              hint: '192.168.1.20',
              icon: Icons.lan_outlined,
            ),
            const SizedBox(height: 10),
            _Field(
              controller: _name,
              hint: 'Name, optional',
              icon: Icons.edit_outlined,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final brand in _manualBrands)
                  _BrandChoice(
                    label: brand.label,
                    selected: _brand == brand,
                    onPressed: () => setState(() => _brand = brand),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: FarlyColors.clay)),
            ],
            const SizedBox(height: 18),
            FarlyPress(
              label: 'Save',
              icon: Icons.check_rounded,
              filled: true,
              expand: true,
              onPressed: _save,
            ),
          ],
        ),
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

class _BrandChoice extends StatelessWidget {
  const _BrandChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: selected
            ? FarlySurfaces.sunPill(radius: 999)
            : BoxDecoration(
                color: const Color(0x0FFFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: FarlyColors.edge),
              ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? FarlyColors.night : FarlyColors.bone,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: FarlyColors.bone),
      cursorColor: FarlyColors.horizon,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: FarlyColors.mist),
        prefixIcon: Icon(icon, color: FarlyColors.mist, size: 20),
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FarlyColors.edge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FarlyColors.horizon),
        ),
      ),
    );
  }
}
