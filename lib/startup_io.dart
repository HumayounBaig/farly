import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'mac/companion_app.dart';

Widget createFarlyRoot() {
  if (Platform.isMacOS) return const FarlyCompanionApp();
  return const FarlyApp();
}
