# Plazma S

**Fast, secure, cross-platform local network file and app sharing.**

Plazma S is a native application project for transferring files and application packages between Android and desktop devices on the same reachable local network.

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

## Technology

- Flutter / Dart for the cross-platform application and shared logic
- Native platform adapters where operating-system APIs require them
- Direct local-network connections for data transfer
- Explicitly framed protocol messages over TCP; transfer payloads will use a separate chunked data path

## Current development status

The initial repository foundation is in progress:

- [x] Flutter package manifest and Dart lint configuration
- [x] Bounded, length-prefixed JSON frame codec
- [x] Initial protocol codec unit tests
- [ ] Confirm Flutter analysis and tests in CI (not yet verified)
- [x] TCP transport, client connections, and receiver
- [x] Room ID generation and host-side room lifecycle (in-memory)
- [x] Join requests, approval/rejection, lock, capacity, PIN verifier hook, kick, and close
- [ ] Network room messages, authenticated sessions, QR pairing, and mDNS discovery
- [ ] File and folder transfer
- [ ] Resume and SHA-256 verification
- [ ] Android and desktop app/package sharing
- [ ] Theme system and UI

The current protocol codec is a small framing primitive, not a complete network transport or a claim that transfers are already working.

## Development

Install the Flutter SDK, then run:

```sh
flutter pub get
flutter analyze
flutter test
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
