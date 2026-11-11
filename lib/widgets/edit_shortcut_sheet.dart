import 'package:flutter/material.dart';

import '../models/farly_device.dart';
import '../models/stream_app.dart';
import '../theme/farly_colors.dart';
import 'farly_press.dart';
import 'keys.dart';
import 'stream_mark.dart';

Future<ShortcutSlot?> showEditShortcutSheet({
  required BuildContext context,
  required ShortcutSlot slot,
  required DeviceBrand brand,
  required int index,
}) {
  return showModalBottomSheet<ShortcutSlot>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _EditShortcutSheet(
      slot: slot,
      brand: brand,
      index: index,
    ),
  );
}

class _EditShortcutSheet extends StatefulWidget {
  const _EditShortcutSheet({
    required this.slot,
    required this.brand,
    required this.index,
  });

  final ShortcutSlot slot;
  final DeviceBrand brand;
  final int index;

  @override
  State<_EditShortcutSheet> createState() => _EditShortcutSheetState();
}

class _EditShortcutSheetState extends State<_EditShortcutSheet> {
  late String _appId;
  late final TextEditingController _label;
  late final TextEditingController _target;
  String? _error;

  bool get _roku => widget.brand == DeviceBrand.roku;

  @override
  void initState() {
    super.initState();
    _appId = widget.slot.appId;
    _label = TextEditingController(text: widget.slot.customLabel ?? '');
    _target = TextEditingController(
      text: _roku
          ? (widget.slot.customRokuId ?? '')
          : (widget.slot.customUrl ?? ''),
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final apps = [
      for (final app in StreamApp.catalog)
        if (app.supports(widget.brand)) app,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
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
                      'App button ${widget.index + 1}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pick a streaming app or set a custom ${_roku ? 'Roku channel id' : 'URL'}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final app in apps)
                            _AppChoice(
                              app: app,
                              selected: _appId == app.id,
                              onSelect: () => setState(() {
                                _appId = app.id;
                                _error = null;
                              }),
                            ),
                          _CustomChoice(
                            selected: _appId == ShortcutSlot.customId,
                            onSelect: () => setState(() {
                              _appId = ShortcutSlot.customId;
                              _error = null;
                            }),
                          ),
                        ],
                      ),
                      if (_appId == ShortcutSlot.customId) ...[
                        const SizedBox(height: 18),
                        _Field(
                          controller: _label,
                          hint: 'Label',
                          icon: Icons.label_outline_rounded,
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          controller: _target,
                          hint: _roku
                              ? 'Roku channel id (e.g. 12)'
                              : 'https://www.example.com',
                          icon: _roku
                              ? Icons.tag_rounded
                              : Icons.link_rounded,
                          keyboard: _roku
                              ? TextInputType.number
                              : TextInputType.url,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: FarlyColors.clay,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FarlyPress(
                  label: 'Save',
                  icon: Icons.check_rounded,
                  filled: true,
                  expand: true,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (_appId != ShortcutSlot.customId) {
      Navigator.pop(context, ShortcutSlot(appId: _appId));
      return;
    }
    final label = _label.text.trim();
    final target = _target.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Enter a label');
      return;
    }
    if (target.isEmpty) {
      setState(
        () => _error = _roku ? 'Enter a Roku channel id' : 'Enter a URL',
      );
      return;
    }
    Navigator.pop(
      context,
      ShortcutSlot(
        appId: ShortcutSlot.customId,
        customLabel: label,
        customRokuId: _roku ? target : null,
        customUrl: _roku ? null : target,
      ),
    );
  }
}

class _AppChoice extends StatelessWidget {
  const _AppChoice({
    required this.app,
    required this.selected,
    required this.onSelect,
  });

  final StreamApp app;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
        decoration: BoxDecoration(
          color: selected
              ? app.tint.withValues(alpha: 0.28)
              : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? app.tint : FarlyColors.edge,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamMark(mark: app.mark, tint: app.tint, size: 32),
            const SizedBox(width: 10),
            Text(
              app.label,
              style: const TextStyle(
                color: FarlyColors.bone,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomChoice extends StatelessWidget {
  const _CustomChoice({required this.selected, required this.onSelect});

  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
        decoration: BoxDecoration(
          color: selected
              ? FarlyColors.horizon.withValues(alpha: 0.22)
              : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? FarlyColors.horizon : FarlyColors.edge,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamMark(mark: '+', size: 32),
            SizedBox(width: 10),
            Text(
              'Custom',
              style: TextStyle(
                color: FarlyColors.bone,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
    this.keyboard = TextInputType.text,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboard;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
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
