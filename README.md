# Nintendo NES / Famicom for Android

An independent Flutter + Dart NES/Famicom emulator project. It is separate from WiFiPad. Commercial game ROMs, copyrighted assets, BIOS files, telemetry, analytics, accounts, cloud services, and relays are not bundled or required.

## Current milestone

This repository began as a README-only scaffold. The feature branch adds:
- iNES/NES 2.0 header parsing with malformed/truncated-file validation.
- NROM (mapper 0) PRG mapping and CPU-visible memory/controller bus.
- The 151 official 6502/Ricoh 2A03 opcodes, flags, instruction-level cycles, page-cross and branch penalties, interrupt entry points, and indirect-JMP wrap behavior. Bus-cycle timing and undocumented opcodes are not implemented.
- NES controller serial strobe/read behavior with simultaneous buttons.
- .nes file import and a pure-black Flutter UI.
- Local Wi-Fi host/controller using a session pairing code, HMAC challenge-response and signed inputs, a 1 KiB frame cap, monotonic sequence checks, heartbeat timeout, and button release on disconnect.
- CPU/cartridge/controller/protocol tests and an Android arm64 CI build workflow.

**Not playable yet.** PPU graphics, nametable/palette/sprite rendering, vblank/NMI timing integration, APU audio, and frame scheduling are missing. The app reports this rather than faking gameplay. NROM is the only executable mapper; other mapper IDs are rejected.

## Local Wi-Fi controller

On the emulator device choose **Host controller connection** and start the host. On the second device choose **Use this device as controller**, then enter the host's displayed IPv4 address and pairing code. Both devices must share the same local Wi-Fi; internet is not required.

The loopback integration test does not meet the acceptance criterion for two physical Android devices. This remains unverified until that manual test is actually performed. Read docs/WIFI_REMOTE.md for protocol limitations.

## Build locally

Install Flutter stable, then run:

    flutter create . --platforms=android --org=com.tomastharwat --project-name=nintendo_nes

Ensure android.permission.INTERNET is present in android/app/src/main/AndroidManifest.xml. Then run flutter pub get, dart format lib test, flutter analyze, flutter test, and flutter build apk --release --target-platform android-arm64.

The release APK is a build artifact, not proof of playable NES compatibility.

## Next milestones

1. PPU registers/timing, background/sprite graphics, mirroring, palettes, and vblank/NMI.
2. CPU/PPU frame scheduling and deterministic synchronization.
3. APU channels/mixing/output without blocking the Flutter UI isolate.
4. Licensed homebrew test ROM validation and additional mappers (MMC1, UxROM).
5. Battery-backed saves, reliable save states, controller layout settings, and physical gamepads.
6. Two-physical-device Wi-Fi testing; add transport encryption before use on untrusted LANs.
