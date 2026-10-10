# NES-Style Wi-Fi Gamepad

## Setup
1. Start Shizuku on the Android TV using Wireless debugging pairing.
2. Open **NES-Style Gamepad Receiver**, tap **Start gamepad receiver**, and grant Shizuku permission. It registers an Xbox 360-compatible system virtual gamepad via `uinput`, then listens on UDP port `27191`.
3. On the phone, open **NES-Style Wi-Fi Controller**, enter the TV IPv4 address, and connect. The phone switches to landscape with D-pad, A, B, START, and SELECT. Buttons can be moved, resized, or hidden separately.

A standard Android app cannot inject controller input into unrelated apps on its own. Shizuku shell access is required on the TV. Firmware support for `uinput` and input mappings varies.

## UDP protocol
Packets are exactly eight bytes: magic `0x4e`, version `2`, type (`0` input, `1` ACK), a little-endian unsigned 32-bit sequence, and a one-byte button mask. The mask bits represent A, B, SELECT, START, Up, Down, Left, Right. Input is sent at approximately 60 Hz. Duplicate/stale sequences are rejected; a 750 ms receiver watchdog releases all controls if frames stop.

## Security
UDP is unauthenticated and unencrypted. Use a trusted local Wi-Fi network and never expose port `27191` publicly. CI tests protocol/layout/network logic, but cannot prove a particular TV or game recognizes the virtual gamepad.
