import 'package:flutter/material.dart';

import '../models/farly_device.dart';
import '../theme/farly_colors.dart';
import '../widgets/farly_press.dart';

class ClimatePage extends StatelessWidget {
  const ClimatePage({super.key, required this.device});

  final FarlyDevice device;

  @override
  Widget build(BuildContext context) {
    final note =
        device.brand.limitation ??
        'Farly can see this air conditioner, but it cannot send commands yet.';
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FarlyPress(
                    label: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 28),
                  Text(device.name, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    [
                      device.brand.label,
                      if (device.host != null) device.host!,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: FarlyColors.field,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(note, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
