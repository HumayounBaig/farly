import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../control/remote_session.dart';
import '../models/farly_device.dart';
import '../models/remote_action.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../sync/device_sync.dart';
import '../sync/sync_client.dart';
import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import '../widgets/farly_list.dart';
import '../widgets/device_glyph.dart';
import '../widgets/farly_mark.dart';
import '../widgets/horizon_pad.dart';
import '../widgets/keys.dart';
import '../widgets/tv_keyboard_sheet.dart';
import 'companion_menu.dart';

/// Compact remote for the macOS menu-bar popover.
class CompanionPage extends StatefulWidget {
  const CompanionPage({super.key, required this.room, this.sessions});

  final RoomModel room;
  final SessionBuilder? sessions;

  @override
  State<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends State<CompanionPage> {
  RoomModel get room => widget.room;
  RemoteController? _remote;
  final _code = TextEditingController();
  FarlyDevice? _pendingAuto;
  MenuBarIconStyle _menuBarIconStyle = MenuBarIconStyle.monotone;

  @override
  void initState() {
    super.initState();
    room.addListener(_onRoom);
    unawaited(_loadMenuBarIconStyle());
    _pendingAuto = room.takeAutoOpen();
    if (_pendingAuto != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final device = _pendingAuto;
        _pendingAuto = null;
        if (device != null && mounted) unawaited(_open(device));
      });
    }
  }

  Future<void> _loadMenuBarIconStyle() async {
    final style = await getMenuBarIconStyle();
    if (!mounted) return;
    setState(() => _menuBarIconStyle = style);
  }

  Future<void> _setMenuBarIconStyle(MenuBarIconStyle style) async {
    final applied = await setMenuBarIconStyle(style);
    if (!mounted) return;
    setState(() => _menuBarIconStyle = applied);
  }

  @override
  void dispose() {
    room.removeListener(_onRoom);
    _code.dispose();
    _remote?.removeListener(_onRemote);
    _remote?.dispose();
    super.dispose();
  }

  void _onRoom() {
    if (!mounted) return;
    final auto = room.takeAutoOpen();
    if (auto != null && _remote == null) {
      unawaited(_open(auto));
      return;
    }
    setState(() {});
  }

  void _onRemote() {
    if (!mounted) return;
    if (_remote?.phase == SessionPhase.ready) {
      unawaited(room.markConnected(_remote!.device));
    }
    setState(() {});
  }

  Future<void> _open(FarlyDevice device) async {
    _remote?.removeListener(_onRemote);
    _remote?.dispose();
    final remote = RemoteController(
      device: device,
      sessions: widget.sessions,
      onCredentials: room.updateDevice,
      relocate: room.relocate,
    );
    remote.addListener(_onRemote);
    setState(() {
      _remote = remote;
      _code.clear();
    });
    await remote.connect();
  }

  void _closeRemote() {
    _remote?.removeListener(_onRemote);
    _remote?.dispose();
    setState(() => _remote = null);
  }

  List<FarlyDevice> get _controllable {
    final list = room.devicesOnNetwork.isEmpty
        ? room.devices
        : room.devicesOnNetwork;
    return [
      for (final device in list)
        if (device.kind == DeviceKind.screen && device.brand.commandsReady)
          device,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final remote = _remote;
    return Material(
      color: FarlyColors.night,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [FarlyColors.deep, FarlyColors.night],
          ),
        ),
        // Transparent titlebar still reports a top safe inset; ignore it so the
        // pad/chrome aren't crushed under empty chrome space.
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: remote == null ? _picker() : _remotePad(remote),
          ),
        ),
      ),
    );
  }

  Widget _picker() {
    final devices = _controllable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          title: 'Farly',
          subtitle: room.network?.label ?? 'Wi-Fi remote',
        ),
        const SizedBox(height: 10),
        if (room.notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              room.notice!,
              style: const TextStyle(color: FarlyColors.mist, fontSize: 12),
            ),
          ),
        Expanded(
          child: devices.isEmpty
              ? const Center(
                  child: Text(
                    'Scan your Wi-Fi or add a TV by address.\nThe phone app does not need to be open.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FarlyColors.mist, height: 1.35),
                  ),
                )
              : ListView(
                  children: [
                    FarlyListGroup(
                      children: [
                        for (final device in devices)
                          _DeviceTile(
                            device: device,
                            onPressed: () => unawaited(_open(device)),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ActionChip(
                icon: Icons.radar_rounded,
                label: room.scanning ? 'Scanning…' : 'Scan',
                onPressed: room.scanning ? null : () => unawaited(room.scan()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionChip(
                icon: Icons.add_rounded,
                label: 'Add IP',
                onPressed: _addByAddress,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ActionChip(
          icon: Icons.phonelink_rounded,
          label: 'Import from phone',
          onPressed: () => unawaited(_importFromPhone()),
        ),
      ],
    );
  }

  void _openTvKeyboard(RemoteController remote) {
    unawaited(
      showTvKeyboardSheet(
        context: context,
        onSend: remote.sendText,
        failureDetail: () => remote.detail,
        onEnter: remote.textEnter,
        onBackspace: remote.textBackspace,
      ),
    );
  }

  Widget _remotePad(RemoteController remote) {
    final ready =
        remote.phase == SessionPhase.ready ||
        remote.phase == SessionPhase.limited;
    final pairing = remote.phase == SessionPhase.pairing;
    final canType = ready && remote.session.supportsText;
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          if (ready) ...{
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                unawaited(remote.send(RemoteAction.up)),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                unawaited(remote.send(RemoteAction.down)),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                unawaited(remote.send(RemoteAction.left)),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                unawaited(remote.send(RemoteAction.right)),
            const SingleActivator(LogicalKeyboardKey.enter): () =>
                unawaited(remote.send(RemoteAction.select)),
            const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                unawaited(remote.send(RemoteAction.select)),
            const SingleActivator(LogicalKeyboardKey.space): () =>
                unawaited(remote.send(RemoteAction.select)),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                unawaited(remote.send(RemoteAction.back)),
            const SingleActivator(LogicalKeyboardKey.backspace): () =>
                unawaited(remote.send(RemoteAction.back)),
            const SingleActivator(LogicalKeyboardKey.home): () =>
                unawaited(remote.send(RemoteAction.home)),
            const SingleActivator(LogicalKeyboardKey.audioVolumeUp): () =>
                unawaited(remote.send(RemoteAction.volumeUp)),
            const SingleActivator(LogicalKeyboardKey.audioVolumeDown): () =>
                unawaited(remote.send(RemoteAction.volumeDown)),
            const SingleActivator(LogicalKeyboardKey.audioVolumeMute): () =>
                unawaited(remote.send(RemoteAction.mute)),
          },
          if (canType)
            const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () =>
                _openTvKeyboard(remote),
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              title: remote.device.name,
              subtitle: _phaseLabel(remote),
              leading: IconButton(
                tooltip: 'Back to TVs',
                onPressed: _closeRemote,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: FarlyColors.bone,
                ),
              ),
            ),
            if (remote.detail != null && remote.detail!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                remote.detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: FarlyColors.mist, fontSize: 12),
              ),
            ],
            if (pairing) ...[
              const SizedBox(height: 10),
              _pairingRow(remote),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: RoundKey(
                icon: Icons.power_settings_new_rounded,
                label: RemoteAction.power.label,
                size: 48,
                tint: FarlyColors.clay,
                onPressed: ready
                    ? () => unawaited(remote.send(RemoteAction.power))
                    : null,
              ),
            ),
            Expanded(
              child: IgnorePointer(
                ignoring: !ready,
                child: Opacity(
                  opacity: ready ? 1 : 0.45,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _CompanionControls(
                      onSend: remote.send,
                      onTypeOnTv:
                          canType ? () => _openTvKeyboard(remote) : null,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (remote.session.canRetry)
                  Expanded(
                    child: _ActionChip(
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                      onPressed: () => unawaited(remote.retry()),
                    ),
                  ),
                if (remote.session.canRetry) const SizedBox(width: 8),
                if (remote.canPairAgain)
                  Expanded(
                    child: _ActionChip(
                      icon: Icons.lock_reset_rounded,
                      label: 'Pair again',
                      onPressed: () => unawaited(remote.pairAgain()),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pairingRow(RemoteController remote) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: FarlyColors.bone),
            decoration: InputDecoration(
              hintText: 'Code on TV',
              hintStyle: TextStyle(
                color: FarlyColors.mist.withValues(alpha: 0.7),
              ),
              filled: true,
              fillColor: FarlyColors.raised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: FarlyColors.edge),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            onSubmitted: (_) => unawaited(_submitCode(remote)),
          ),
        ),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.check_rounded,
          label: remote.submitting ? '…' : 'Send',
          onPressed: remote.submitting
              ? null
              : () => unawaited(_submitCode(remote)),
        ),
      ],
    );
  }

  Future<void> _submitCode(RemoteController remote) async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    final ok = await remote.submitCode(code);
    if (ok && mounted) _code.clear();
  }

  Widget _header({
    required String title,
    required String subtitle,
    Widget? leading,
  }) {
    return Row(
      children: [
        ?leading,
        const SizedBox(
          width: 28,
          height: 28,
          child: CustomPaint(painter: FarlyMarkPainter()),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: FarlyColors.bone,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: FarlyColors.mist, fontSize: 11),
              ),
            ],
          ),
        ),
        PopupMenuButton<MenuBarIconStyle>(
          tooltip: 'Menu bar icon',
          initialValue: _menuBarIconStyle,
          onSelected: (style) => unawaited(_setMenuBarIconStyle(style)),
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              value: MenuBarIconStyle.monotone,
              checked: _menuBarIconStyle == MenuBarIconStyle.monotone,
              child: const Text('Monotone'),
            ),
            CheckedPopupMenuItem(
              value: MenuBarIconStyle.color,
              checked: _menuBarIconStyle == MenuBarIconStyle.color,
              child: const Text('Color'),
            ),
          ],
          icon: Icon(
            _menuBarIconStyle == MenuBarIconStyle.color
                ? Icons.palette_rounded
                : Icons.contrast_rounded,
            color: FarlyColors.mist,
            size: 20,
          ),
        ),
        IconButton(
          tooltip: 'Quit Farly',
          onPressed: () => unawaited(quitCompanion()),
          icon: const Icon(Icons.power_settings_new_rounded,
              color: FarlyColors.mist, size: 20),
        ),
      ],
    );
  }

  String _phaseLabel(RemoteController remote) {
    return switch (remote.phase) {
      SessionPhase.connecting => 'Connecting…',
      SessionPhase.waitingForTv => 'Waiting for the TV…',
      SessionPhase.pairing => 'Enter the code on the TV',
      SessionPhase.ready => remote.device.brand.label,
      SessionPhase.limited => 'Limited',
      SessionPhase.failed => 'Not connected',
    };
  }

  Future<void> _addByAddress() async {
    final device = await showDialog<FarlyDevice>(
      context: context,
      builder: (context) => const _AddAddressDialog(),
    );
    if (device == null || !mounted) return;
    await room.remember(device);
    await _open(device);
  }

  Future<void> _importFromPhone() async {
    final request = await showDialog<_ImportRequest>(
      context: context,
      builder: (context) => const _ImportPinDialog(),
    );
    if (request == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: FarlyColors.field,
        content: Row(
          children: [
            CircularProgressIndicator(color: FarlyColors.horizon),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Connecting to the phone…',
                style: TextStyle(color: FarlyColors.bone),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await ensureLocalNetworkAccess();
      final payload = await pullDeviceSync(
        pin: request.pin,
        endpoint: request.endpoint,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final result = await room.importSyncPayload(payload);
      if (!mounted) return;
      final auto = room.takeAutoOpen();
      if (auto != null) {
        await _open(auto);
      } else if (result.changed > 0 && _controllable.isNotEmpty) {
        // Stay on the list; notice text already updated.
      }
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: FarlyColors.field,
          title: const Text(
            'Import failed',
            style: TextStyle(color: FarlyColors.bone),
          ),
          content: Text(
            error.toString(),
            style: const TextStyle(color: FarlyColors.mist),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}

class _ImportRequest {
  const _ImportRequest({required this.pin, this.endpoint});
  final String pin;
  final String? endpoint;
}

class _ImportPinDialog extends StatefulWidget {
  const _ImportPinDialog();

  @override
  State<_ImportPinDialog> createState() => _ImportPinDialogState();
}

class _ImportPinDialogState extends State<_ImportPinDialog> {
  final _pin = TextEditingController();
  final _endpoint = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FarlyColors.field,
      title: const Text(
        'Import from phone',
        style: TextStyle(color: FarlyColors.bone),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the code and address shown on the phone’s Share with Mac sheet.',
              style: TextStyle(color: FarlyColors.mist, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                color: FarlyColors.sunrise,
                fontSize: 28,
                letterSpacing: 6,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(color: FarlyColors.mist),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _endpoint,
              keyboardType: TextInputType.text,
              style: const TextStyle(color: FarlyColors.bone, fontSize: 15),
              decoration: const InputDecoration(
                hintText: '192.168.1.20:41234',
                hintStyle: TextStyle(color: FarlyColors.mist),
                labelText: 'Address from phone',
                labelStyle: TextStyle(color: FarlyColors.mist),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: FarlyColors.clay)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Import')),
      ],
    );
  }

  void _submit() {
    final pin = _pin.text.trim();
    final endpoint = _endpoint.text.trim();
    if (pin.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    if (endpoint.isNotEmpty && parseSyncEndpoint(endpoint) == null) {
      setState(() => _error = 'Address must look like 192.168.1.20:41234.');
      return;
    }
    Navigator.pop(
      context,
      _ImportRequest(
        pin: pin,
        endpoint: endpoint.isEmpty ? null : endpoint,
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onPressed});

  final FarlyDevice device;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FarlyListRow(
      leading: DeviceGlyph(device: device, size: 36),
      title: device.name,
      detail: [
        device.brand.label,
        if (device.host != null) device.host!,
      ].join(' · '),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: FarlyColors.mist,
      ),
      onTap: onPressed,
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onPressed,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: FarlySurfaces.glass(radius: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: FarlyColors.horizon),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: FarlyColors.bone,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same control cluster as the phone remote: volume rail + horizon pad + chrome.
class _CompanionControls extends StatelessWidget {
  const _CompanionControls({required this.onSend, this.onTypeOnTv});

  final Future<void> Function(RemoteAction action) onSend;
  final VoidCallback? onTypeOnTv;

  static const _chromeHeight = 62.0;
  static const _minPadHeight = 160.0;
  static const _maxPadHeight = 280.0;

  void _send(RemoteAction action) => unawaited(onSend(action));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - _chromeHeight)
                .clamp(_minPadHeight, _maxPadHeight)
            : 200.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                LevelRail(
                  icon: Icons.volume_up_rounded,
                  label: 'Volume',
                  height: padHeight,
                  width: 44,
                  steps: 2,
                  onIncrease: () => _send(RemoteAction.volumeUp),
                  onDecrease: () => _send(RemoteAction.volumeDown),
                  onIconTap: () => _send(RemoteAction.mute),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: HorizonPad(
                    height: padHeight,
                    onAction: _send,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                RoundKey(
                  icon: Icons.arrow_back_rounded,
                  label: RemoteAction.back.label,
                  size: 48,
                  onPressed: () => _send(RemoteAction.back),
                ),
                RoundKey(
                  icon: Icons.home_rounded,
                  label: RemoteAction.home.label,
                  size: 48,
                  onPressed: () => _send(RemoteAction.home),
                ),
                RoundKey(
                  icon: Icons.menu_rounded,
                  label: RemoteAction.menu.label,
                  size: 48,
                  onPressed: () => _send(RemoteAction.menu),
                ),
                if (onTypeOnTv != null)
                  RoundKey(
                    icon: Icons.keyboard_rounded,
                    label: 'Type on the TV',
                    size: 48,
                    onPressed: onTypeOnTv,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AddAddressDialog extends StatefulWidget {
  const _AddAddressDialog();

  @override
  State<_AddAddressDialog> createState() => _AddAddressDialogState();
}

class _AddAddressDialogState extends State<_AddAddressDialog> {
  final _address = TextEditingController();
  final _name = TextEditingController();
  DeviceBrand _brand = DeviceBrand.roku;
  String? _error;

  static const _brands = [
    DeviceBrand.roku,
    DeviceBrand.samsung,
    DeviceBrand.lg,
    DeviceBrand.androidTv,
  ];

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FarlyColors.field,
      title: const Text('Add by address', style: TextStyle(color: FarlyColors.bone)),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _address,
              style: const TextStyle(color: FarlyColors.bone),
              decoration: const InputDecoration(
                hintText: '192.168.1.20',
                hintStyle: TextStyle(color: FarlyColors.mist),
              ),
            ),
            TextField(
              controller: _name,
              style: const TextStyle(color: FarlyColors.bone),
              decoration: const InputDecoration(
                hintText: 'Name, optional',
                hintStyle: TextStyle(color: FarlyColors.mist),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final brand in _brands)
                  ChoiceChip(
                    label: Text(brand.label),
                    selected: _brand == brand,
                    onSelected: (_) => setState(() => _brand = brand),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: FarlyColors.clay)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
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
