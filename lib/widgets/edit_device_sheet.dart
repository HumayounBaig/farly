import 'package:flutter/material.dart';

import '../models/device_icon.dart';
import '../models/farly_device.dart';
import '../theme/farly_colors.dart';
import 'device_glyph.dart';
import 'farly_press.dart';
import 'keys.dart';

/// Edits a saved device's display name and icon.
Future<FarlyDevice?> showEditDeviceSheet(
  BuildContext context,
  FarlyDevice device,
) {
  return showModalBottomSheet<FarlyDevice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _EditDeviceSheet(device: device),
  );
}

class _EditDeviceSheet extends StatefulWidget {
  const _EditDeviceSheet({required this.device});

  final FarlyDevice device;

  @override
  State<_EditDeviceSheet> createState() => _EditDeviceSheetState();
}

class _EditDeviceSheetState extends State<_EditDeviceSheet> {
  late final TextEditingController _name;
  late String? _icon;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.device.name);
    _icon = widget.device.icon ?? DeviceIcon.suggestedId(widget.device);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final preview = widget.device.copyWith(name: _name.text, icon: _icon);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
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
            Row(
              children: [
                DeviceGlyph(device: preview, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Edit device',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              style: const TextStyle(color: FarlyColors.bone),
              cursorColor: FarlyColors.horizon,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Name',
                hintStyle: const TextStyle(color: FarlyColors.mist),
                prefixIcon: const Icon(
                  Icons.edit_outlined,
                  color: FarlyColors.mist,
                  size: 20,
                ),
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
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),
            Text('Brand marks', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 10),
            _IconRow(
              icons: DeviceIcon.brands,
              selected: _icon,
              onSelect: (id) => setState(() => _icon = id),
            ),
            const SizedBox(height: 16),
            Text('Emojis', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: _IconRow(
                  icons: DeviceIcon.emojis,
                  selected: _icon,
                  onSelect: (id) => setState(() => _icon = id),
                ),
              ),
            ),
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
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      widget.device.copyWith(
        name: name,
        icon: _icon,
        nameLocked: true,
        clearIcon: _icon == null,
      ),
    );
  }
}

class _IconRow extends StatelessWidget {
  const _IconRow({
    required this.icons,
    required this.selected,
    required this.onSelect,
  });

  final List<DeviceIcon> icons;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final icon in icons)
          Pressable(
            onPressed: () => onSelect(icon.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected == icon.id
                    ? icon.tint.withValues(alpha: 0.35)
                    : const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected == icon.id ? icon.tint : FarlyColors.edge,
                  width: selected == icon.id ? 1.6 : 1,
                ),
              ),
              child: icon.emoji != null
                  ? Text(icon.emoji!, style: const TextStyle(fontSize: 22))
                  : Text(
                      icon.brand!.length <= 3
                          ? icon.brand!
                          : icon.brand!.substring(0, 1),
                      style: TextStyle(
                        color: FarlyColors.bone,
                        fontSize: icon.brand!.length > 2 ? 11 : 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}
