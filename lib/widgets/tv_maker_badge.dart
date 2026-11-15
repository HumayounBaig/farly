import 'package:flutter/material.dart';

import '../models/farly_device.dart';

/// A TV maker's wordmark and signature color. Text only, no logo files.
typedef TvMaker = ({String label, Color color});

const _protocolMakers = <DeviceBrand, TvMaker>{
  DeviceBrand.lg: (label: 'LG', color: Color(0xFFA50034)),
  DeviceBrand.samsung: (label: 'SAMSUNG', color: Color(0xFF1428A0)),
  DeviceBrand.sony: (label: 'SONY', color: Color(0xFF1A1A1A)),
  DeviceBrand.roku: (label: 'ROKU', color: Color(0xFF662D91)),
};

const _xiaomi = (label: 'MI', color: Color(0xFFE8590C));
const _sony = (label: 'SONY', color: Color(0xFF1A1A1A));

/// Makers that ship Android or Google TV, spotted in the name the TV announces.
final _nameMakers = <(RegExp, TvMaker)>[
  (RegExp(r'\btcl'), (label: 'TCL', color: Color(0xFFC8102E))),
  (RegExp(r'\bhisense'), (label: 'HISENSE', color: Color(0xFF00A19B))),
  (RegExp(r'\bhaier'), (label: 'HAIER', color: Color(0xFF0055A5))),
  (RegExp(r'\baqua\b'), (label: 'AQUA', color: Color(0xFF0090C4))),
  (RegExp(r'\bmatrix'), (label: 'HAIER', color: Color(0xFF0055A5))),
  (RegExp(r'\bphilips'), (label: 'PHILIPS', color: Color(0xFF0B5ED7))),
  (RegExp(r'\bsharp'), (label: 'SHARP', color: Color(0xFFD7002F))),
  (RegExp(r'\btoshiba'), (label: 'TOSHIBA', color: Color(0xFFB30000))),
  (RegExp(r'\bxiaomi'), _xiaomi),
  (RegExp(r'\bmi\s?tv'), _xiaomi),
  (RegExp(r'\bbravia'), _sony),
  (RegExp(r'\bsony'), _sony),
  (RegExp(r'\bsamsung'), (label: 'SAMSUNG', color: Color(0xFF1428A0))),
];

/// The maker Farly can tell from the control protocol or the TV's name, or null.
TvMaker? tvMakerOf(FarlyDevice device) {
  if (device.kind != DeviceKind.screen) return null;
  final byProtocol = _protocolMakers[device.brand];
  if (byProtocol != null) return byProtocol;
  final name = device.name.toLowerCase();
  for (final (pattern, maker) in _nameMakers) {
    if (pattern.hasMatch(name)) return maker;
  }
  return null;
}

class TvMakerBadge extends StatelessWidget {
  const TvMakerBadge({super.key, required this.device});

  final FarlyDevice device;

  @override
  Widget build(BuildContext context) {
    final maker = tvMakerOf(device);
    if (maker == null) return const SizedBox.shrink();
    return Semantics(
      label: '${maker.label} TV',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: maker.color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          maker.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
