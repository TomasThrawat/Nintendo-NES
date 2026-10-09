# NES local Wi-Fi receiver/controller

## Roles

- **Receiver APK** runs on the emulator device. It starts/stops a listener, shows IPv4 addresses and UDP port, creates a fresh 16-character pairing code each time it starts, displays live connection state and a volatile accepted-frame count, and routes the NES button mask into the in-process `NesController`.
- **Controller APK** is a separate second-app entry point containing only receiver IP/code fields and eight NES buttons: Up, Down, Left, Right, A, B, Select, and Start.
- Like WiFiPad, the controller emits small UDP input datagrams to the receiver at approximately 60 Hz. Unlike WiFiPad's generic gamepad packet, this protocol carries only NES buttons and writes directly into the NES emulator's controller state. It does not use Shizuku or system-wide `uinput`.

## UDP wire protocol

The receiver listens on UDP port `27191`, matching WiFiPad's default receiver port. Each datagram is exactly 24 bytes: magic (`N`), protocol version, packet type, 32-bit little-endian sequence, 8-bit NES button mask/status, and a 16-byte truncated HMAC-SHA-256. Frames with the wrong size, version, type, pairing-code MAC, or stale sequence are ignored.

The host issues a signed acknowledgement for accepted frames so the controller can report real receiver reachability. Input sequence checks allow uint32 wraparound while rejecting duplicate/replayed datagrams. The host only accepts one active controller; the first valid authenticated sender becomes the peer. A 750 ms watchdog releases all pressed buttons when frames stop arriving. The sender emits the current button state repeatedly and sends several all-buttons-up frames on disconnect.

The pairing code is generated with a cryptographically secure random source and is replaced each time the receiver starts. Only the code is displayed to the user. The HMAC authenticates input datagrams, and no handshake/account/cloud service is required.

## Network changes and privacy

The receiver binds local IPv4 interfaces and offers a refresh button if Wi-Fi changes. Restart the receiver to get a fresh pairing code. The controller can reconnect by re-entering the receiver address/code. IP addresses, current input state, counts, and connection status are held in memory only; there is no persistent network log, analytics, telemetry, cloud, or relay.

The transport authenticates frames and protects integrity but does not encrypt UDP payloads. Use a trusted local Wi-Fi network. The Android manifest requests only `android.permission.INTERNET` for local sockets; it does not request location or Wi-Fi scan permissions.

## Verification

CI tests fixed-size packets, HMAC tampering, stale sequence rejection, host/client UDP loopback, simultaneous NES input, and input release on disconnect. It builds and inspects both arm64-only APKs. **Two-physical-device Wi-Fi testing is still required before claiming the connection acceptance criterion complete.** Full NES gameplay is also not yet available because PPU rendering, APU audio, and frame scheduling remain incomplete.
