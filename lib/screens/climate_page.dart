import 'package:flutter/material.dart';

import '../models/farly_device.dart';
import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import '../widgets/bottom_aligned.dart';
import '../widgets/device_glyph.dart';
import '../widgets/farly_backdrop.dart';
import '../widgets/farly_pill.dart';
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
      body: FarlyBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      children: [
                        DeviceGlyph(device: device, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  device.brand.label,
                                  if (device.host != null) device.host!,
                                ].join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const FarlyPill(
                          label: 'Limited',
                          color: FarlyColors.mist,
                          dot: true,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: BottomAligned(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      children: [
                        Center(
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  FarlyColors.mist.withValues(alpha: 0.16),
                                  FarlyColors.mist.withValues(alpha: 0),
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Container(
                              width: 132,
                              height: 132,
                              decoration: FarlySurfaces.glassDisc,
                              child: const Icon(
                                Icons.ac_unit_rounded,
                                size: 56,
                                color: FarlyColors.mist,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          note,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FarlyPress(
                          label: 'Back to devices',
                          icon: Icons.arrow_back_rounded,
                          expand: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
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
