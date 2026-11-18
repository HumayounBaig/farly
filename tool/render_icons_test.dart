// Renders every platform icon from FarlyMarkPainter.
// Run with: flutter test tool/render_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:farly/widgets/farly_mark.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<void> _render(
  String path,
  int pixels, {
  bool background = true,
  bool glyph = true,
  bool rounded = false,
  double inset = 0,
  bool alpha = true,
  bool template = false,
}) async {
  final recorder = ui.PictureRecorder();
  FarlyMarkPainter(
    background: background,
    glyph: glyph,
    rounded: rounded,
    inset: inset,
    template: template,
  ).paint(Canvas(recorder), Size.square(pixels.toDouble()));
  final image = await recorder.endRecording().toImage(pixels, pixels);
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  var decoded = img.Image.fromBytes(
    width: pixels,
    height: pixels,
    bytes: raw!.buffer,
    numChannels: 4,
  );
  if (!alpha) decoded = decoded.convert(numChannels: 3);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(decoded));
}

void main() {
  testWidgets('render Farly icons', (tester) async {
    await tester.runAsync(() async {
      const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final (name, pixels) in [
        ('20x20@1x', 20),
        ('20x20@2x', 40),
        ('20x20@3x', 60),
        ('29x29@1x', 29),
        ('29x29@2x', 58),
        ('29x29@3x', 87),
        ('40x40@1x', 40),
        ('40x40@2x', 80),
        ('40x40@3x', 120),
        ('60x60@2x', 120),
        ('60x60@3x', 180),
        ('76x76@1x', 76),
        ('76x76@2x', 152),
        ('83.5x83.5@2x', 167),
        ('1024x1024@1x', 1024),
      ]) {
        await _render('$ios/Icon-App-$name.png', pixels, alpha: false);
      }

      const launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
      await _render('$launch/LaunchImage.png', 120, rounded: true);
      await _render('$launch/LaunchImage@2x.png', 240, rounded: true);
      await _render('$launch/LaunchImage@3x.png', 360, rounded: true);

      const res = 'android/app/src/main/res';
      for (final (density, scale) in [
        ('mdpi', 1.0),
        ('hdpi', 1.5),
        ('xhdpi', 2.0),
        ('xxhdpi', 3.0),
        ('xxxhdpi', 4.0),
      ]) {
        final dir = '$res/mipmap-$density';
        await _render(
          '$dir/ic_launcher.png',
          (48 * scale).round(),
          rounded: true,
        );
        await _render(
          '$dir/ic_launcher_background.png',
          (108 * scale).round(),
          glyph: false,
          alpha: false,
        );
        await _render(
          '$dir/ic_launcher_foreground.png',
          (108 * scale).round(),
          background: false,
          inset: 0.17,
        );
        await _render(
          '$dir/launch_mark.png',
          (96 * scale).round(),
          rounded: true,
        );
      }

      await _render('web/favicon.png', 32, rounded: true);
      await _render('web/icons/Icon-192.png', 192, rounded: true);
      await _render('web/icons/Icon-512.png', 512, rounded: true);
      await _render('web/icons/Icon-maskable-192.png', 192, inset: 0.1);
      await _render('web/icons/Icon-maskable-512.png', 512, inset: 0.1);
      await _render('docs/farly-icon.png', 1024, rounded: true);

      const mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final pixels in [16, 32, 64, 128, 256, 512, 1024]) {
        await _render('$mac/app_icon_$pixels.png', pixels, rounded: true);
      }

      const menuBar = 'macos/Runner/Assets.xcassets/MenuBarIcon.imageset';
      await _render('$menuBar/menubar_18.png', 18, rounded: true);
      await _render('$menuBar/menubar_36.png', 36, rounded: true);
      await _render('$menuBar/menubar_54.png', 54, rounded: true);

      const menuBarMono =
          'macos/Runner/Assets.xcassets/MenuBarIconMono.imageset';
      await _render(
        '$menuBarMono/menubar_mono_18.png',
        18,
        background: false,
        template: true,
        inset: 0.08,
      );
      await _render(
        '$menuBarMono/menubar_mono_36.png',
        36,
        background: false,
        template: true,
        inset: 0.08,
      );
      await _render(
        '$menuBarMono/menubar_mono_54.png',
        54,
        background: false,
        template: true,
        inset: 0.08,
      );
    });
  });
}
