import 'package:flutter/material.dart';

import '../models/farly_device.dart';
import '../models/menu_command.dart';
import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import 'farly_list.dart';
import 'keys.dart';

Future<String?> showMenuProbeSheet({
  required BuildContext context,
  required FarlyDevice device,
  required Future<void> Function(String commandId) onTry,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _MenuProbeSheet(device: device, onTry: onTry),
  );
}

class _MenuProbeSheet extends StatefulWidget {
  const _MenuProbeSheet({required this.device, required this.onTry});

  final FarlyDevice device;
  final Future<void> Function(String commandId) onTry;

  @override
  State<_MenuProbeSheet> createState() => _MenuProbeSheetState();
}

class _MenuProbeSheetState extends State<_MenuProbeSheet> {
  late String _active;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _active = MenuCommand.resolvedId(widget.device);
  }

  Future<void> _try(MenuCommand command) async {
    if (_busyId != null) return;
    setState(() => _busyId = command.id);
    try {
      await widget.onTry(command.id);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commands = MenuCommand.forBrand(widget.device.brand);
    final tclHint =
        widget.device.brand == DeviceBrand.androidTv &&
        widget.device.name.toLowerCase().contains('tcl');
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF243731), FarlyColors.night],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: FarlyColors.edge)),
      ),
      child: Column(
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Try another Menu key',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              RoundKey(
                icon: Icons.close_rounded,
                label: 'Close',
                size: 44,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tclHint
                ? 'TCL remotes often use Settings or All apps instead of the classic Menu key. Tap Try on each, watch the TV, then keep the one that works.'
                : 'Menu keys differ by TV. Tap Try on each option, watch the screen, then keep the one that opens the menu you want.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              children: [
                FarlyListGroup(
                  inset: 16,
                  children: [
                    for (final command in commands)
                      FarlyListRow(
                        title: command.label,
                        detail: command.note,
                        padding: const EdgeInsets.only(left: 16, right: 10),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 8),
                            _Chip(
                              label: _busyId == command.id ? '…' : 'Try',
                              onPressed: _busyId != null
                                  ? null
                                  : () => _try(command),
                            ),
                            const SizedBox(width: 6),
                            _Chip(
                              label: command.id == _active ? 'Using' : 'Use',
                              filled: true,
                              onPressed: () =>
                                  Navigator.of(context).pop(command.id),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      label: label,
      onPressed: onPressed,
      child: Container(
        constraints: const BoxConstraints(minWidth: 52, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: filled
            ? FarlySurfaces.sunPill(radius: 14)
            : FarlySurfaces.glass(radius: 14),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: filled ? FarlyColors.night : FarlyColors.bone,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
