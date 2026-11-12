import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../control/remote_session.dart';
import '../models/farly_device.dart';
import '../models/remote_action.dart';
import '../models/stream_app.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../storage/shortcut_store.dart';
import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import '../widgets/bottom_aligned.dart';
import '../widgets/device_glyph.dart';
import '../widgets/edit_shortcut_sheet.dart';
import '../widgets/farly_backdrop.dart';
import '../widgets/farly_pill.dart';
import '../widgets/farly_press.dart';
import '../widgets/horizon_pad.dart';
import '../widgets/keys.dart';
import '../widgets/menu_probe_sheet.dart';
import '../widgets/stream_mark.dart';
import '../widgets/tv_keyboard_sheet.dart';

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.device,
    required this.room,
    this.sessions,
    this.shortcuts,
  });

  final FarlyDevice device;
  final RoomModel room;
  final SessionBuilder? sessions;
  final ShortcutStore? shortcuts;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  late final RemoteController _remote = RemoteController(
    device: widget.device,
    sessions: widget.sessions,
    onCredentials: widget.room.updateDevice,
    relocate: widget.room.relocate,
  );
  late final ShortcutStore _shortcutStore =
      widget.shortcuts ?? PreferencesShortcutStore();
  List<ShortcutSlot> _slots = ShortcutSlot.defaults;

  @override
  void initState() {
    super.initState();
    _remote.addListener(_rememberWhenReady);
    _remote.connect();
    _loadShortcuts();
  }

  Future<void> _loadShortcuts() async {
    final slots = await _shortcutStore.read();
    if (!mounted) return;
    setState(() => _slots = slots);
  }

  void _rememberWhenReady() {
    if (_remote.phase == SessionPhase.ready) {
      // Use the live device: a Wi-Fi hop may have changed its address/id.
      widget.room.markConnected(_remote.device);
    }
  }

  @override
  void dispose() {
    _remote.removeListener(_rememberWhenReady);
    _remote.dispose();
    super.dispose();
  }

  FarlyDevice get _liveDevice {
    final current = _remote.device;
    for (final device in widget.room.devices) {
      if (device.id == current.id || device.id == widget.device.id) {
        // Prefer the saved row so a rename/icon edit shows up immediately.
        return device;
      }
    }
    return current;
  }

  List<AppShortcut> get _shortcuts {
    final brand = _remote.device.brand;
    if (_remote.session.shortcuts.isEmpty) return const [];
    return [for (final slot in _slots) slot.toShortcut(brand)];
  }

  Future<void> _editShortcut(int index) async {
    if (index < 0 || index >= _slots.length) return;
    final edited = await showEditShortcutSheet(
      context: context,
      slot: _slots[index],
      brand: _remote.device.brand,
      index: index,
    );
    if (edited == null || !mounted) return;
    final next = [..._slots];
    next[index] = edited;
    await _shortcutStore.write(next);
    if (!mounted) return;
    setState(() => _slots = next);
  }

  Widget _key(RemoteAction action, IconData icon, {Color? tint}) {
    return RoundKey(
      key: ValueKey(action),
      icon: icon,
      label: action.label,
      tint: tint ?? FarlyColors.bone,
      onPressed: () => _remote.send(action),
    );
  }

  RockerSegment _segment(RemoteAction action, IconData icon) {
    return RockerSegment(
      id: ValueKey(action),
      icon: icon,
      label: action.label,
      onPressed: () => _remote.send(action),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padHeight = (MediaQuery.sizeOf(context).height * 0.34).clamp(
      220.0,
      300.0,
    );
    return Scaffold(
      body: FarlyBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListenableBuilder(
                listenable: Listenable.merge([_remote, widget.room]),
                builder: (context, _) {
                  final session = _remote.session;
                  final live = _liveDevice;
                  final shortcuts = _shortcuts;
                  final detail = _remote.detail?.trim();
                  final showStatus =
                      detail != null &&
                      detail.isNotEmpty &&
                      detail != 'Connected' &&
                      detail != live.brand.label;
                  final showBrightness = session.supports(
                    RemoteAction.brightnessUp,
                  );
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Row(
                          children: [
                            DeviceGlyph(device: live, size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    live.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    live.brand.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _PhasePill(phase: _remote.phase),
                          ],
                        ),
                      ),
                      if (showStatus)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: _StatusBanner(
                            text: detail,
                            alert: _remote.phase == SessionPhase.failed,
                          ),
                        ),
                      Expanded(
                        child: BottomAligned(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          children: [
                            Row(
                              children: [
                                RoundKey(
                                  icon: Icons.arrow_back_rounded,
                                  label: 'Back to devices',
                                  size: 52,
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                const Spacer(),
                                RoundKey(
                                  key: const ValueKey(RemoteAction.power),
                                  icon: Icons.power_settings_new_rounded,
                                  label: RemoteAction.power.label,
                                  size: 52,
                                  tint: FarlyColors.clay,
                                  onPressed: () =>
                                      _remote.send(RemoteAction.power),
                                ),
                              ],
                            ),
                            if (shortcuts.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  for (var i = 0; i < shortcuts.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 10),
                                    Expanded(
                                      child: _ShortcutButton(
                                        shortcut: shortcuts[i],
                                        onPressed: () =>
                                            _remote.launch(shortcuts[i]),
                                        onLongPress: () =>
                                            _editShortcut(i),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Hold an app button to change it.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (_remote.phase == SessionPhase.pairing) ...[
                              const SizedBox(height: 16),
                              _PairPanel(
                                busy: _remote.submitting,
                                onSubmit: _remote.submitCode,
                              ),
                            ],
                            if (_remote.phase == SessionPhase.failed &&
                                session.canRetry) ...[
                              const SizedBox(height: 16),
                              FarlyPress(
                                label: 'Try again',
                                icon: Icons.refresh_rounded,
                                expand: true,
                                onPressed: _remote.retry,
                              ),
                            ],
                            const SizedBox(height: 16),
                            KeyRocker(
                              segments: [
                                _segment(
                                  RemoteAction.rewind,
                                  Icons.fast_rewind_rounded,
                                ),
                                _segment(
                                  RemoteAction.play,
                                  Icons.play_arrow_rounded,
                                ),
                                _segment(
                                  RemoteAction.forward,
                                  Icons.fast_forward_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                if (!showBrightness) const Spacer(),
                                Expanded(
                                  flex: showBrightness ? 1 : 2,
                                  child: LevelRail(
                                    icon: Icons.volume_up_rounded,
                                    label: 'Volume',
                                    onIncrease: () =>
                                        _remote.send(RemoteAction.volumeUp),
                                    onDecrease: () =>
                                        _remote.send(RemoteAction.volumeDown),
                                    onIconTap: () =>
                                        _remote.send(RemoteAction.mute),
                                    increaseKey: const ValueKey(
                                      RemoteAction.volumeUp,
                                    ),
                                    decreaseKey: const ValueKey(
                                      RemoteAction.volumeDown,
                                    ),
                                    iconKey: const ValueKey(RemoteAction.mute),
                                  ),
                                ),
                                if (showBrightness) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: LevelRail(
                                      icon: Icons.wb_sunny_rounded,
                                      label: 'Brightness',
                                      onIncrease: () => _remote.send(
                                        RemoteAction.brightnessUp,
                                      ),
                                      onDecrease: () => _remote.send(
                                        RemoteAction.brightnessDown,
                                      ),
                                      increaseKey: const ValueKey(
                                        RemoteAction.brightnessUp,
                                      ),
                                      decreaseKey: const ValueKey(
                                        RemoteAction.brightnessDown,
                                      ),
                                    ),
                                  ),
                                ] else
                                  const Spacer(),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _key(RemoteAction.back, Icons.undo_rounded),
                                _key(RemoteAction.home, Icons.home_rounded),
                                if (session.supports(RemoteAction.menu))
                                  _key(
                                    RemoteAction.menu,
                                    Icons.menu_rounded,
                                  ),
                                if (session.supportsText)
                                  RoundKey(
                                    icon: Icons.keyboard_rounded,
                                    label: 'Type on the TV',
                                    onPressed: () => showTvKeyboardSheet(
                                      context: context,
                                      onSend: _remote.sendText,
                                      onEnter: _remote.textEnter,
                                      onBackspace: _remote.textBackspace,
                                    ),
                                  ),
                                if (session.supports(RemoteAction.input))
                                  _key(
                                    RemoteAction.input,
                                    Icons.input_rounded,
                                  ),
                              ],
                            ),
                            if (session.supportsMenuProbes) ...[
                              const SizedBox(height: 8),
                              Center(
                                child: Pressable(
                                  label: 'Menu not working? Try other keys',
                                  onPressed: () async {
                                    final chosen = await showMenuProbeSheet(
                                      context: context,
                                      device: _liveDevice,
                                      onTry: _remote.sendMenuProbe,
                                    );
                                    if (chosen == null || !mounted) return;
                                    _remote.setMenuCommand(chosen);
                                  },
                                  child: Text(
                                    'Menu not working?',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: FarlyColors.horizon,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            HorizonPad(
                              height: padHeight,
                              onAction: _remote.send,
                            ),
                          ],
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
}

class _PairPanel extends StatefulWidget {
  const _PairPanel({required this.busy, required this.onSubmit});

  final bool busy;
  final Future<bool> Function(String code) onSubmit;

  @override
  State<_PairPanel> createState() => _PairPanelState();
}

class _PairPanelState extends State<_PairPanel> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.busy) return;
    final ok = await widget.onSubmit(_code.text);
    if (!ok && mounted) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: FarlySurfaces.glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pair with the TV',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Type the 6-character code on the TV screen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pairing-code'),
            controller: _code,
            autofocus: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
              TextInputFormatter.withFunction(
                (_, next) => next.copyWith(text: next.text.toUpperCase()),
              ),
            ],
            onSubmitted: (_) => _submit(),
            style: const TextStyle(
              color: FarlyColors.bone,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 8,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            cursorColor: FarlyColors.horizon,
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: const TextStyle(color: FarlyColors.mist),
              filled: true,
              fillColor: const Color(0x14FFFFFF),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: FarlyColors.edge),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: FarlyColors.horizon),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FarlyPress(
            label: widget.busy ? 'Pairing' : 'Pair',
            icon: Icons.link_rounded,
            filled: true,
            expand: true,
            onPressed: widget.busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({required this.phase});

  final SessionPhase phase;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (phase) {
      SessionPhase.connecting => ('Connecting', FarlyColors.mist),
      SessionPhase.waitingForTv => ('Check the TV', FarlyColors.horizon),
      SessionPhase.pairing => ('Pairing', FarlyColors.horizon),
      SessionPhase.ready => ('Connected', FarlyColors.leaf),
      SessionPhase.limited => ('Limited', FarlyColors.mist),
      SessionPhase.failed => ('Offline', FarlyColors.clay),
    };
    return FarlyPill(label: label, color: color, dot: true);
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.text, this.alert = false});

  final String text;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final color = alert ? FarlyColors.clay : FarlyColors.horizon;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        softWrap: true,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: FarlyColors.bone,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.shortcut,
    required this.onPressed,
    required this.onLongPress,
  });

  final AppShortcut shortcut;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final tint = shortcut.tint ?? FarlyColors.horizon;
    final mark = shortcut.mark ?? shortcut.label.characters.first;
    return Pressable(
      onPressed: onPressed,
      onLongPress: onLongPress,
      label: shortcut.label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: FarlySurfaces.glass(radius: 20),
        child: Row(
          children: [
            StreamMark(mark: mark, tint: tint, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                shortcut.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: FarlyColors.bone,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
