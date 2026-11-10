# Farly

<img src="docs/farly-icon.png" width="96" alt="Farly icon">

One tap scans the Wi-Fi for televisions and air conditioners, then opens a remote.

## Run

```bash
flutter pub get
flutter run
```

The browser build can show the pad, but it cannot scan a network. Discovery and control run on iOS and Android.

## Icon

The logo is drawn by `FarlyMarkPainter` in `lib/widgets/farly_mark.dart`. After changing it, regenerate the iOS, Android, and web icons:

```bash
flutter test tool/render_icons_test.dart
```

## What this build controls

- **Roku** over its local HTTP remote (keys, Netflix, YouTube)
- **Samsung** over the TV's remote WebSocket, including the allow prompt and saved token
- **LG webOS** over the registration socket, volume commands, and the pointer buttons after the TV accepts Farly

The scan also recognizes Android TV, Apple TV, Chromecast, Sony Bravia, and Broadlink infrared hubs. Those open with an honest note instead of a fake connection. Air-conditioner commands are not sent yet.

## Names and domains

`farly.com`, `farly.io`, `farly.app`, `farly.dev`, and `farly.co` are already registered. `getfarly.com` was free when this project was created. The iOS bundle id is `app.getfarly.farly`.

A Paris app-marketing company already uses the Farly name. Check that trademark before a store submission.

## Network notes

iOS shows a local-network prompt. Roku and many TVs answer SSDP, which also needs Apple's multicast entitlement before that search works on a device. mDNS (Chromecast, Android TV, Apple TV) uses the system discovery API and does not need that entitlement. If a TV does not appear, add it by address.
