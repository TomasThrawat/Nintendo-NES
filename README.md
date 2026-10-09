# Nintendo NES / Famicom for Android

An independent Flutter + Dart NES/Famicom emulator project, separate from WiFiPad. No commercial ROMs, copyrighted assets, telemetry, analytics, accounts, cloud services, or relays are bundled or required.

## Two-app layout

- **Nintendo NES Receiver** runs on the device hosting the emulator. It imports a legally obtained .nes ROM and opens the receiver page, which shows the IPv4 address, TCP port, pairing code, connection state, and accepted input-frame count.
- **NES Wi-Fi Controller** is a separate, controller-only app for the second device. Its UI contains only the receiver address/code form and the NES D-pad, A, B, Start, and Select controls. It does not offer a receiver mode or generic gamepad layout.

The role split follows the receiver/controller workflow used by WiFiPad, but the NES receiver does not use Shizuku or system-wide uinput injection. It routes authenticated button state directly to the emulator's NES controller port. Unlike WiFiPad's open UDP packet format, the NES connection uses a temporary pairing code, HMAC challenge-response, and signed input frames.

## Current emulator milestone

- iNES/NES 2.0 header parsing and malformed/truncated-file validation.
- NROM (mapper 0) PRG mapping and CPU-visible memory/controller bus.
- The 151 official 6502/Ricoh 2A03 opcodes, flags, instruction-level cycles, page-cross and branch penalties, interrupt entry points, and indirect-JMP wrap behavior. Bus-cycle timing and undocumented opcodes are not implemented.
- NES controller serial strobe/read behavior with simultaneous button presses.
- .nes file picker through Flutter's maintained `file_selector` plugin.
- Pure-black Flutter UI for the receiver and dedicated controller.
- Local Wi-Fi TCP receiver/controller with a one-session pairing code, HMAC challenge-response and signed input, 1 KiB frame cap, monotonic sequence checks, heartbeat timeout, and automatic button release on disconnect.
- Tests for CPU/cartridge/controller/protocol behavior, host/client loopback integration, and both Flutter entry-point screens.

**Not playable yet.** PPU graphics, nametable/palette/sprite rendering, vblank/NMI timing integration, APU audio, and frame scheduling are missing. The app says this rather than faking a game screen. NROM is the only executable mapper; other mapper IDs are rejected.

## Pairing on local Wi-Fi

1. Install **Nintendo NES Receiver** on the emulator device and open **NES Receiver**.
2. Start the receiver. The screen displays the receiver IPv4 address and a one-session pairing code.
3. Install **NES Wi-Fi Controller** on the second device, enter the receiver address and pairing code, then connect.
4. Hold the NES buttons. The receiver displays connection status and a volatile input-frame count. Disconnect or stop the receiver to release all buttons.

Both devices must share the same local Wi-Fi. Internet, user accounts, cloud relays, and Shizuku are not required. Input frames are authenticated but TCP payloads are not encrypted, so only use trusted local networks. The loopback integration test does not replace a two-physical-device test; real-device acceptance remains unverified.

## CI builds

GitHub Actions builds and inspects two arm64-only APKs:
- `app-receiver-release.apk` — package `com.tomastharwat.nintendo_nes`
- `app-controller-release.apk` — package `com.tomastharwat.nes_controller`

The CI verifies both APKs' ABI, package ID, launcher label, and local-network permissions. Download both from the workflow artifact. A successful build is not proof of playable NES compatibility.

## Next emulator milestones

1. PPU registers/timing, background/sprite graphics, mirroring, palettes, and vblank/NMI.
2. CPU/PPU frame scheduling and deterministic synchronization.
3. APU channels/mixing/output without blocking Flutter's UI isolate.
4. Licensed homebrew test ROM validation and additional mappers (MMC1, UxROM).
5. Battery-backed saves, reliable save states, configurable controls, and physical gamepads.
6. Test the two dedicated apps on two physical Android devices.
