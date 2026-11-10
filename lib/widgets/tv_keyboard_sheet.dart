import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/farly_colors.dart';
import 'farly_press.dart';
import 'keys.dart';

/// Types into the focused field on the TV (search, PIN, password).
Future<void> showTvKeyboardSheet({
  required BuildContext context,
  required Future<void> Function(String text) onSend,
  Future<void> Function()? onEnter,
  Future<void> Function()? onBackspace,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TvKeyboardSheet(
      onSend: onSend,
      onEnter: onEnter,
      onBackspace: onBackspace,
    ),
  );
}

class _TvKeyboardSheet extends StatefulWidget {
  const _TvKeyboardSheet({
    required this.onSend,
    this.onEnter,
    this.onBackspace,
  });

  final Future<void> Function(String text) onSend;
  final Future<void> Function()? onEnter;
  final Future<void> Function()? onBackspace;

  @override
  State<_TvKeyboardSheet> createState() => _TvKeyboardSheetState();
}

class _TvKeyboardSheetState extends State<_TvKeyboardSheet> {
  final _text = TextEditingController();
  var _obscure = false;
  var _busy = false;

  @override
  void dispose() {
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
    if (value.isEmpty) return;
    await _run(() async {
      await widget.onSend(value);
      if (!mounted) return;
      _text.clear();
      HapticFeedback.lightImpact();
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
                  ? 'Hidden while you type a password or PIN. Tap Send to put it on the TV.'
                  : 'Focus a field on the TV, then type here and tap Send.',
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
              textInputAction: TextInputAction.send,
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
                    label: 'Enter on TV',
                    size: 52,
                    onPressed: _busy ? null : () => _run(widget.onEnter!),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FarlyPress(
                    label: _busy ? 'Sending' : 'Send to TV',
                    icon: Icons.keyboard_rounded,
                    filled: true,
                    expand: true,
                    onPressed: _busy ? null : _send,
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
