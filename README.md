# Plazma S

**Native, local-network file and app sharing.**

Plazma S is a Flutter application for moving files between nearby Android and desktop devices without cloud storage or an internet relay.

## Supported platforms

- Android
- Windows
- Linux

The current release pipeline builds Android, Windows, and Linux packages. iOS is not included in the current release configuration.

## What is included

- Local room-based pairing and QR invitations.
- Android hotspot hosting/joining and local-network connections, subject to device and OS support.
- File and folder selection with multi-item transfers.
- Images, videos, music, files, and installed-app browsing.
- Transfer progress, queue controls, retry/cancel actions, and transfer history.
- Resumable downloads and SHA-256 integrity checks.
- Twelve built-in themes: Plazma Light, Plazma Dark, Ocean, Sunset, Forest, Purple, Crimson, Midnight, Obsidian, Black & White, Black & Gold, and Abyssal Amethyst.
- Android app-package handling and installation flows, subject to Android package format and system confirmation requirements.

## Local-only design

Plazma S does not provide cloud file storage, internet transfer, or relay-based transfers. Devices must be able to reach one another over a local Wi-Fi network, Android hotspot, or compatible wired LAN. Wi-Fi client isolation, firewall rules, Android permissions, and device-specific hotspot restrictions can prevent connections.

## Important limitations

- Physical device-to-device testing is still required for each device/network combination; a successful CI build does not prove real-world transfer performance or compatibility.
- Android may require user confirmation before installing received applications.
- Some Android devices restrict hotspot control and background activity.
- The current LAN transfer and room-control transport should not be treated as end-to-end encrypted. Do not use it for sensitive files until encrypted transport is implemented and independently verified.
- Split-APK bundle handling and installation must be verified on physical Android devices before being considered production-ready.

## Build and test

Install the Flutter stable SDK, then run:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Desktop release builds are produced by the GitHub Actions workflow.

## Project identity

- App name: **Plazma S**
- Dart package: `plazma_s`
- Android application ID: `com.plazma.s`
- Release version: read from `pubspec.yaml`
