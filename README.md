# Nintendo NES / Famicom for Android

An independent Flutter + Dart NES/Famicom emulator project, separate from WiFiPad. No commercial ROMs, copyrighted assets, telemetry, analytics, accounts, cloud services, or relays are bundled or required.

## Two-app layout

- **Nintendo NES Receiver** opens directly to a Wi-Fi receiver screen, with one **Start NES receiver** button. It displays the device IP after starting, the connection state, and received input-frame count. Loading a legally obtained .nes ROM remains optional.
- **NES Wi-Fi Controller** asks for only the receiver IP. After a successful connection it rotates to landscape and displays only the NES D-pad, A, B, Start, and Select controls. Every button can be dragged, resized, or hidden independently; the layout is saved between launches.

The connection follows WiFiPad's direct local Wi-Fi UDP model: the controller sends compact input datagrams at approximately 60 Hz to the receiver. The payload contains only the eight NES buttons and is routed directly to the emulator's in-process controller port, rather than injecting a general Android gamepad through Shizuku/uinput. The controller uses the fixed receiver port automatically; no pairing code is required.

## Current emulator milestone

- iNES/NES 2.0 header parsing and malformed/truncated-file validation.
- NROM (mapper 0) PRG mapping and CPU-visible memory/controller bus.
- The 151 official 6502/Ricoh 2A03 opcodes, flags, instruction-level cycles, page-cross and branch penalties, interrupt entry points, and indirect-JMP wrap behavior. Bus-cycle timing and undocumented opcodes are not implemented.
- NES controller serial strobe/read behavior with simultaneous button presses.
- .nes file picker through Flutter's maintained `file_selector` plugin.
- Pure-black Flutter UI for the receiver and dedicated controller.
- IP-only fixed-size UDP controller packets at ~60 Hz, sequence/replay checks, receiver reachability acknowledgements, a 750 ms failsafe, and button release on disconnect.
- A WiFiPad-style landscape controller with per-button drag positioning, size and visibility settings saved locally.
- Unit tests for CPU/cartridge/controller/protocol behavior, UDP host/client loopback integration, and both Flutter app screens.

**Not playable yet.** PPU graphics, nametable/palette/sprite rendering, vblank/NMI timing integration, APU audio, and frame scheduling are missing. The app reports that limitation rather than faking gameplay. NROM is the only executable mapper; other mapper IDs are rejected.

## Pairing on local Wi-Fi

1. Install **Nintendo NES Receiver** on the TV/host device and press **Start NES receiver**.
2. Copy its displayed IPv4 address.
3. Open **NES Wi-Fi Controller** on the second device, enter only that IP address, and connect.
4. The controller automatically rotates to landscape. Drag buttons or use **Edit controls** to customize positions, size, and visibility; changes are saved. Disconnect or stop the receiver to release all buttons.

Both devices must share the same trusted local Wi-Fi. Internet, accounts, cloud relays, Shizuku, and a pairing code are not required. To match WiFiPad's simple IP-only flow, input datagrams are not cryptographically authenticated; anyone with access to the same local network could send button input while the receiver is listening. Do not expose the receiver port to the internet. Loopback tests do not replace tests on two physical Android devices and a real Android TV.

## CI builds

Analysis, tests, coverage and security auditing use the reusable workflow pinned to the full commit SHA `92cded954be5653a48fada29e926e4a3e4f402b7` that the upstream README explicitly documents for the enhanced reusable workflow ([source commit](https://github.com/TomasThrawat/hyouka-flutter-workflows/commit/92cded954be5653a48fada29e926e4a3e4f402b7)). A separate local job is retained for building the two Android product flavors because the shared workflow's standard build path creates a single APK. The pinned reusable workflow calls `scripts/ci_enhancements.py` for its warning and quality reports, so that dependency-free helper and its upstream unit tests are vendored from the same documented commit and tested before building. Dependency/outdated reports are informational; CI does not upgrade declared package constraints.

GitHub Actions builds and inspects two APKs:
- `app-receiver-release.apk` — package `com.tomastharwat.nintendo_nes`, bundled for `armeabi-v7a`, `arm64-v8a`, and `x86_64`; Android TV Leanback launcher metadata is included.
- `app-controller-release.apk` — package `com.tomastharwat.nes_controller`, still `arm64-v8a` only.

The CI verifies APK ABI sets, package IDs, launcher labels, receiver Leanback metadata, and local-network permissions. Download both from the workflow artifact. Successful build output is not proof of playable NES compatibility.

## Next emulator milestones

1. PPU registers/timing, background/sprite graphics, mirroring, palettes, and vblank/NMI.
2. CPU/PPU frame scheduling and deterministic synchronization.
3. APU channels/mixing/output without blocking Flutter's UI isolate.
4. Licensed homebrew test ROM validation and additional mappers (MMC1, UxROM).
5. Battery-backed saves, reliable save states, configurable controls, and physical gamepads.
6. Test the two dedicated apps on two physical Android devices.
