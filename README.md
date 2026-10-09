# Nintendo NES

A dedicated Android emulator project for the Nintendo Entertainment System (NES) / Famicom. This project is intentionally separate from WifiPad and is focused on one console rather than a universal multi-system interface.

## Project goals

- Load locally supplied NES game images (`.nes`) in supported iNES and NES 2.0 formats.
- Implement and test the NES CPU (Ricoh 2A03 / 6502 family), memory map, PPU graphics pipeline, and APU audio path.
- Provide accurate NES controller input, including D-pad, **A**, **B**, **Select**, and **Start**. Start/Select must generate distinct, reliable press and release events.
- Render gameplay smoothly and keep emulation timing independent from UI rendering.
- Support save data where the cartridge uses battery-backed memory, and add save states only after deterministic state capture is reliable.
- Keep the emulator core isolated from the Android UI so CPU, memory, cartridge, graphics, audio, and controller behavior can be tested independently.

## Scope

This repository is for **NES/Famicom only**. It will not host PSP, PlayStation, SNES, Sega, or other console implementations. Those should be separate projects if needed.

No commercial game ROMs, copyrighted game assets, or proprietary BIOS files are included. Use game dumps you are legally entitled to use. This is an independent project and is not affiliated with or endorsed by Nintendo.

## Planned milestones

1. Create the Android app shell and a testable emulator-core module.
2. Implement cartridge parsing, mapper support, memory bus, and CPU instruction tests.
3. Implement PPU rendering and frame timing; validate against public homebrew/test ROMs where their licenses permit.
4. Implement APU audio and timing synchronization.
5. Add touch controls and physical gamepad support; verify Start/Select and A/B on real games.
6. Add game library management, save data, performance profiling, and release APK workflow.

## Current status

**Repository scaffold only.** The emulator core, playable game loop, ROM browser, and APK build pipeline have not been implemented or verified yet. The milestones above are the work plan, not claims of completed features.

## Development principles

- Keep each change small, testable, and tied to a specific emulator subsystem.
- Never bundle copyrighted ROMs in source code or CI artifacts.
- Test input edge cases, especially short button taps and simultaneous inputs.
- Read complete CI/build logs and address real errors and relevant warnings before calling a build complete.
