# Nintendo NES local Wi-Fi receiver/controller

## Apps and connection flow

- **Nintendo NES Receiver** starts directly on the receiver screen. Press **Start NES receiver** to listen on UDP port `27191`; the screen shows the receiver's local IPv4 address and connection status.
- **NES Wi-Fi Controller** asks for the receiver's IPv4 address only. The UDP port is fixed and detected by the app, so no pairing code or second field is required. After a successful receiver acknowledgement, the controller switches to landscape and shows the NES D-pad, A, B, Start, and Select.
- Both devices must be on the same trusted local Wi-Fi network. The apps communicate directly; no internet service, account, cloud relay, Shizuku, or generic system gamepad injection is used.

## UDP wire protocol

The receiver and controller share `lib/services/remote_protocol.dart`. Every packet is exactly **8 bytes**:

| Byte offset | Size | Meaning |
|---:|---:|---|
| 0 | 1 byte | Magic value `0x4e` (`N`) |
| 1 | 1 byte | Protocol version `2` |
| 2 | 1 byte | Packet type: `0` input, `1` acknowledgement |
| 3–6 | 4 bytes | Unsigned 32-bit sequence, little-endian |
| 7 | 1 byte | NES button mask for input; value `1` for acknowledgement |

The button-mask bits follow the controller enum order: A, B, Select, Start, Up, Down, Left, Right. The controller sends current input at approximately 60 Hz and emits several all-buttons-up packets when disconnecting. The receiver rejects malformed packets and duplicate/stale sequence numbers, including across uint32 wraparound. It sends an acknowledgement for accepted input so the controller can verify that the receiver is reachable.

The receiver accepts one active peer at a time. A **750 ms** receiver watchdog releases all buttons if input stops; the controller declares the receiver connection lost after approximately **1.5 seconds** without an acknowledgement.

## Security and privacy

This is an intentionally **unauthenticated and unencrypted** IP-only protocol. A device that can send UDP packets to port `27191` on the same network may be able to inject button input while the receiver is listening. Use a trusted local network and do not expose the receiver port to the internet.

Neither app requires a pairing code, account, cloud relay, location permission, or Wi-Fi scanning permission. The Android manifest requests `android.permission.INTERNET` for local sockets. The apps do not persist network input, addresses, or connection logs; controller layout preferences are stored locally.

## Verification and limitations

The automated checks cover CPU/cartridge/controller behavior, packet structure and sequence handling, control-layout persistence, UDP loopback between client and receiver, Flutter analysis/tests, dependency/security reporting, and APK metadata/ABI/permission inspection. The receiver APK is built for `armeabi-v7a`, `arm64-v8a`, and `x86_64`; the controller APK is built for `arm64-v8a` only. These checks do not replace testing on two real devices and an actual Android TV.

**Full NES gameplay is not available yet.** The PPU graphics pipeline, APU audio, and frame scheduler are still incomplete; the app currently validates and loads supported ROM data but does not claim playable emulation.
