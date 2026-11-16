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

## Connection types

The Home screen offers three explicit transfer routes:

- **PC to PC** — Windows, macOS, and Linux desktop devices.
- **Android to Android** — Android phones and tablets.
- **Android ↔ PC** — cross-platform transfers in either direction.

The selected route filters discovered destinations to the matching platform type. All routes remain local-network-only.

## Web preview

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
- [x] CI release builds for Windows, macOS and Linux desktop apps
- [ ] Install and smoke-test the first Android APK on a physical device
- [ ] Network room messages, authenticated sessions, QR pairing, and room-aware mDNS discovery
- [ ] Folder transfer and resumable transfer
- [x] Single-file native LAN transfer with SHA-256 verification and receiver acknowledgement
- [x] Native file and folder picker UI with multi-file selection
- [x] Android installed-app browser with names, icons, versions, selection, and base APK path inspection
- [x] Windows installed-app browser with extracted executable icons
- [x] Linux installed-app browser with icons resolved from desktop entries and icon themes
- [x] Windows and Linux local Images, Videos, and Music libraries with selection and deletion
- [x] Local mDNS discovery and nearby Plazma S device list
- [ ] Authenticated device connections and room pairing
- [ ] Android split-APK extraction and complete app/package sharing
- [ ] Complete theme system and settings UI

The native transfer screen now supports the same HTTP transfer protocol on Android and desktop: Android can host its private hotspot, while desktop hosts bind to the active private LAN address and accept connections from other PCs or Android devices. Desktop receivers can paste a Plazma S connection code; Android receivers can scan the sender QR code. For cross-platform transfers, connect both devices to the same Wi-Fi or connect the PC manually to the Android sender's hotspot before pairing. Desktop firewall rules may need to allow Plazma S on private networks. The service supports multi-file transfers, resumable HTTP range downloads, and SHA-256 verification. Android app installation remains Android-only. Desktop builds include local media browsing for the standard Pictures, Videos, Music, Downloads and Desktop folders; installed-app entries display their platform icon where the operating system provides one. Desktop app bundling is still limited by each app's packaging and installation method. This cross-platform path still needs CI desktop builds and physical PC/Android transfer testing before it can be considered verified. The TCP/HTTP payload is not yet encrypted, and room membership is not yet used as authorization.

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
