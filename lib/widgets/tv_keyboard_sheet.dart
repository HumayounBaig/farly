import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/farly_colors.dart';
import '../models/remote_action.dart';
import '../state/youtube_grid.dart';
import 'farly_list.dart';
import 'farly_press.dart';
import 'keys.dart';

/// Types into the focused field on the TV (search, PIN, password).
Future<void> showTvKeyboardSheet({
  required BuildContext context,
  required Future<bool> Function(String text) onSend,
  String? Function()? failureDetail,
  Future<void> Function()? onEnter,
  Future<void> Function()? onBackspace,
  Future<bool> Function(String query)? onSearchYoutube,
  bool Function()? youtubeInFront,
  Future<bool> Function(List<RemoteAction> keys)? onSendKeys,
  VoidCallback? onCancelKeys,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TvKeyboardSheet(
      onSend: onSend,
      failureDetail: failureDetail,
      onEnter: onEnter,
      onBackspace: onBackspace,
      onSearchYoutube: onSearchYoutube,
      youtubeInFront: youtubeInFront,
      onSendKeys: onSendKeys,
      onCancelKeys: onCancelKeys,
    ),
  );
}

class _TvKeyboardSheet extends StatefulWidget {
  const _TvKeyboardSheet({
    required this.onSend,
    this.failureDetail,
    this.onEnter,
    this.onBackspace,
    this.onSearchYoutube,
    this.youtubeInFront,
    this.onSendKeys,
    this.onCancelKeys,
  });

  final Future<bool> Function(String text) onSend;
  final String? Function()? failureDetail;
  final Future<void> Function()? onEnter;
  final Future<void> Function()? onBackspace;

  /// Null hides "Search YouTube" (the TV cannot open a search link).
  final Future<bool> Function(String query)? onSearchYoutube;

  /// Done falls back to YouTube search only while YouTube is on screen.
  final bool Function()? youtubeInFront;

  /// Null hides the grid-typing rows.
  final Future<bool> Function(List<RemoteAction> keys)? onSendKeys;
  final VoidCallback? onCancelKeys;

  @override
  State<_TvKeyboardSheet> createState() => _TvKeyboardSheetState();
}

class _TvKeyboardSheetState extends State<_TvKeyboardSheet> {
  final _text = TextEditingController();
  var _obscure = false;
  var _busy = false;
  String? _error;
  int? _gridKeys; // keys left in a grid typing run, for the status line
  GridCursor? _gridEnd; // where YouTube's focus should be after typing

  @override
  void dispose() {
    // Closing the sheet stops a grid run; its Cancel button goes with it.
    if (_gridKeys != null) widget.onCancelKeys?.call();
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final value = _text.text;
    if (value.isEmpty) {
      // After grid typing, Done presses YouTube's own Search key.
      if (_gridEnd != null && widget.onSendKeys != null) await _gridSearch();
      return;
    }
    // Read before the send: the eye can be toggled while it is in flight.
    final password = _obscure;
    var searched = false;
    await _run(() async {
      final landed = await widget.onSend(value);
      if (!mounted) return;
      if (!landed) {
        // No TV text box took it and YouTube is on screen (it draws its own
        // keyboard): search YouTube instead. Never for passwords.
        if (widget.onSearchYoutube != null &&
            !password &&
            (widget.youtubeInFront?.call() ?? false)) {
          searched = await widget.onSearchYoutube!(value.trim());
          if (!mounted) return;
          if (searched) {
            setState(() => _error = null);
            _text.clear();
            HapticFeedback.lightImpact();
            return;
          }
        }
        // Enter would click whatever key the TV's grid has highlighted.
        setState(() => _error = widget.failureDetail?.call());
        return;
      }
      // Android TV password/PIN fields wait for IME Done (KEYCODE_ENTER).
      if (widget.onEnter != null) {
        await widget.onEnter!();
      }
      if (!mounted) return;
      setState(() => _error = null);
      _text.clear();
      HapticFeedback.lightImpact();
    });
  }

  Future<void> _searchYoutube() async {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    await _run(() async {
      final ok = await widget.onSearchYoutube!(value);
      if (!mounted) return;
      setState(() => _error = ok ? null : widget.failureDetail?.call());
    });
  }

  Future<void> _gridType() async {
    final plan = youtubeGridActions(_text.text);
    if (_text.text.isEmpty) return;
    if (plan.error != null) {
      setState(() => _error = plan.error);
      return;
    }
    await _sendKeys(plan.actions, end: plan.end, clear: true);
  }

  Future<void> _gridSearch() =>
      _sendKeys(youtubeSearchActions(_gridEnd!), end: null, clear: false);

  Future<void> _sendKeys(
    List<RemoteAction> keys, {
    required GridCursor? end,
    required bool clear,
  }) async {
    await _run(() async {
      setState(() {
        _error = null;
        _gridKeys = keys.length;
      });
      final ok = await widget.onSendKeys!(keys);
      if (!mounted) return;
      setState(() {
        _gridKeys = null;
        _error = ok
            ? null
            : (widget.failureDetail?.call() ?? 'Typing stopped.');
        if (ok) _gridEnd = end;
        // Cleared so Done cannot press Enter on top of the grid.
        if (ok && clear) _text.clear();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
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
                Expanded(
                  child: Text(
                    'Type on the TV',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Pressable(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  child: KeyFace(
                    icon: _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 44,
                    tint: FarlyColors.horizon,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _obscure
                  ? 'Hidden while you type a password or PIN. Focus the field in a TV app (not a PS5 keyboard), hide the TV’s on-screen keyboard if it is open, then tap Done.'
                  : 'Focus a text box in a TV app, hide the TV’s on-screen keyboard if it covers the field, then type here and tap Done. Game console keyboards (PS5, Xbox) cannot take Farly typing.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              autofocus: true,
              obscureText: _obscure,
              autocorrect: !_obscure,
              enableSuggestions: !_obscure,
              keyboardType: _obscure
                  ? TextInputType.visiblePassword
                  : TextInputType.text,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: FarlyColors.bone, fontSize: 18),
              cursorColor: FarlyColors.horizon,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: _obscure ? 'Password or PIN' : 'Search or text',
                hintStyle: const TextStyle(color: FarlyColors.mist),
                filled: true,
                fillColor: const Color(0x14FFFFFF),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
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
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (widget.onSearchYoutube != null ||
                widget.onSendKeys != null) ...[
              const SizedBox(height: 14),
              FarlyListGroup(
                inset: 16,
                children: [
                  if (widget.onSearchYoutube != null)
                    FarlyListRow(
                      title: 'Search YouTube',
                      detail: 'Opens the results on the TV',
                      onTap: _busy ? null : _searchYoutube,
                    ),
                  if (widget.onSendKeys != null)
                    FarlyListRow(
                      title: 'Type on YouTube’s keyboard',
                      detail: 'Open YouTube search first, with A highlighted',
                      onTap: _busy ? null : _gridType,
                    ),
                  if (widget.onSendKeys != null && _gridEnd != null)
                    FarlyListRow(
                      title: 'Press Search on YouTube’s keyboard',
                      detail: 'Moves to the on-screen Search button',
                      onTap: _busy ? null : _gridSearch,
                    ),
                ],
              ),
            ],
            if (_gridKeys != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Typing on YouTube… ($_gridKeys keys)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onCancelKeys,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.onBackspace != null) ...[
                  RoundKey(
                    icon: Icons.backspace_outlined,
                    label: 'Backspace on TV',
                    size: 52,
                    onPressed: _busy ? null : () => _run(widget.onBackspace!),
                  ),
                  const SizedBox(width: 10),
                ],
                if (widget.onEnter != null) ...[
                  RoundKey(
                    icon: Icons.keyboard_return_rounded,
                    label: 'Done on TV without retyping',
                    size: 52,
                    onPressed: _busy ? null : () => _run(widget.onEnter!),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FarlyPress(
                    label: _busy ? 'Sending' : 'Done',
                    icon: Icons.done_rounded,
                    filled: true,
                    expand: true,
                    onPressed: _busy ? null : () => _send(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
