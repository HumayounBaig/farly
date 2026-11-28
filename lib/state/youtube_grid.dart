import '../models/remote_action.dart';

/// YouTube's TV search keyboard: a 7-column letter grid, with SPACE, CLEAR
/// and SEARCH buttons on a row below it. Focus starts on "A" (row 0, col 0).
const youtubeGridRows = ['ABCDEFG', 'HIJKLMN', 'OPQRSTU', "VWXYZ-'"];

typedef GridCursor = ({int row, int col});

const youtubeGridStart = (row: 0, col: 0);

/// Where focus sits after pressing SPACE: back on the letter above it.
const _afterSpace = (row: 3, col: 0);

class YoutubeGridPlan {
  const YoutubeGridPlan({
    this.actions = const [],
    this.end = youtubeGridStart,
    this.unsupported = const [],
  });

  final List<RemoteAction> actions;
  final GridCursor end;

  /// Characters the grid cannot type; when set, [actions] is empty.
  final List<String> unsupported;

  String? get error => unsupported.isEmpty
      ? null
      : 'YouTube’s keyboard cannot type ${unsupported.join(' ')} from Farly. '
            'Remove it, or search another way.';
}

/// Key presses that type [text] from [from]. Shortest Manhattan path inside
/// the letter grid; never wraps and never presses Left from column 0.
YoutubeGridPlan youtubeGridActions(
  String text, {
  GridCursor from = youtubeGridStart,
}) {
  final bad = <String>[];
  for (final c in text.split('')) {
    final ok =
        c == ' ' || youtubeGridRows.any((r) => r.contains(c.toUpperCase()));
    if (!ok && !bad.contains(c)) bad.add(c);
  }
  if (bad.isNotEmpty) return YoutubeGridPlan(unsupported: bad);

  final out = <RemoteAction>[];
  var at = from;
  void goTo(GridCursor to) {
    final vertical = to.row > at.row ? RemoteAction.down : RemoteAction.up;
    final horizontal = to.col > at.col ? RemoteAction.right : RemoteAction.left;
    out
      ..addAll(List.filled((to.row - at.row).abs(), vertical))
      ..addAll(List.filled((to.col - at.col).abs(), horizontal));
    at = to;
  }

  for (final c in text.toUpperCase().split('')) {
    if (c == ' ') {
      goTo(_afterSpace);
      out.addAll([RemoteAction.down, RemoteAction.select, RemoteAction.up]);
      continue;
    }
    final row = youtubeGridRows.indexWhere((r) => r.contains(c));
    goTo((row: row, col: youtubeGridRows[row].indexOf(c)));
    out.add(RemoteAction.select);
  }
  return YoutubeGridPlan(actions: out, end: at);
}

/// Presses the on-screen SEARCH button from [from]: down to SPACE, then right
/// twice. shortcut: the columns under SEARCH are unverified on a real TV.
List<RemoteAction> youtubeSearchActions(GridCursor from) => [
  ...List.filled(3 - from.row, RemoteAction.down),
  ...List.filled(from.col, RemoteAction.left),
  RemoteAction.down,
  RemoteAction.right,
  RemoteAction.right,
  RemoteAction.select,
];
