import 'package:flutter/material.dart';

import '../models/farly_device.dart';
import '../models/remote_action.dart';
import '../state/remote_controller.dart';
import '../state/room_model.dart';
import '../theme/farly_colors.dart';
import '../widgets/farly_press.dart';
import '../widgets/horizon_pad.dart';

class RemotePage extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.device,
    required this.room,
    this.sessions,
  });

  final FarlyDevice device;
  final RoomModel room;
  final SessionBuilder? sessions;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  late final RemoteController _remote = RemoteController(
    device: widget.device,
    sessions: widget.sessions,
    onCredentials: widget.room.updateDevice,
  );

  @override
  void initState() {
    super.initState();
    _remote.connect();
  }

  @override
  void dispose() {
    _remote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListenableBuilder(
              listenable: _remote,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  children: [
                      Row(
                        children: [
                          _IconPress(
                            label: 'Back to devices',
                            icon: Icons.arrow_back,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.device.name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  widget.device.brand.label,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          _IconPress(
                            label: 'Power',
                            icon: Icons.power_settings_new,
                            onPressed: () => _remote.send(RemoteAction.power),
                          ),
                        ],
                      ),
                      if (_remote.detail != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _remote.detail!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 18),
                      HorizonPad(onAction: _remote.send),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FarlyPress(
                              label: 'Back',
                              onPressed: () => _remote.send(RemoteAction.back),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FarlyPress(
                              label: 'Home',
                              onPressed: () => _remote.send(RemoteAction.home),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FarlyPress(
                              label: 'Vol −',
                              onPressed: () => _remote.send(RemoteAction.volumeDown),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FarlyPress(
                              label: 'Mute',
                              onPressed: () => _remote.send(RemoteAction.mute),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FarlyPress(
                              label: 'Vol +',
                              onPressed: () => _remote.send(RemoteAction.volumeUp),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FarlyPress(
                              label: 'Rewind',
                              onPressed: () => _remote.send(RemoteAction.rewind),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FarlyPress(
                              label: 'Play',
                              onPressed: () => _remote.send(RemoteAction.play),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FarlyPress(
                              label: 'Forward',
                              onPressed: () => _remote.send(RemoteAction.forward),
                            ),
                          ),
                        ],
                      ),
                      if (_remote.session.supports(RemoteAction.input)) ...[
                        const SizedBox(height: 10),
                        FarlyPress(
                          label: 'Input',
                          expand: true,
                          onPressed: () => _remote.send(RemoteAction.input),
                        ),
                      ],
                      if (_remote.session.shortcuts.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            for (final shortcut in _remote.session.shortcuts) ...[
                              Expanded(
                                child: FarlyPress(
                                  label: shortcut.label,
                                  onPressed: () => _remote.launch(shortcut),
                                ),
                              ),
                              if (shortcut != _remote.session.shortcuts.last)
                                const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ],
                    ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _IconPress extends StatelessWidget {
  const _IconPress({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: FarlyColors.raised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: FarlyColors.horizon),
          ),
        ),
      ),
    );
  }
}
