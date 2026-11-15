import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../control/remote_session.dart';
import '../models/farly_device.dart';
import '../models/remote_action.dart';
import '../models/remote_layout.dart';
import '../models/stream_app.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../storage/layout_store.dart';
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
import '../widgets/jiggle.dart';
import '../widgets/keys.dart';
import '../widgets/menu_probe_sheet.dart';
import '../widgets/phone_volume_bridge.dart';
import '../widgets/stream_mark.dart';
import '../widgets/tv_keyboard_sheet.dart';

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.device,
    required this.room,
    this.sessions,
    this.shortcuts,
    this.layout,
  });

  final FarlyDevice device;
  final RoomModel room;
  final SessionBuilder? sessions;
  final ShortcutStore? shortcuts;
  final LayoutStore? layout;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  late final RemoteController _remote = RemoteController(
    device: widget.device,
    sessions: widget.sessions,
    onCredentials: widget.room.updateDevice,
    relocate: widget.room.relocate,
  );
  late final ShortcutStore _shortcutStore =
      widget.shortcuts ?? PreferencesShortcutStore();
  late final LayoutStore _layoutStore =
      widget.layout ?? PreferencesLayoutStore();
  List<ShortcutSlot> _slots = ShortcutSlot.defaults;
  RemoteLayout _layout = RemoteLayout.defaults;
  var _editing = false;
  var _dragging = false;
  var _resumeRetrying = false;
  late final PhoneVolumeBridge _phoneVolume = PhoneVolumeBridge(
    onAction: (action) {
      if (_editing) return;
      _remote.send(action);
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remote.addListener(_rememberWhenReady);
    _remote.connect();
    _loadPrefs();
    unawaited(_phoneVolume.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_retryOnResume());
    }
  }

  Future<void> _retryOnResume() async {
    if (_resumeRetrying || !mounted) return;
    final phase = _remote.phase;
    if (phase != SessionPhase.failed && phase != SessionPhase.limited) {
      return;
    }
    if (!_remote.session.canRetry) return;
    _resumeRetrying = true;
    try {
      await _remote.retry();
    } finally {
      _resumeRetrying = false;
    }
  }

  Future<void> _loadPrefs() async {
    final shortcuts = await _shortcutStore.read();
    final layout = await _layoutStore.read();
    if (!mounted) return;
    setState(() {
      _slots = shortcuts;
      _layout = layout;
    });
  }

  void _rememberWhenReady() {
    if (_remote.phase == SessionPhase.ready) {
      widget.room.markConnected(_remote.device);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_phoneVolume.stop());
    _remote.removeListener(_rememberWhenReady);
    _remote.dispose();
    super.dispose();
  }

  FarlyDevice get _liveDevice {
    final current = _remote.device;
    for (final device in widget.room.devices) {
      if (device.id == current.id || device.id == widget.device.id) {
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

  Future<void> _persistLayout(RemoteLayout layout) async {
    if (!mounted) return;
    setState(() => _layout = layout);
    await _layoutStore.write(layout);
  }

  void _setDragging(bool value) {
    if (_dragging == value || !mounted) return;
    setState(() => _dragging = value);
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

  Future<void> _enterEdit() async {
    if (_editing) return;
    HapticFeedback.mediumImpact();
    setState(() => _editing = true);
  }

  Future<void> _leaveEdit() async {
    if (!_editing) return;
    await _layoutStore.write(_layout);
    if (!mounted) return;
    setState(() => _editing = false);
  }

  Future<void> _resetAll() async {
    HapticFeedback.mediumImpact();
    await _shortcutStore.write(ShortcutSlot.defaults);
    await _layoutStore.write(RemoteLayout.defaults);
    if (!mounted) return;
    setState(() {
      _slots = ShortcutSlot.defaults;
      _layout = RemoteLayout.defaults;
    });
  }

  void _reorderVisibleBlocks(
    List<RemoteBlockId> visible,
    int oldIndex,
    int newIndex,
  ) {
    final next = [...visible];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    final hidden = [
      for (final block in _layout.blocks)
        if (!next.contains(block)) block,
    ];
    _persistLayout(_layout.copyWith(blocks: [...next, ...hidden]));
  }

  void _reorderChrome(int oldIndex, int newIndex) {
    final chrome = [..._layout.chrome];
    final item = chrome.removeAt(oldIndex);
    chrome.insert(newIndex, item);
    _persistLayout(_layout.copyWith(chrome: chrome));
  }

  void _hideChrome(ChromeId id) {
    final chrome = [for (final item in _layout.chrome) if (item != id) item];
    _persistLayout(_layout.copyWith(chrome: chrome));
  }

  void _showChrome(ChromeId id) {
    if (_layout.chrome.contains(id)) return;
    _persistLayout(_layout.copyWith(chrome: [..._layout.chrome, id]));
  }

  void _reorderShortcuts(int oldIndex, int newIndex) {
    final slots = [..._slots];
    final item = slots.removeAt(oldIndex);
    slots.insert(newIndex, item);
    setState(() => _slots = slots);
    _shortcutStore.write(slots);
  }

  RockerSegment _segment(RemoteAction action, IconData icon) {
    return RockerSegment(
      id: ValueKey(action),
      icon: icon,
      label: action.label,
      onPressed: _editing ? null : () => _remote.send(action),
    );
  }

  bool _chromeAvailable(ChromeId id, RemoteSession session) {
    return switch (id) {
      ChromeId.back || ChromeId.home => true,
      ChromeId.menu => session.supports(RemoteAction.menu),
      ChromeId.keyboard => session.supportsText,
      ChromeId.input => session.supports(RemoteAction.input),
    };
  }

  IconData _chromeIcon(ChromeId id) {
    return switch (id) {
      ChromeId.back => Icons.undo_rounded,
      ChromeId.home => Icons.home_rounded,
      ChromeId.menu => Icons.menu_rounded,
      ChromeId.keyboard => Icons.keyboard_rounded,
      ChromeId.input => Icons.input_rounded,
    };
  }

  String _chromeLabel(ChromeId id) {
    return switch (id) {
      ChromeId.back => RemoteAction.back.label,
      ChromeId.home => RemoteAction.home.label,
      ChromeId.menu => RemoteAction.menu.label,
      ChromeId.keyboard => 'Type on the TV',
      ChromeId.input => RemoteAction.input.label,
    };
  }

  VoidCallback? _chromeAction(ChromeId id) {
    if (_editing) return null;
    return switch (id) {
      ChromeId.back => () => _remote.send(RemoteAction.back),
      ChromeId.home => () => _remote.send(RemoteAction.home),
      ChromeId.menu => () => _remote.send(RemoteAction.menu),
      ChromeId.keyboard => () => showTvKeyboardSheet(
        context: context,
        onSend: _remote.sendText,
        onEnter: _remote.textEnter,
        onBackspace: _remote.textBackspace,
      ),
      ChromeId.input => () => _remote.send(RemoteAction.input),
    };
  }

  Widget _wrapEdit(Key key, Widget child) {
    return Jiggle(key: key, active: _editing && !_dragging, child: child);
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(animation.value);
        return Material(
          elevation: 2 + 6 * t,
          color: Colors.transparent,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(18),
          child: child,
        );
      },
      child: child,
    );
  }

  Widget _levelsRails({required bool showBrightness, double? height}) {
    return IgnorePointer(
      ignoring: _editing,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LevelRail(
            icon: Icons.volume_up_rounded,
            label: 'Volume',
            height: height ?? 156,
            onIncrease: () => _remote.send(RemoteAction.volumeUp),
            onDecrease: () => _remote.send(RemoteAction.volumeDown),
            onIconTap: () => _remote.send(RemoteAction.mute),
            increaseKey: const ValueKey(RemoteAction.volumeUp),
            decreaseKey: const ValueKey(RemoteAction.volumeDown),
            iconKey: const ValueKey(RemoteAction.mute),
          ),
          if (showBrightness) ...[
            const SizedBox(width: 22),
            LevelRail(
              icon: Icons.wb_sunny_rounded,
              label: 'Brightness',
              height: height ?? 156,
              onIncrease: () => _remote.send(RemoteAction.brightnessUp),
              onDecrease: () => _remote.send(RemoteAction.brightnessDown),
              increaseKey: const ValueKey(RemoteAction.brightnessUp),
              decreaseKey: const ValueKey(RemoteAction.brightnessDown),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pad({required double padHeight}) {
    return HorizonPad(
      height: padHeight,
      onAction: _editing ? (_) {} : _remote.send,
      onLongPress: _editing ? null : _enterEdit,
    );
  }

  Widget _padWithRails({
    required bool showBrightness,
    required double padHeight,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _levelsRails(showBrightness: showBrightness, height: padHeight),
        const SizedBox(width: 14),
        Expanded(child: _pad(padHeight: padHeight)),
      ],
    );
  }

  Widget _block(
    RemoteBlockId id, {
    required RemoteSession session,
    required List<AppShortcut> shortcuts,
    required bool showBrightness,
    required double padHeight,
  }) {
    return switch (id) {
      RemoteBlockId.powerRow => _wrapEdit(
        const ValueKey(RemoteBlockId.powerRow),
        Row(
          children: [
            RoundKey(
              icon: Icons.arrow_back_rounded,
              label: 'Back to devices',
              size: 52,
              onPressed: _editing ? null : () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            RoundKey(
              key: const ValueKey(RemoteAction.power),
              icon: Icons.power_settings_new_rounded,
              label: RemoteAction.power.label,
              size: 52,
              tint: FarlyColors.clay,
              onPressed: _editing
                  ? null
                  : () => _remote.send(RemoteAction.power),
            ),
          ],
        ),
      ),
      RemoteBlockId.shortcuts => shortcuts.isEmpty
          ? const SizedBox.shrink()
          : _wrapEdit(
              const ValueKey(RemoteBlockId.shortcuts),
              Column(
                children: [
                  if (_editing)
                    // Horizontal so it doesn't fight the parent vertical list.
                    SizedBox(
                      height: 64,
                      child: ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        proxyDecorator: _proxyDecorator,
                        onReorderStart: (_) => _setDragging(true),
                        onReorderEnd: (_) => _setDragging(false),
                        onReorderItem: _reorderShortcuts,
                        itemCount: shortcuts.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            key: ValueKey(
                              'shortcut-${_slots[index].appId}',
                            ),
                            padding: EdgeInsets.only(
                              right: index == shortcuts.length - 1 ? 0 : 10,
                            ),
                            child: SizedBox(
                              width: 140,
                              child: ReorderableDelayedDragStartListener(
                                index: index,
                                child: _ShortcutButton(
                                  shortcut: shortcuts[index],
                                  onPressed: () => _editShortcut(index),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Row(
                      children: [
                        for (var i = 0; i < shortcuts.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _ShortcutButton(
                              shortcut: shortcuts[i],
                              onPressed: () => _remote.launch(shortcuts[i]),
                              onLongPress: () => _editShortcut(i),
                            ),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    _editing
                        ? 'Tap an app to change it. Hold & drag to reorder.'
                        : 'Hold an app to change it. Hold the pad to rearrange.',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
      RemoteBlockId.transport => _wrapEdit(
        const ValueKey(RemoteBlockId.transport),
        KeyRocker(
          height: 54,
          segments: [
            _segment(RemoteAction.rewind, Icons.fast_rewind_rounded),
            _segment(RemoteAction.play, Icons.play_arrow_rounded),
            _segment(RemoteAction.forward, Icons.fast_forward_rounded),
          ],
        ),
      ),
      RemoteBlockId.levels => _wrapEdit(
        const ValueKey(RemoteBlockId.levels),
        _levelsRails(showBrightness: showBrightness),
      ),
      RemoteBlockId.chrome => _wrapEdit(
        const ValueKey(RemoteBlockId.chrome),
        _ChromeRow(
          editing: _editing,
          visible: [
            for (final id in _layout.chrome)
              if (_chromeAvailable(id, session)) id,
          ],
          hidden: [
            for (final id in ChromeId.values)
              if (!_layout.chrome.contains(id) && _chromeAvailable(id, session))
                id,
          ],
          iconFor: _chromeIcon,
          labelFor: _chromeLabel,
          actionFor: _chromeAction,
          onReorder: _reorderChrome,
          onHide: _hideChrome,
          onShow: _showChrome,
          onDragStart: (_) => _setDragging(true),
          onDragEnd: (_) => _setDragging(false),
          menuProbe: session.supportsMenuProbes
              ? () async {
                  final chosen = await showMenuProbeSheet(
                    context: context,
                    device: _liveDevice,
                    onTry: _remote.sendMenuProbe,
                  );
                  if (chosen == null || !mounted) return;
                  _remote.setMenuCommand(chosen);
                }
              : null,
        ),
      ),
      RemoteBlockId.pad => _wrapEdit(
        const ValueKey(RemoteBlockId.pad),
        _pad(padHeight: padHeight),
      ),
    };
  }

  List<Widget> _normalBlocks({
    required List<RemoteBlockId> blocks,
    required RemoteSession session,
    required List<AppShortcut> shortcuts,
    required bool showBrightness,
    required double padHeight,
  }) {
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 14));
      final id = blocks[i];
      final next = i + 1 < blocks.length ? blocks[i + 1] : null;
      if (id == RemoteBlockId.levels && next == RemoteBlockId.pad) {
        children.add(
          _padWithRails(
            showBrightness: showBrightness,
            padHeight: padHeight,
          ),
        );
        i++;
        continue;
      }
      if (id == RemoteBlockId.pad && next == RemoteBlockId.levels) {
        children.add(
          _padWithRails(
            showBrightness: showBrightness,
            padHeight: padHeight,
          ),
        );
        i++;
        continue;
      }
      children.add(
        _block(
          id,
          session: session,
          shortcuts: shortcuts,
          showBrightness: showBrightness,
          padHeight: padHeight,
        ),
      );
    }
    return children;
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
                  final blocks = [
                    for (final id in _layout.blocks)
                      if (id != RemoteBlockId.shortcuts || shortcuts.isNotEmpty)
                        id,
                  ];
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _editing
                                        ? 'Arrange mode'
                                        : live.brand.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: _editing
                                              ? FarlyColors.horizon
                                              : null,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_editing) ...[
                              Pressable(
                                label: 'Reset layout',
                                onPressed: _resetAll,
                                child: const Text(
                                  'Reset',
                                  style: TextStyle(
                                    color: FarlyColors.clay,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Pressable(
                                label: 'Done arranging',
                                onPressed: _leaveEdit,
                                child: const Text(
                                  'Done',
                                  style: TextStyle(
                                    color: FarlyColors.horizon,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ] else
                              _PhasePill(phase: _remote.phase),
                          ],
                        ),
                      ),
                      if (showStatus && !_editing)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: _StatusBanner(
                            text: detail,
                            alert: _remote.phase == SessionPhase.failed,
                          ),
                        ),
                      Expanded(
                        child: _editing
                            ? ReorderableListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  16,
                                ),
                                buildDefaultDragHandles: false,
                                proxyDecorator: _proxyDecorator,
                                onReorderStart: (_) => _setDragging(true),
                                onReorderEnd: (_) => _setDragging(false),
                                itemCount: blocks.length,
                                onReorderItem: (oldIndex, newIndex) {
                                  _reorderVisibleBlocks(
                                    blocks,
                                    oldIndex,
                                    newIndex,
                                  );
                                },
                                itemBuilder: (context, index) {
                                  final id = blocks[index];
                                  final body = _block(
                                    id,
                                    session: session,
                                    shortcuts: shortcuts,
                                    showBrightness: showBrightness,
                                    padHeight: padHeight,
                                  );
                                  return Padding(
                                    key: ValueKey(id),
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Immediate grab from the handle.
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: const Padding(
                                            padding: EdgeInsets.only(
                                              top: 18,
                                              right: 10,
                                            ),
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              size: 28,
                                              color: FarlyColors.mist,
                                            ),
                                          ),
                                        ),
                                        // Hold anywhere on the block to drag.
                                        Expanded(
                                          child:
                                              ReorderableDelayedDragStartListener(
                                                index: index,
                                                child: body,
                                              ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : BottomAligned(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  16,
                                ),
                                children: [
                                  ..._normalBlocks(
                                    blocks: blocks,
                                    session: session,
                                    shortcuts: shortcuts,
                                    showBrightness: showBrightness,
                                    padHeight: padHeight,
                                  ),
                                  if (_remote.phase == SessionPhase.pairing) ...[
                                    const SizedBox(height: 14),
                                    _PairPanel(
                                      busy: _remote.submitting,
                                      onSubmit: _remote.submitCode,
                                    ),
                                  ],
                                  if (_remote.phase == SessionPhase.failed &&
                                      session.canRetry) ...[
                                    const SizedBox(height: 14),
                                    FarlyPress(
                                      label: 'Try again',
                                      icon: Icons.refresh_rounded,
                                      expand: true,
                                      onPressed: _remote.retry,
                                    ),
                                  ],
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

class _ChromeRow extends StatelessWidget {
  const _ChromeRow({
    required this.editing,
    required this.visible,
    required this.hidden,
    required this.iconFor,
    required this.labelFor,
    required this.actionFor,
    required this.onReorder,
    required this.onHide,
    required this.onShow,
    this.onDragStart,
    this.onDragEnd,
    this.menuProbe,
  });

  final bool editing;
  final List<ChromeId> visible;
  final List<ChromeId> hidden;
  final IconData Function(ChromeId id) iconFor;
  final String Function(ChromeId id) labelFor;
  final VoidCallback? Function(ChromeId id) actionFor;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<ChromeId> onHide;
  final ValueChanged<ChromeId> onShow;
  final ValueChanged<int>? onDragStart;
  final ValueChanged<int>? onDragEnd;
  final VoidCallback? menuProbe;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (editing)
          SizedBox(
            height: 72,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                return Material(
                  color: Colors.transparent,
                  elevation: 6,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(28),
                  child: child,
                );
              },
              onReorderStart: onDragStart,
              onReorderEnd: onDragEnd,
              onReorderItem: onReorder,
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final id = visible[index];
                return Padding(
                  key: ValueKey(id),
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: RoundKey(
                          icon: iconFor(id),
                          label: labelFor(id),
                          onPressed: null,
                        ),
                      ),
                      Positioned(
                        top: -4,
                        left: -4,
                        child: Pressable(
                          label: 'Hide ${labelFor(id)}',
                          onPressed: () => onHide(id),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: FarlyColors.clay,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.remove_rounded,
                              size: 14,
                              color: FarlyColors.night,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final id in visible)
                RoundKey(
                  key: ValueKey(id),
                  icon: iconFor(id),
                  label: labelFor(id),
                  onPressed: actionFor(id),
                ),
            ],
          ),
        if (editing && hidden.isNotEmpty) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Hidden — tap to show',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final id in hidden)
                Pressable(
                  label: 'Show ${labelFor(id)}',
                  onPressed: () => onShow(id),
                  child: Opacity(
                    opacity: 0.55,
                    child: KeyFace(icon: iconFor(id), size: 52),
                  ),
                ),
            ],
          ),
        ],
        if (!editing && menuProbe != null) ...[
          const SizedBox(height: 6),
          Center(
            child: Pressable(
              label: 'Menu not working? Try other keys',
              onPressed: menuProbe,
              child: Text(
                'Menu not working?',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: FarlyColors.horizon,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
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
    this.onLongPress,
  });

  final AppShortcut shortcut;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

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
