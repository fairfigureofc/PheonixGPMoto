# PheonixGPMoto

Native iOS proof of concept for measuring how quickly an E87/L8 badge can accept
successive navigation-style JPEG updates over BLE.

## What it does

- Scans for E87, L8, X9, and LED Badge peripherals.
- Connects with CoreBluetooth and performs the Jieli RCSP authentication handshake.
- Renders compact 368x368 left/right navigation JPEGs.
- Alternates them at a configurable interval.
- Records JPEG size, encode time, BLE upload time, total cycle time, and failures.

This is a transport benchmark, not a navigation app. It deliberately excludes a
maps SDK until the badge update cadence has been measured on real hardware.

## Open and run

1. Install full Xcode (the current machine only has Command Line Tools).
2. Install XcodeGen (`brew install xcodegen`).
3. From this directory run `xcodegen generate`.
4. Open `PheonixGPMoto.xcodeproj`.
5. Select your development team and a physical iPhone target.
6. Wake the badge, launch the app, tap **Scan**, and select the badge.

Bluetooth testing requires a physical iPhone. The Simulator cannot communicate
with the badge.

## Test protocol

Start at 2.0 seconds for 20 cycles, then try 1.0, 0.5, and 0.25 seconds. A cadence
is viable only if all transfers succeed and the upload p95 stays below the chosen
interval. The app measures transport completion; visually verify when the badge
screen actually changes because the E87 provides no display-presented callback.
