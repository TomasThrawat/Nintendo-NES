# NES-Style Wi-Fi Gamepad for Android TV

Use an Android phone as an NES-style Wi-Fi controller for games already running on an Android TV. **This is not an NES emulator and does not load ROMs.**

## Apps
- **NES-Style Gamepad Receiver** runs on the TV. Press **Start gamepad receiver** to register a system-wide virtual gamepad and listen on UDP port `27191`. Enter the displayed IPv4 address on the phone.
- **NES-Style Wi-Fi Controller** runs on the phone. Enter only the TV IP, connect, and the screen switches to landscape with D-pad, A, B, SELECT, and START. Each control can be moved, resized, or hidden independently.

## TV setup
A regular Android app cannot inject gamepad events into other apps merely by receiving UDP packets. The TV receiver uses Shizuku's shell-privileged user service to run Android's `uinput` command and register an Xbox 360-compatible virtual controller. Games can then receive input through Android's system input stack. This requires TV firmware with usable `uinput` support; compatibility is not guaranteed on every TV.

1. Enable Developer options and **Wireless debugging** on the TV.
2. Install Shizuku on the TV, pair through **Pair device with pairing code**, then tap **Start** in Shizuku.
3. Open **NES-Style Gamepad Receiver**, start the receiver, and grant Shizuku permission.
4. Confirm the receiver reports a registered gamepad and shows the TV IP.
5. On the phone, open **NES-Style Wi-Fi Controller**, enter that IP, and connect.
6. Use **Edit controls** to move, resize, or hide buttons. Disconnecting or stopping the receiver releases inputs.

After a TV reboot, Shizuku usually must be started again but does not need re-pairing. No root, PC, cloud relay, or Shizuku on the phone is required.

Both devices must share the same trusted Wi-Fi. UDP port `27191` is unauthenticated and unencrypted; never expose it to the internet.

## CI and limitations
CI analyzes/tests Flutter, generates the Kotlin/AIDL bridge, builds three separate APKs, and verifies each APK's exact native ABI alongside package IDs, TV launcher metadata, and permissions. It keeps dependency constraints unchanged. The reusable workflow is pinned to upstream commit `92cded954be5653a48fada29e926e4a3e4f402b7`. The phone controller is `arm64-v8a` only. The Receiver is available as `armeabi-v7a` for 32-bit TVs and `arm64-v8a` for 64-bit TVs. The CI artifact contains all three APKs.

CI cannot test a real TV firmware or game. On the TV, check the device in a gamepad tester, then the intended game. If `uinput` is missing or denied, receiver startup should show an error rather than claim success.
