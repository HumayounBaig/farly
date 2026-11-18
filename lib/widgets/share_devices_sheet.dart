import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/room_model.dart';
import '../sync/sync_server.dart';
import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import 'farly_press.dart';

/// Starts a short-lived LAN share so the Mac companion can pull saved TVs.
Future<void> showShareDevicesSheet(BuildContext context, RoomModel room) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ShareDevicesSheet(room: room),
  );
}

class ShareDevicesSheet extends StatefulWidget {
  const ShareDevicesSheet({super.key, required this.room});

  final RoomModel room;

  @override
  State<ShareDevicesSheet> createState() => _ShareDevicesSheetState();
}

class _ShareDevicesSheetState extends State<ShareDevicesSheet> {
  final _server = FarlySyncServer();
  var _starting = true;
  String? _error;
  Timer? _ticker;
  var _secondsLeft = 120;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_server.stop());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final source = switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        TargetPlatform.macOS => 'macos',
        _ => 'farly',
      };
      await _server.start(widget.room.exportSyncPayload(source: source));
      if (!mounted) return;
      setState(() {
        _starting = false;
        _secondsLeft = 120;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_secondsLeft <= 1 || !_server.isRunning) {
          timer.cancel();
          Navigator.of(context).maybePop();
          return;
        }
        setState(() => _secondsLeft -= 1);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Could not start sharing on this Wi‑Fi.';
      });
      debugPrint('ShareDevicesSheet: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final endpoint = _server.endpointLabel;
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
            const SizedBox(height: 18),
            Text(
              'Share with Mac',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Keep Farly open. On the Mac, enter this code and the address below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (_starting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: FarlyColors.horizon),
                ),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: FarlyColors.clay))
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: FarlySurfaces.glass(radius: 20),
                child: Column(
                  children: [
                    Text(
                      _server.pin,
                      style: const TextStyle(
                        color: FarlyColors.sunrise,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (endpoint != null) ...[
                      Text(
                        endpoint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: FarlyColors.bone,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Address for the Mac',
                        style: TextStyle(
                          color: FarlyColors.mist,
                          fontSize: 12,
                        ),
                      ),
                    ] else
                      const Text(
                        'Could not read this phone’s Wi‑Fi address.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: FarlyColors.clay, fontSize: 13),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      '${widget.room.devices.length} saved · ${_secondsLeft}s left'
                      '${_server.isAdvertising ? '' : ' · discovery limited'}',
                      style: const TextStyle(
                        color: FarlyColors.mist,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FarlyPress(
                label: 'Copy code + address',
                icon: Icons.copy_rounded,
                expand: true,
                onPressed: () async {
                  final text = [_server.pin, ?endpoint].join('\n');
                  await Clipboard.setData(ClipboardData(text: text));
                },
              ),
            ],
            const SizedBox(height: 10),
            FarlyPress(
              label: 'Done',
              icon: Icons.check_rounded,
              filled: true,
              expand: true,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
