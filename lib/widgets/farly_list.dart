import 'package:flutter/material.dart';

import '../theme/farly_colors.dart';

/// One inset-grouped container: flat muted fill, hairline border, dividers
/// between children. Shared by the drawer, arrange mode and the sub-sheets.
class FarlyListGroup extends StatelessWidget {
  const FarlyListGroup({super.key, required this.children, this.inset = 56});

  final List<Widget> children;

  /// Left inset of the divider lines.
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x0FFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: FarlyColors.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) FarlyListDivider(inset: inset),
            children[i],
          ],
        ],
      ),
    );
  }
}

class FarlyListDivider extends StatelessWidget {
  const FarlyListDivider({super.key, this.inset = 56});

  final double inset;

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: EdgeInsets.only(left: inset),
    color: FarlyColors.edge,
  );
}

/// A flat list row. [divider] draws the inset line above it, for rows in a
/// list the group cannot split itself (a ReorderableListView).
class FarlyListRow extends StatelessWidget {
  const FarlyListRow({
    super.key,
    required this.title,
    this.leading,
    this.detail,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.muted = false,
    this.titleSemantics,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.divider = false,
    this.dividerInset = 56,
  });

  final String title;
  final Widget? leading;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Mist title instead of bone, for hidden or disabled rows.
  final bool muted;

  /// Replaces the title/detail semantics (and only those) when set.
  final String? titleSemantics;
  final EdgeInsetsGeometry padding;
  final bool divider;
  final double dividerInset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted ? FarlyColors.mist : FarlyColors.bone,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detail != null)
          Text(
            detail!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(
              color: FarlyColors.mist.withValues(alpha: 0.7),
            ),
          ),
      ],
    );
    if (titleSemantics != null) {
      titles = Semantics(
        container: true,
        button: true,
        label: titleSemantics,
        excludeSemantics: true,
        child: titles,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (divider) FarlyListDivider(inset: dividerInset),
        InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? const Color(0x0FFFFFFF)
                : Colors.transparent,
          ),
          splashFactory: NoSplash.splashFactory,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: detail == null ? 56 : 64),
            child: Padding(
              padding: padding,
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(child: titles),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
