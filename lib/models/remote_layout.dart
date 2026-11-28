/// Major blocks on the remote pad that the user can reorder or hide.
enum RemoteBlockId {
  powerRow,
  shortcuts,
  transport,
  levels,
  chrome,
  pad,
}

/// Buttons in the chrome / menu row.
enum ChromeId { back, home, menu, keyboard, input, pictureOff }

/// Saved arrangement of the remote pad.
///
/// [blocks] and [chrome] are the visible items in order. Hidden items are
/// simply omitted — same pattern for both lists.
class RemoteLayout {
  const RemoteLayout({required this.blocks, required this.chrome});

  /// Visible major blocks, in order. Hidden ones are omitted.
  final List<RemoteBlockId> blocks;

  /// Visible chrome buttons, in order. Hidden ones are simply omitted.
  final List<ChromeId> chrome;

  static const defaults = RemoteLayout(
    blocks: [
      RemoteBlockId.powerRow,
      RemoteBlockId.shortcuts,
      RemoteBlockId.transport,
      RemoteBlockId.chrome,
      // Levels sit beside the pad when adjacent (default).
      RemoteBlockId.levels,
      RemoteBlockId.pad,
    ],
    chrome: [
      ChromeId.back,
      ChromeId.home,
      ChromeId.menu,
      ChromeId.keyboard,
      ChromeId.input,
      ChromeId.pictureOff,
    ],
  );

  RemoteLayout copyWith({
    List<RemoteBlockId>? blocks,
    List<ChromeId>? chrome,
  }) {
    return RemoteLayout(
      blocks: blocks ?? this.blocks,
      chrome: chrome ?? this.chrome,
    );
  }

  bool get isDefault {
    if (blocks.length != defaults.blocks.length) return false;
    if (chrome.length != defaults.chrome.length) return false;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i] != defaults.blocks[i]) return false;
    }
    for (var i = 0; i < chrome.length; i++) {
      if (chrome[i] != defaults.chrome[i]) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'blocks': [for (final block in blocks) block.name],
    'chrome': [for (final item in chrome) item.name],
    'chromeV': 2,
  };

  factory RemoteLayout.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'];
    final rawChrome = json['chrome'];
    final blocks = <RemoteBlockId>[];
    if (rawBlocks is List) {
      for (final item in rawBlocks) {
        if (item is! String) continue;
        for (final value in RemoteBlockId.values) {
          if (value.name == item && !blocks.contains(value)) {
            blocks.add(value);
            break;
          }
        }
      }
    }
    // Empty / missing list → defaults. A partial list means intentional hides.
    if (blocks.isEmpty) blocks.addAll(RemoteLayout.defaults.blocks);

    final chrome = <ChromeId>[];
    if (rawChrome is List) {
      for (final item in rawChrome) {
        if (item is! String) continue;
        for (final value in ChromeId.values) {
          if (value.name == item && !chrome.contains(value)) {
            chrome.add(value);
            break;
          }
        }
      }
    }
    if (chrome.isEmpty) chrome.addAll(RemoteLayout.defaults.chrome);
    // Layouts saved before pictureOff existed show it (when the TV supports it).
    if (json['chromeV'] != 2 && !chrome.contains(ChromeId.pictureOff)) {
      chrome.add(ChromeId.pictureOff);
    }

    return RemoteLayout(blocks: blocks, chrome: chrome);
  }
}
