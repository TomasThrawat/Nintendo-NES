# Local Wi-Fi controller protocol

- The host listens on TCP port 47531 on local IPv4 interfaces and displays detected local addresses. There is no internet discovery or relay.
- The host generates a one-session 16-character code using a cryptographically secure random source. The controller enters the host IP and code; HMAC-SHA-256 challenge/response derives a session key.
- Each input contains a button bitmask, monotonically increasing sequence number, and HMAC. Duplicate/stale sequence numbers are ignored. Newline-delimited JSON frames are capped at 1,024 bytes.
- One controller may be paired at a time. Failed pairing attempts are rate-limited, and every button is released when the client disconnects or no authenticated input arrives for two seconds.
- No button states or network traffic are persisted. No telemetry, accounts, cloud services, or relay is used.

## Security boundary

The protocol authenticates the paired controller and protects message integrity, but TCP traffic is not encrypted. Use it only on a trusted local network. Stop the host to invalidate the pairing code. The server binds local IPv4 interfaces, so do not leave it active on an untrusted network.

Android requires the INTERNET manifest permission for local TCP sockets. A separate Android local-network runtime permission applies on newer platform targets that enforce it; re-check the [official Android local-network permission guide](https://developer.android.com/privacy-and-security/local-network-permission) before raising target SDK levels.

## Verification

The automated host/client test exercises pairing, simultaneous input, and release on disconnect in a loopback process. It does not replace a two-device physical Wi-Fi test. Do not call the acceptance criterion complete until two separate Android devices have been tested.
