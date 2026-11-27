import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/feedback_log.dart';
import '../theme/farly_colors.dart';
import '../widgets/farly_press.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _text = TextEditingController();
  var _includeLog = true;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    bool opened;
    try {
      opened = await launchUrl(
        feedbackUri(_text.text, includeLog: _includeLog),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false; // no browser or a platform error: show the same message
    }
    if (!mounted) return;
    if (opened) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Send feedback'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _text,
              minLines: 5,
              maxLines: 10,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: FarlyColors.bone),
              cursorColor: FarlyColors.horizon,
              decoration: InputDecoration(
                hintText: 'What happened?',
                hintStyle: const TextStyle(color: FarlyColors.mist),
                filled: true,
                fillColor: const Color(0x14FFFFFF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include diagnostic log'),
              value: _includeLog,
              onChanged: (value) => setState(() => _includeLog = value),
            ),
            if (_includeLog)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text("See what's included", style: theme.bodyMedium),
                children: [
                  SelectableText(
                    feedbackLog.report(),
                    style: theme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Addresses, Wi-Fi and device names, and pairing codes are removed. Very long logs drop the oldest lines to fit.',
                    style: theme.bodySmall,
                  ),
                ],
              ),
            const SizedBox(height: 16),
            FarlyPress(
              label: 'Send',
              icon: Icons.send_rounded,
              filled: true,
              expand: true,
              onPressed:
                  _text.text.trim().isEmpty ? null : () => unawaited(_send()),
            ),
            const SizedBox(height: 8),
            Text(
              'Opens a public GitHub issue. You can edit or cancel before posting. Needs a GitHub account.',
              textAlign: TextAlign.center,
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
