import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../models/farly_device.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../storage/layout_store.dart';
import '../storage/shortcut_store.dart';
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
import '../widgets/farly_list.dart';
import '../widgets/share_devices_sheet.dart';
import '../widgets/tv_maker_badge.dart';
import 'feedback_page.dart';
import 'open_device.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({
    super.key,
    required this.room,
    this.sessions,
    this.shortcuts,
    this.layout,
  });

  final RoomModel room;
  final SessionBuilder? sessions;
  final ShortcutStore? shortcuts;
  final LayoutStore? layout;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with WidgetsBindingObserver {
  RoomModel get room => widget.room;
  SessionBuilder? get sessions => widget.sessions;
  ShortcutStore? get shortcuts => widget.shortcuts;
  LayoutStore? get layout => widget.layout;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    room.addListener(_reopenLastRemote);
    _reopenLastRemote();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    room.removeListener(_reopenLastRemote);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(room.refreshNetwork());
    }
  }

  void _reopenLastRemote() {
    final device = room.takeAutoOpen();
    if (device == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openDevice(
        context,
        device,
        room: room,
        sessions: sessions,
        shortcuts: shortcuts,
        layout: layout,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _SavedDevicesDrawer(
        room: room,
        onOpen: (device) {
          Navigator.pop(context);
          openDevice(
            context,
            device,
            room: room,
            sessions: sessions,
            shortcuts: shortcuts,
            layout: layout,
          );
        },
        onEdit: (device) async {
          Navigator.pop(context);
          await _editDevice(context, device);
        },
        onForget: (device) async {
          Navigator.pop(context);
          await _forget(context, device);
        },
        onShareWithMac: () {
          Navigator.pop(context);
          unawaited(showShareDevicesSheet(context, room));
        },
        onFeedback: () {
          Navigator.pop(context);
          unawaited(
            Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const FeedbackPage()),
            ),
          );
        },
      ),
      body: FarlyBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListenableBuilder(
                listenable: room,
                builder: (context, _) {
                  final onNetwork = room.devicesOnNetwork;
                  return Column(
                    children: [
                      _Header(
                        count: onNetwork.length,
                        networkLabel: room.network?.label,
                        onOpenSaved: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                      ),
                      Expanded(
                        child: BottomAligned(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                          children: [
                            // Subtle progress line while a scan runs; the orb's rings alone are easy to miss.
                            if (room.scanning &&
                                !MediaQuery.disableAnimationsOf(context))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: const LinearProgressIndicator(
                                    key: Key('scan-progress'),
                                    minHeight: 2,
                                    color: FarlyColors.horizon,
                                    backgroundColor: Colors.transparent,
                                  ),
                                ),
                              ),
                            if (onNetwork.isEmpty)
                              room.devices.isEmpty
                                  ? const _EmptyHorizon()
                                  : _EmptyOnNetwork(
                                      savedCount: room.devices.length,
                                      onOpenSaved: () => _scaffoldKey
                                          .currentState
                                          ?.openDrawer(),
                                    )
                            else
                              ..._deviceSection(context, onNetwork),
                            if (room.devices.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _AllSavedButton(
                                total: room.devices.length,
                                elsewhere: room.devicesElsewhere.length,
                                onPressed: () =>
                                    _scaffoldKey.currentState?.openDrawer(),
                              ),
                            ],
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
                          shortcuts: shortcuts,
                          layout: layout,
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

  List<Widget> _deviceSection(BuildContext context, List<FarlyDevice> devices) {
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(
          'ON THIS WI-FI',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      for (final device in _sorted(devices)) ...[
        _DeviceCard(
          device: device,
          lastUsed: device.id == room.lastConnectedId,
          answered:
              device.lastSeen != null && device.lastSeen == room.lastScanAt,
          onOpen: () => openDevice(
            context,
            device,
            room: room,
            sessions: sessions,
            shortcuts: shortcuts,
            layout: layout,
          ),
          onEdit: () => _editDevice(context, device),
          onLongPress: () => _deviceActions(context, device),
        ),
        const SizedBox(height: 10),
      ],
      Padding(
        padding: const EdgeInsets.only(left: 4, top: 2),
        child: Text(
          'Tap the pencil or hold a device to rename it, change its icon, or delete it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
  }

  /// Last used first, then paired TVs, then by brand. Wi-Fi cannot tell which
  /// TV is physically nearest, so nothing here pretends to.
  List<FarlyDevice> _sorted(List<FarlyDevice> devices) {
    int weight(FarlyDevice d) => d.id == room.lastConnectedId
        ? 0
        : (d.token != null || d.clientKey != null ? 1 : 2);
    return [...devices]..sort((a, b) {
      final byWeight = weight(a).compareTo(weight(b));
      return byWeight != 0 ? byWeight : a.brand.rank.compareTo(b.brand.rank);
    });
  }

  Future<void> _editDevice(BuildContext context, FarlyDevice device) async {
    final edited = await showEditDeviceSheet(context, device);
    if (edited != null) await room.updateDevice(edited);
  }

  Future<void> _deviceActions(BuildContext context, FarlyDevice device) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DeviceActionsSheet(name: device.name),
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      await _editDevice(context, device);
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
        title: Text('Delete ${device.name}?'),
        content: const Text(
          'Removes this TV from Farly on your phone. You can add it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (forget == true) await room.forget(device);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.onOpenSaved,
    this.networkLabel,
  });

  final int count;
  final String? networkLabel;
  final VoidCallback onOpenSaved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'All saved devices',
            onPressed: onOpenSaved,
            icon: const Icon(Icons.menu_rounded),
          ),
          const FarlyMark(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Farly', style: Theme.of(context).textTheme.titleLarge),
                if (networkLabel != null)
                  Text(
                    networkLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
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

class _AllSavedButton extends StatelessWidget {
  const _AllSavedButton({
    required this.total,
    required this.elsewhere,
    required this.onPressed,
  });

  final int total;
  final int elsewhere;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final detail = elsewhere == 0
        ? (total == 1 ? '1 saved device' : '$total saved devices')
        : elsewhere == 1
        ? '$total saved · 1 on another Wi‑Fi'
        : '$total saved · $elsewhere on other Wi‑Fi';
    return Pressable(
      label: 'All saved devices',
      onPressed: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: FarlySurfaces.glass(radius: 20),
        child: Row(
          children: [
            const Icon(Icons.folder_open_rounded, color: FarlyColors.horizon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All saved devices',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: FarlyColors.mist),
          ],
        ),
      ),
    );
  }
}

class _EmptyOnNetwork extends StatelessWidget {
  const _EmptyOnNetwork({required this.savedCount, required this.onOpenSaved});

  final int savedCount;
  final VoidCallback onOpenSaved;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nothing on this Wi‑Fi yet.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          savedCount == 1
              ? '1 saved device is on another network. Open the sidebar to delete or open it anyway.'
              : '$savedCount saved devices are on another network. Open the sidebar to delete or open them anyway.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        FarlyPress(
          label: 'All saved devices',
          icon: Icons.folder_open_rounded,
          onPressed: onOpenSaved,
        ),
      ],
    );
  }
}

class _SavedDevicesDrawer extends StatelessWidget {
  const _SavedDevicesDrawer({
    required this.room,
    required this.onOpen,
    required this.onEdit,
    required this.onForget,
    required this.onShareWithMac,
    required this.onFeedback,
  });

  final RoomModel room;
  final ValueChanged<FarlyDevice> onOpen;
  final ValueChanged<FarlyDevice> onEdit;
  final ValueChanged<FarlyDevice> onForget;
  final VoidCallback onShareWithMac;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: FarlyColors.night,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: room,
          builder: (context, _) {
            final here = room.devicesOnNetwork;
            final elsewhere = room.devicesElsewhere;
            final total = room.devices.length;
            final network = room.network;
            // A bare subnet ("192.168.0.x") means no Wi-Fi name is known.
            final wifi = network == null
                ? null
                : (network.ssidKey == null ? 'This Wi‑Fi' : network.label);
            Widget group(List<FarlyDevice> devices, bool onNetwork) {
              return FarlyListGroup(
                children: [
                  for (final device in devices)
                    _DrawerDeviceTile(
                      device: device,
                      onNetwork: onNetwork,
                      onOpen: () => onOpen(device),
                      onEdit: () => onEdit(device),
                      onForget: () => onForget(device),
                    ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Saved TVs',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    total == 0
                        ? 'Nothing saved yet'
                        : [?wifi, '${here.length} here'].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: total == 0
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Scan or add a TV to keep it here across Wi‑Fi networks.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            if (here.isNotEmpty) ...[
                              _DrawerSectionLabel('On this Wi‑Fi'),
                              group(here, true),
                            ],
                            if (elsewhere.isNotEmpty) ...[
                              _DrawerSectionLabel('Other Wi‑Fi'),
                              group(elsewhere, false),
                            ],
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: FarlyListGroup(
                    children: [
                      if (!kIsWeb &&
                          (defaultTargetPlatform == TargetPlatform.iOS ||
                              defaultTargetPlatform == TargetPlatform.android))
                        FarlyListRow(
                          leading: const Icon(
                            Icons.laptop_mac_rounded,
                            color: FarlyColors.mist,
                          ),
                          title: 'Share with Mac',
                          muted: total == 0,
                          onTap: total == 0 ? null : onShareWithMac,
                        ),
                      FarlyListRow(
                        leading: const Icon(
                          Icons.feedback_outlined,
                          color: FarlyColors.mist,
                        ),
                        title: 'Send feedback',
                        onTap: onFeedback,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

String _elsewhereSubtitle(FarlyDevice device) {
  for (final key in device.networkKeys) {
    if (key.startsWith('ssid:') && key.length > 5) {
      return 'Saved on ${key.substring(5)}';
    }
  }
  return 'Not on this Wi‑Fi';
}

class _DrawerDeviceTile extends StatelessWidget {
  const _DrawerDeviceTile({
    required this.device,
    required this.onNetwork,
    required this.onOpen,
    required this.onEdit,
    required this.onForget,
  });

  final FarlyDevice device;
  final bool onNetwork;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onForget;

  Future<void> _actions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DeviceActionsSheet(name: device.name),
    );
    if (action == 'edit') onEdit();
    if (action == 'forget') onForget();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Edit'): onEdit,
        const CustomSemanticsAction(label: 'Delete'): onForget,
      },
      child: Dismissible(
        key: ValueKey(device.id),
        direction: DismissDirection.endToStart,
        // Never actually dismissed: the swipe hands off to the delete confirm.
        confirmDismiss: (_) async {
          onForget();
          return false;
        },
        background: Container(
          color: FarlyColors.clay.withValues(alpha: 0.25),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: FarlyColors.bone,
          ),
        ),
        child: FarlyListRow(
          leading: Opacity(
            opacity: onNetwork ? 1 : 0.55,
            child: DeviceGlyph(device: device, size: 36),
          ),
          title: device.name,
          detail: onNetwork ? device.brand.label : _elsewhereSubtitle(device),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: FarlyColors.mist,
          ),
          onTap: onOpen,
          onLongPress: () => _actions(context),
        ),
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
              label: 'Delete',
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
    required this.lastUsed,
    required this.onOpen,
    required this.onEdit,
    required this.onLongPress,
  });

  final FarlyDevice device;
  final bool answered;
  final bool lastUsed;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ready = device.brand.commandsReady;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: FarlySurfaces.glass(),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              onPressed: onOpen,
              onLongPress: onLongPress,
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
                            if (lastUsed) 'Last used',
                            if (device.token != null ||
                                device.clientKey != null)
                              'Paired before',
                            if (kDebugMode && device.host != null) device.host!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Pressable(
            onPressed: onEdit,
            label: 'Edit ${device.name}',
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.edit_outlined,
                size: 20,
                color: FarlyColors.mist,
              ),
            ),
          ),
          TvMakerBadge(device: device),
          const SizedBox(width: 6),
          FarlyPill(
            label: ready ? 'Ready' : 'Seen',
            color: ready ? FarlyColors.horizon : FarlyColors.mist,
            dot: answered,
          ),
          const Icon(Icons.chevron_right_rounded, color: FarlyColors.mist),
        ],
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
