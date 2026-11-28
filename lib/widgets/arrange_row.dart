import 'package:flutter/material.dart';

import '../theme/farly_colors.dart';
import 'farly_list.dart';
import 'keys.dart';

/// One arrange row: handle, icon, name, optional chevron, eye. A thin wrapper
/// over [FarlyListRow] so it matches the drawer.
///
/// [index] non-null adds a drag handle (must sit in a reorderable list).
/// [onTap] adds a chevron and makes the name open a sub-editor. [onToggle]
/// is the eye; null disables it. [hidden] mutes the row and shows eye-slash.
class ArrangeRow extends StatelessWidget {
  const ArrangeRow({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.detail,
    this.index,
    this.hidden = false,
    this.divider = false,
    this.onTap,
    this.onToggle,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final String? detail;
  final int? index;
  final bool hidden;
  final bool divider;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  /// Divider inset that lines up with the icon after the 44pt handle.
  static const dividerInset = 48.0;

  @override
  Widget build(BuildContext context) {
    final handle = index == null
        ? const SizedBox(width: 44)
        : ReorderableDragStartListener(
            index: index!,
            child: Semantics(
              container: true,
              label: 'Reorder $label',
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 24,
                  color: FarlyColors.mist,
                ),
              ),
            ),
          );
    return FarlyListRow(
      divider: divider,
      dividerInset: dividerInset,
      padding: const EdgeInsets.only(left: 4),
      muted: hidden,
      title: label,
      detail: detail,
      titleSemantics: onTap == null ? null : 'Edit $label',
      onTap: onTap,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          handle,
          leading ??
              Icon(
                icon,
                size: 22,
                color: hidden ? FarlyColors.mist : FarlyColors.bone,
              ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onTap != null && !hidden)
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: FarlyColors.mist,
            ),
          Semantics(
            container: true,
            child: Pressable(
              label: '${hidden ? 'Show' : 'Hide'} $label',
              onPressed: onToggle,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  hidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 22,
                  color: hidden ? FarlyColors.mist : FarlyColors.horizon,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
