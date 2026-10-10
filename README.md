# Nintendo NES / Famicom for Android

An independent Flutter + Dart NES/Famicom emulator project, separate from WiFiPad. No commercial ROMs, copyrighted assets, telemetry, analytics, accounts, cloud services, or relays are bundled or required.

## Two-app layout

- **Nintendo NES Receiver** runs on the emulator device. It imports a legally obtained .nes ROM and opens the receiver page, displaying the IPv4 address, UDP port, pairing code, connection state, and accepted input-frame count.
- **NES Wi-Fi Controller** is a separate controller-only app for the second device. Its UI contains only the receiver address/code form and NES D-pad, A, B, Start, and Select controls. It has no receiver mode or generic gamepad layout.

The connection follows WiFiPad's local Wi-Fi UDP model: the controller sends compact input datagrams at approximately 60 Hz to the receiver. The important difference is that the payload contains only the eight NES buttons and is routed directly to the emulator's in-process controller port, rather than injecting a general Android gamepad through Shizuku/uinput. A temporary pairing code and HMAC authenticate the datagrams.

## Current emulator milestone

- iNES/NES 2.0 header parsing and malformed/truncated-file validation.
- NROM (mapper 0) PRG mapping and CPU-visible memory/controller bus.
- The 151 official 6502/Ricoh 2A03 opcodes, flags, instruction-level cycles, page-cross and branch penalties, interrupt entry points, and indirect-JMP wrap behavior. Bus-cycle timing and undocumented opcodes are not implemented.
- NES controller serial strobe/read behavior with simultaneous button presses.
- .nes file picker through Flutter's maintained `file_selector` plugin.
- Pure-black Flutter UI for the receiver and dedicated controller.
- UDP controller packets at ~60 Hz, temporary pairing code, HMAC-authenticated frames and acknowledgements, fixed-size payload validation, sequence/replay checks, receiver reachability acknowledgements, 750 ms failsafe, and button release on disconnect.
- Unit tests for CPU/cartridge/controller/protocol behavior, UDP host/client loopback integration, and both Flutter app screens.

**Not playable yet.** PPU graphics, nametable/palette/sprite rendering, vblank/NMI timing integration, APU audio, and frame scheduling are missing. The app reports that limitation rather than faking gameplay. NROM is the only executable mapper; other mapper IDs are rejected.

## Pairing on local Wi-Fi

1. Install **Nintendo NES Receiver** on the emulator device and open **NES Receiver**.
2. Start the receiver. The screen displays its IPv4 address, UDP port, and one-session pairing code.
3. Install **NES Wi-Fi Controller** on the second device, enter the receiver address and pairing code, then connect.
4. Hold the NES buttons. The receiver displays connection state and a non-persistent input-frame counter. Disconnect or stop the receiver to release all buttons.

Both devices must share local Wi-Fi. Internet, accounts, cloud relays, and Shizuku are not required. HMAC protects integrity but the payload is not encrypted, so use a trusted local network. The loopback integration test does not replace the required test on two physical Android devices.

## CI builds

Analysis, tests, coverage and security auditing use the reusable workflow pinned to the full commit SHA `92cded954be5653a48fada29e926e4a3e4f402b7` that the upstream README explicitly documents for the enhanced reusable workflow ([source commit](https://github.com/TomasThrawat/hyouka-flutter-workflows/commit/92cded954be5653a48fada29e926e4a3e4f402b7)). A separate local job is retained for building the two Android product flavors because the shared workflow's standard build path creates a single APK. The pinned reusable workflow calls `scripts/ci_enhancements.py` for its warning and quality reports, so that dependency-free helper and its upstream unit tests are vendored from the same documented commit and tested before building. Dependency/outdated reports are informational; CI does not upgrade declared package constraints.

GitHub Actions builds and inspects two arm64-only APKs:
- `app-receiver-release.apk` — package `com.tomastharwat.nintendo_nes`
- `app-controller-release.apk` — package `com.tomastharwat.nes_controller`

The CI verifies both APKs' ABI, package ID, launcher label, and local-network permissions. Download both from the workflow artifact. Successful build output is not proof of playable NES compatibility.

## Next emulator milestones

1. PPU registers/timing, background/sprite graphics, mirroring, palettes, and vblank/NMI.
2. CPU/PPU frame scheduling and deterministic synchronization.
3. APU channels/mixing/output without blocking Flutter's UI isolate.
4. Licensed homebrew test ROM validation and additional mappers (MMC1, UxROM).
5. Battery-backed saves, reliable save states, configurable controls, and physical gamepads.
6. Test the two dedicated apps on two physical Android devices.
