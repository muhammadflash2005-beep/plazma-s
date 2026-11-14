# Plazma S

**Fast, secure, cross-platform local network file and app sharing.**

Plazma S is a Flutter application project for transferring files and application packages between Android and desktop devices on the same reachable local network.

## Scope

- Android ↔ Android
- Desktop ↔ Desktop
- Android ↔ Desktop
- Nearby-device discovery and room-based pairing
- Multi-file and folder transfers with progress, speed, and ETA
- Resumable transfers and SHA-256 integrity verification
- Android APK sharing and desktop installer/package sharing
- Five persistent themes

**LAN-only by design.** Plazma S will not include internet transfer mode, relay servers, cloud file storage, or online transfer services. Devices must be connected to the same reachable Wi-Fi, hotspot, or wired LAN. Network client isolation may prevent devices on the same Wi-Fi from communicating.

## Connection types\n\nThe Home screen offers three explicit transfer routes:\n\n- **PC to PC** — Windows, macOS, and Linux desktop devices.\n- **Android to Android** — Android phones and tablets.\n- **PC to Android** — cross-platform transfers in either direction.\n\nThe selected route filters discovered destinations to the matching platform type. All routes remain local-network-only.\n\n## Web preview

The browser preview is being prepared for interface testing. It demonstrates the responsive home screen and local room-code flow. Browser preview mode does **not** provide real LAN device discovery or file transfer; those require the native Android/desktop application.

## Technology

- Flutter / Dart for the cross-platform application and shared logic
- Native platform adapters where operating-system APIs require them
- Direct local-network connections for data transfer
- Explicitly framed protocol messages over TCP; transfer payloads will use a separate chunked data path

## Current development status

- [x] Flutter package manifest and Dart lint configuration
- [x] Bounded, length-prefixed JSON frame codec and unit tests
- [x] TCP transport, client connections, receiver, and loopback tests
- [x] Room ID generation and host-side in-memory room lifecycle
- [x] Join requests, approval/rejection, lock, capacity, PIN verifier hook, kick, and close
- [x] Responsive Flutter web preview and room-code UI
- [x] Five selectable themes with on-device persistence (Light, Dark, Ocean, Sunset, Forest)
- [x] Android APK build pipeline with local-network permissions and downloadable CI artifact
- [ ] Web deployment and browser smoke test
- [ ] Install and smoke-test the first Android APK on a physical device
- [ ] Network room messages, authenticated sessions, QR pairing, and room-aware mDNS discovery
- [ ] File and folder transfer
- [ ] Resume and SHA-256 verification
- [x] Native file and folder picker UI with multi-file selection
- [x] Android installed-app browser with names, icons, versions, selection, and base APK path inspection
- [x] Local mDNS discovery and nearby Plazma S device list
- [ ] Authenticated device connections and room pairing
- [ ] Android split-APK extraction and complete app/package sharing
- [ ] Complete theme system and settings UI

The current native Files screen supports direct single-file and sequential multi-file TCP transfers, six-digit receiver-code authorization, SHA-256 verification, and receiver acknowledgements. It does not yet encrypt TCP traffic, transfer folders, resume interrupted transfers, or use room membership as authorization. The room code remains a local preview and is not yet connected to authenticated network sessions. Device-to-device behavior still requires physical-device testing.

## Development

Install the Flutter SDK, then run:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter build web --release
flutter build apk --release
```

## Security principles

- Never trust a room ID as authentication by itself.
- Authenticate room membership before accepting transfer requests.
- Validate all message sizes and transfer metadata.
- Verify completed files with SHA-256.
- Do not silently install received applications.

## Project identity

- App name: **Plazma S**
- Dart package: `plazma_s`
- Android application ID target: `com.plazma.s`
