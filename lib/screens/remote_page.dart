import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../control/remote_session.dart';
import '../models/farly_device.dart';
import '../models/remote_action.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import '../widgets/bottom_aligned.dart';
import '../widgets/device_glyph.dart';
import '../widgets/farly_backdrop.dart';
import '../widgets/farly_pill.dart';
import '../widgets/farly_press.dart';
import '../widgets/horizon_pad.dart';
import '../widgets/keys.dart';
import '../widgets/tv_keyboard_sheet.dart';

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.device,
    required this.room,
    this.sessions,
  });

  final FarlyDevice device;
  final RoomModel room;
  final SessionBuilder? sessions;

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

  @override
  void initState() {
    super.initState();
    _remote.addListener(_rememberWhenReady);
    _remote.connect();
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
                listenable: _remote,
                builder: (context, _) {
                  final session = _remote.session;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Row(
                          children: [
                            DeviceGlyph(device: widget.device, size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.device.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _remote.detail ?? widget.device.brand.label,
                                    maxLines: 2,
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
                            if (session.shortcuts.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  for (final shortcut in session.shortcuts) ...[
                                    if (shortcut != session.shortcuts.first)
                                      const SizedBox(width: 10),
                                    Expanded(
                                      child: FarlyPress(
                                        label: shortcut.label,
                                        icon: Icons.play_circle_outline_rounded,
                                        onPressed: () =>
                                            _remote.launch(shortcut),
                                      ),
                                    ),
                                  ],
                                ],
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
                            HorizonPad(
                              height: padHeight,
                              onAction: _remote.send,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _key(RemoteAction.back, Icons.undo_rounded),
                                _key(RemoteAction.home, Icons.home_rounded),
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
                                  _key(RemoteAction.input, Icons.input_rounded),
                              ],
                            ),
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
                            const SizedBox(height: 12),
                            KeyRocker(
                              segments: [
                                _segment(
                                  RemoteAction.volumeDown,
                                  Icons.remove_rounded,
                                ),
                                _segment(
                                  RemoteAction.mute,
                                  Icons.volume_off_rounded,
                                ),
                                _segment(
                                  RemoteAction.volumeUp,
                                  Icons.add_rounded,
                                ),
                              ],
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
