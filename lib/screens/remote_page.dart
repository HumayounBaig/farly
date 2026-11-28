import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import '../widgets/arrange_row.dart';
import '../widgets/farly_list.dart';
import '../widgets/bottom_aligned.dart';
import '../widgets/device_glyph.dart';
import '../widgets/edit_shortcut_sheet.dart';
import '../widgets/farly_backdrop.dart';
import '../widgets/farly_press.dart';
import '../widgets/horizon_pad.dart';
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
    } else if (state == AppLifecycleState.hidden) {
      // Backing out of the TV menu when the app is minimized.
      unawaited(_remote.sendAutoBack());
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
    final remote = _remote;
    // Back out of a left-open TV menu; close the session only after it goes out.
    unawaited(remote
        .sendAutoBack()
        .timeout(const Duration(seconds: 2))
        .catchError((_) {})
        .whenComplete(remote.dispose));
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

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to default?'),
        content: const Text('Restores the original layout and app buttons.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) await _resetAll();
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

  void _reorderBlocks(int oldIndex, int newIndex) {
    final next = [..._layout.blocks];
    if (oldIndex < 0 || oldIndex >= next.length) return;
    if (newIndex < 0 || newIndex > next.length) return;
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    HapticFeedback.selectionClick();
    _persistLayout(_layout.copyWith(blocks: next));
  }

  void _hideBlock(RemoteBlockId id) {
    if (!_layout.blocks.contains(id)) return;
    // Keep at least one block so arrange mode still has something to show.
    if (_layout.blocks.length <= 1) return;
    HapticFeedback.lightImpact();
    _persistLayout(
      _layout.copyWith(
        blocks: [
          for (final block in _layout.blocks)
            if (block != id) block,
        ],
      ),
    );
  }

  void _showBlock(RemoteBlockId id) {
    if (_layout.blocks.contains(id)) return;
    HapticFeedback.selectionClick();
    _persistLayout(_layout.copyWith(blocks: [..._layout.blocks, id]));
  }

  void _reorderChrome(int oldIndex, int newIndex) {
    final chrome = [..._layout.chrome];
    if (oldIndex < 0 || oldIndex >= chrome.length) return;
    if (newIndex < 0 || newIndex > chrome.length) return;
    final item = chrome.removeAt(oldIndex);
    chrome.insert(newIndex.clamp(0, chrome.length), item);
    HapticFeedback.selectionClick();
    _persistLayout(_layout.copyWith(chrome: chrome));
  }

  void _hideChrome(ChromeId id) {
    final chrome = [
      for (final item in _layout.chrome)
        if (item != id) item,
    ];
    HapticFeedback.lightImpact();
    _persistLayout(_layout.copyWith(chrome: chrome));
  }

  void _showChrome(ChromeId id) {
    if (_layout.chrome.contains(id)) return;
    HapticFeedback.selectionClick();
    _persistLayout(_layout.copyWith(chrome: [..._layout.chrome, id]));
  }

  void _reorderShortcuts(int oldIndex, int newIndex) {
    final slots = [..._slots];
    if (oldIndex < 0 || oldIndex >= slots.length) return;
    if (newIndex < 0 || newIndex > slots.length) return;
    final item = slots.removeAt(oldIndex);
    slots.insert(newIndex.clamp(0, slots.length), item);
    HapticFeedback.selectionClick();
    setState(() => _slots = slots);
    _shortcutStore.write(slots);
  }

  String _blockLabel(RemoteBlockId id) {
    return switch (id) {
      RemoteBlockId.powerRow => 'Power row',
      RemoteBlockId.shortcuts => 'Apps',
      RemoteBlockId.transport => 'Play controls',
      RemoteBlockId.levels => 'Volume',
      RemoteBlockId.chrome => 'Menu keys',
      RemoteBlockId.pad => 'D-pad',
    };
  }

  IconData _blockIcon(RemoteBlockId id) {
    return switch (id) {
      RemoteBlockId.powerRow => Icons.power_settings_new_rounded,
      RemoteBlockId.shortcuts => Icons.apps_rounded,
      RemoteBlockId.transport => Icons.play_arrow_rounded,
      RemoteBlockId.levels => Icons.volume_up_rounded,
      RemoteBlockId.chrome => Icons.menu_rounded,
      RemoteBlockId.pad => Icons.gamepad_rounded,
    };
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
      ChromeId.pictureOff =>
        session.pictureOffSupport != PictureOffSupport.none,
    };
  }

  IconData _chromeIcon(ChromeId id) {
    return switch (id) {
      ChromeId.back => Icons.undo_rounded,
      ChromeId.home => Icons.home_rounded,
      ChromeId.menu => Icons.menu_rounded,
      ChromeId.keyboard => Icons.keyboard_rounded,
      ChromeId.input => Icons.input_rounded,
      ChromeId.pictureOff =>
        _remote.pictureIsOff ? Icons.tv_rounded : Icons.tv_off_rounded,
    };
  }

  String _chromeLabel(ChromeId id) {
    return switch (id) {
      ChromeId.back => RemoteAction.back.label,
      ChromeId.home => RemoteAction.home.label,
      ChromeId.menu => RemoteAction.menu.label,
      ChromeId.keyboard => 'Type on the TV',
      ChromeId.input => RemoteAction.input.label,
      ChromeId.pictureOff =>
        _remote.pictureIsOff ? 'Picture on' : 'Picture off',
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
        failureDetail: () => _remote.textDetail,
        onEnter: _remote.textEnter,
        onBackspace: _remote.textBackspace,
        onSearchYoutube: _remote.supportsYoutubeSearch ? _remote.searchYoutube : null,
        onSendKeys: _remote.sendKeysInOrder,
        onCancelKeys: _remote.cancelKeys,
      ),
      ChromeId.input => () => _remote.send(RemoteAction.input),
      ChromeId.pictureOff => _remote.togglePictureOff,
    };
  }

  Widget _arrangeList({
    required List<AppShortcut> shortcuts,
    required RemoteSession session,
    required bool showBrightness,
  }) {
    final blocks = _layout.blocks;
    final hidden = [
      for (final id in RemoteBlockId.values)
        if (!blocks.contains(id)) id,
    ];
    ArrangeRow row(RemoteBlockId id, {int? index}) {
      final apps = id == RemoteBlockId.shortcuts;
      final detail = apps && shortcuts.isEmpty ? 'No apps on this TV' : null;
      final onTap = switch (id) {
        RemoteBlockId.shortcuts when shortcuts.isNotEmpty => _editApps,
        RemoteBlockId.chrome => _editChrome,
        _ => null,
      };
      final isHidden = index == null;
      return ArrangeRow(
        key: ValueKey(id),
        icon: _blockIcon(id),
        label: _blockLabel(id),
        detail: detail,
        index: index,
        hidden: isHidden,
        divider: (index ?? 0) > 0,
        onTap: isHidden ? null : onTap,
        onToggle: isHidden
            ? () => _showBlock(id)
            : (blocks.length > 1 ? () => _hideBlock(id) : null),
      );
    }

    final labelStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: FarlyColors.mist);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.maxHeight >= 600) ...[
              _arrangePreview(
                shortcuts: shortcuts,
                session: session,
                showBrightness: showBrightness,
              ),
              const SizedBox(height: 20),
            ],
            FarlyListGroup(
              inset: ArrangeRow.dividerInset,
              children: [
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: _proxyDecorator,
                  onReorderItem: _reorderBlocks,
                  itemCount: blocks.length,
                  itemBuilder: (context, index) {
                    final id = blocks[index];
                    return Semantics(
                      key: ValueKey('arrange-$id'),
                      customSemanticsActions: {
                        if (index > 0)
                          const CustomSemanticsAction(label: 'Move up'): () =>
                              _reorderBlocks(index, index - 1),
                        if (index < blocks.length - 1)
                          const CustomSemanticsAction(label: 'Move down'): () =>
                              _reorderBlocks(index, index + 1),
                      },
                      child: row(id, index: index),
                    );
                  },
                ),
              ],
            ),
            if (hidden.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                child: Text('Hidden', style: labelStyle),
              ),
              FarlyListGroup(
                inset: ArrangeRow.dividerInset,
                children: [for (final id in hidden) row(id)],
              ),
            ],
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: TextButton(
                  onPressed: _confirmReset,
                  style: TextButton.styleFrom(
                    foregroundColor: FarlyColors.mist,
                  ),
                  child: const Text('Reset to default'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Static, scaled-down copy of the remote in the current order. Built from
  /// the real block builders; `_editing` is true here so every control is
  /// disabled, and IgnorePointer blocks the rest.
  Widget _arrangePreview({
    required List<AppShortcut> shortcuts,
    required RemoteSession session,
    required bool showBrightness,
  }) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          height: 280,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FarlyColors.edge),
          ),
          child: FittedBox(
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _normalBlocks(
                  blocks: _layout.blocks,
                  session: session,
                  shortcuts: shortcuts,
                  showBrightness: showBrightness,
                  padHeight: 240,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showArrangeSheet({
    required String title,
    required Widget Function(StateSetter setSheet) body,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF243731), FarlyColors.night],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(top: BorderSide(color: FarlyColors.edge)),
        ),
        child: SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setSheet) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  body(setSheet),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editApps() {
    final brand = _remote.device.brand;
    return _showArrangeSheet(
      title: 'Apps',
      body: (setSheet) => FarlyListGroup(
        inset: ArrangeRow.dividerInset,
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: _proxyDecorator,
            onReorderItem: (from, to) {
              _reorderShortcuts(from, to);
              setSheet(() {});
            },
            itemCount: _slots.length,
            itemBuilder: (context, i) {
              final app = _slots[i].toShortcut(brand);
              return ArrangeRow(
                key: ValueKey('shortcut-${_slots[i].appId}-$i'),
                divider: i > 0,
                leading: StreamMark(
                  mark: app.mark ?? app.label.characters.first,
                  tint: app.tint ?? FarlyColors.horizon,
                  size: 28,
                ),
                label: app.label,
                index: i,
                onTap: () async {
                  await _editShortcut(i);
                  if (context.mounted) setSheet(() {});
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editChrome() {
    final session = _remote.session;
    return _showArrangeSheet(
      title: 'Menu keys',
      body: (setSheet) {
        final visible = [
          for (final id in _layout.chrome)
            if (_chromeAvailable(id, session)) id,
        ];
        final hidden = [
          for (final id in ChromeId.values)
            if (!_layout.chrome.contains(id) && _chromeAvailable(id, session))
              id,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FarlyListGroup(
              inset: ArrangeRow.dividerInset,
              children: [
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  proxyDecorator: _proxyDecorator,
                  onReorderItem: (from, to) {
                    _reorderChrome(from, to);
                    setSheet(() {});
                  },
                  itemCount: visible.length,
                  itemBuilder: (context, i) => ArrangeRow(
                    key: ValueKey(visible[i]),
                    divider: i > 0,
                    icon: _chromeIcon(visible[i]),
                    label: _chromeLabel(visible[i]),
                    index: i,
                    onToggle: () {
                      _hideChrome(visible[i]);
                      setSheet(() {});
                    },
                  ),
                ),
              ],
            ),
            if (hidden.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                child: Text(
                  'Hidden',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: FarlyColors.mist),
                ),
              ),
              FarlyListGroup(
                inset: ArrangeRow.dividerInset,
                children: [
                  for (final id in hidden)
                    ArrangeRow(
                      key: ValueKey(id),
                      icon: _chromeIcon(id),
                      label: _chromeLabel(id),
                      hidden: true,
                      onToggle: () {
                        _showChrome(id);
                        setSheet(() {});
                      },
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _wrapEdit(Key key, Widget child) {
    return KeyedSubtree(key: key, child: child);
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(animation.value);
        return Material(
          elevation: 2 + 8 * t,
          color: FarlyColors.raised,
          shadowColor: Colors.black87,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      child: child,
    );
  }

  Widget _volumeRail({double? height}) {
    return LevelRail(
      icon: Icons.volume_up_rounded,
      label: 'Volume',
      height: height ?? 156,
      steps: 2,
      onIncrease: () => _remote.send(RemoteAction.volumeUp),
      onDecrease: () => _remote.send(RemoteAction.volumeDown),
      onIconTap: () => _remote.send(RemoteAction.mute),
      increaseKey: const ValueKey(RemoteAction.volumeUp),
      decreaseKey: const ValueKey(RemoteAction.volumeDown),
      iconKey: const ValueKey(RemoteAction.mute),
    );
  }

  Widget _brightnessRail({double? height}) {
    return LevelRail(
      icon: Icons.wb_sunny_rounded,
      label: 'Brightness',
      height: height ?? 156,
      steps: 5,
      onIncrease: () => _remote.send(RemoteAction.brightnessUp),
      onDecrease: () => _remote.send(RemoteAction.brightnessDown),
      increaseKey: const ValueKey(RemoteAction.brightnessUp),
      decreaseKey: const ValueKey(RemoteAction.brightnessDown),
    );
  }

  /// Stacked rails when levels sit alone (not beside the pad).
  Widget _levelsRails({required bool showBrightness, double? height}) {
    return IgnorePointer(
      ignoring: _editing,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _volumeRail(height: height),
          if (showBrightness) ...[
            const SizedBox(width: 22),
            _brightnessRail(height: height),
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

  /// Default control cluster: volume | pad | brightness.
  Widget _padWithRails({
    required bool showBrightness,
    required double padHeight,
  }) {
    return IgnorePointer(
      ignoring: _editing,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _volumeRail(height: padHeight),
          const SizedBox(width: 14),
          Expanded(child: _pad(padHeight: padHeight)),
          if (showBrightness) ...[
            const SizedBox(width: 14),
            _brightnessRail(height: padHeight),
          ],
        ],
      ),
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
        Align(
          alignment: Alignment.centerRight,
          child: RoundKey(
            key: const ValueKey(RemoteAction.power),
            icon: Icons.power_settings_new_rounded,
            label: RemoteAction.power.label,
            size: 52,
            tint: FarlyColors.clay,
            onPressed: _editing ? null : () => _remote.send(RemoteAction.power),
          ),
        ),
      ),
      RemoteBlockId.shortcuts =>
        shortcuts.isEmpty
            ? const SizedBox.shrink()
            : _wrapEdit(
                const ValueKey(RemoteBlockId.shortcuts),
                Column(
                  children: [
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
                      'Hold an app to change it. Hold the pad to rearrange.',
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
          visible: [
            for (final id in _layout.chrome)
              if (_chromeAvailable(id, session)) id,
          ],
          iconFor: _chromeIcon,
          labelFor: _chromeLabel,
          actionFor: _chromeAction,
          activeFor: (id) => id == ChromeId.pictureOff && _remote.pictureIsOff,
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
          _padWithRails(showBrightness: showBrightness, padHeight: padHeight),
        );
        i++;
        continue;
      }
      if (id == RemoteBlockId.pad && next == RemoteBlockId.levels) {
        children.add(
          _padWithRails(showBrightness: showBrightness, padHeight: padHeight),
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
                  // In arrange mode show every saved visible block, even empty
                  // shortcuts, so hide/reorder never fights capability filters.
                  final blocks = _editing
                      ? _layout.blocks
                      : [
                          for (final id in _layout.blocks)
                            if (id != RemoteBlockId.shortcuts ||
                                shortcuts.isNotEmpty)
                              id,
                        ];
                  return Column(
                    children: [
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        color: _editing
                            ? FarlyColors.arrangeWash
                            : Colors.transparent,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                        child: Row(
                          children: [
                            if (!_editing)
                              Pressable(
                                label: 'Back to devices',
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    size: 24,
                                    color: FarlyColors.bone,
                                  ),
                                ),
                              ),
                            DeviceGlyph(device: live, size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (!_editing) ...[
                                        _PhaseDot(phase: _remote.phase),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Text(
                                          _editing
                                              ? 'Arrange remote'
                                              : live.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _editing
                                        ? 'Drag to reorder, eye to hide'
                                        : live.brand.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: _editing
                                              ? FarlyColors.mist
                                              : null,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_editing)
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
                              )
                            else
                              Pressable(
                                label: 'Arrange remote',
                                onPressed: _enterEdit,
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    size: 22,
                                    color: FarlyColors.mist,
                                  ),
                                ),
                              ),
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
                            ? _arrangeList(
                                shortcuts: shortcuts,
                                session: session,
                                showBrightness: showBrightness,
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
                                  if (_remote.phase ==
                                      SessionPhase.pairing) ...[
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
                                    if (_remote.canPairAgain) ...[
                                      const SizedBox(height: 10),
                                      FarlyPress(
                                        label: 'Pair again',
                                        icon: Icons.link_rounded,
                                        expand: true,
                                        onPressed: _remote.pairAgain,
                                      ),
                                    ],
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
    required this.visible,
    required this.iconFor,
    required this.labelFor,
    required this.actionFor,
    this.activeFor,
    this.menuProbe,
  });

  final List<ChromeId> visible;
  final IconData Function(ChromeId id) iconFor;
  final String Function(ChromeId id) labelFor;
  final VoidCallback? Function(ChromeId id) actionFor;
  final bool Function(ChromeId id)? activeFor;
  final VoidCallback? menuProbe;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final id in visible)
              RoundKey(
                key: ValueKey(id),
                icon: iconFor(id),
                label: labelFor(id),
                onPressed: actionFor(id),
                accent: activeFor?.call(id) ?? false,
              ),
          ],
        ),
        if (menuProbe != null) ...[
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
    return FarlyListGroup(
      children: [
        Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
        ),
      ],
    );
  }
}

class _PhaseDot extends StatelessWidget {
  const _PhaseDot({required this.phase});

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
    return Semantics(
      label: label,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 6,
              spreadRadius: 0.5,
            ),
          ],
        ),
      ),
    );
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
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: FarlyColors.bone, height: 1.35),
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
