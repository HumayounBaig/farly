import 'farly_device.dart';

/// Alternate TV “menu” keys. Physical remotes disagree, especially on TCL /
/// Google TV, so Farly lets people try a short list and keep the one that works.
class MenuCommand {
  const MenuCommand({
    required this.id,
    required this.label,
    required this.note,
  });

  final String id;
  final String label;
  final String note;

  static const androidTv = [
    MenuCommand(
      id: 'menu',
      label: 'Menu',
      note: 'Classic Android menu key (KEYCODE_MENU).',
    ),
    MenuCommand(
      id: 'settings',
      label: 'Settings',
      note: 'Often the Menu / gear button on TCL and Google TV.',
    ),
    MenuCommand(
      id: 'allApps',
      label: 'All apps',
      note: 'Google TV apps dashboard — common on TCL remotes.',
    ),
    MenuCommand(
      id: 'tvContentsMenu',
      label: 'TV contents',
      note: 'On-screen TV contents menu.',
    ),
    MenuCommand(
      id: 'contextMenu',
      label: 'Context menu',
      note: 'Media / context menu key.',
    ),
    MenuCommand(
      id: 'info',
      label: 'Info',
      note: 'Program info overlay.',
    ),
    MenuCommand(
      id: 'guide',
      label: 'Guide',
      note: 'Live TV guide.',
    ),
  ];

  static const samsung = [
    MenuCommand(
      id: 'menu',
      label: 'Menu',
      note: 'Samsung MENU key.',
    ),
    MenuCommand(
      id: 'tools',
      label: 'Tools',
      note: 'Quick settings / tools panel.',
    ),
    MenuCommand(
      id: 'contents',
      label: 'Smart Hub',
      note: 'Smart Hub / contents key.',
    ),
    MenuCommand(
      id: 'guide',
      label: 'Guide',
      note: 'Channel guide.',
    ),
    MenuCommand(
      id: 'info',
      label: 'Info',
      note: 'Info overlay.',
    ),
  ];

  static const roku = [
    MenuCommand(
      id: 'info',
      label: 'Info / ★',
      note: 'Roku asterisk / options button.',
    ),
    MenuCommand(
      id: 'search',
      label: 'Search',
      note: 'Opens Roku search.',
    ),
    MenuCommand(
      id: 'replay',
      label: 'Instant replay',
      note: 'Some remotes use this near Menu.',
    ),
  ];

  static const lg = [
    MenuCommand(
      id: 'menu',
      label: 'Menu',
      note: 'LG MENU pointer button.',
    ),
    MenuCommand(
      id: 'info',
      label: 'Info',
      note: 'Info overlay.',
    ),
    MenuCommand(
      id: 'exit',
      label: 'Exit',
      note: 'Exit / close overlays.',
    ),
  ];

  static List<MenuCommand> forBrand(DeviceBrand brand) => switch (brand) {
    DeviceBrand.androidTv => androidTv,
    DeviceBrand.samsung => samsung,
    DeviceBrand.roku => roku,
    DeviceBrand.lg => lg,
    _ => const [],
  };

  /// Saved preference, or a brand default. TCL Android TVs prefer Settings.
  static String resolvedId(FarlyDevice device) {
    final saved = device.menuCommand?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    return defaultIdFor(device);
  }

  static String defaultIdFor(FarlyDevice device) {
    if (device.brand == DeviceBrand.androidTv && _looksLikeTcl(device.name)) {
      return 'settings';
    }
    return switch (device.brand) {
      DeviceBrand.roku => 'info',
      DeviceBrand.samsung ||
      DeviceBrand.lg ||
      DeviceBrand.androidTv => 'menu',
      _ => 'menu',
    };
  }

  static MenuCommand? find(DeviceBrand brand, String id) {
    for (final command in forBrand(brand)) {
      if (command.id == id) return command;
    }
    return null;
  }

  static bool _looksLikeTcl(String name) {
    final lower = name.toLowerCase();
    return lower.contains('tcl') || lower.contains('google tv');
  }
}
