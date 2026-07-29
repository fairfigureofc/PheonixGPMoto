# PheonixGPMoto

Native iOS proof of concept for measuring how quickly an E87/L8 badge can accept
successive navigation-style JPEG updates over BLE.

> [!NOTE]
> **Archived hardware experiment:** BLE authentication and image transfer were
> successfully reverse engineered, but the stock firmware on the tested E38
> badge requires the badge to remain in pairing mode while connected. In that
> mode the display does not automatically refresh after receiving an image.
> This makes the stock badge unsuitable for dependable turn-by-turn navigation.
> The implementation remains here as a reference for anyone experimenting with
> BLE image transfer to generic Jieli-based badges.

PheonixGPMoto is continuing with an ESP32 touchscreen using the ILI9341 display
driver (240x320, SKU E32R28T), where the application can control screen refreshes
directly.

## What it does

- Scans for E87, L8, X9, and LED Badge peripherals.
- Connects with CoreBluetooth and performs the Jieli RCSP authentication handshake.
- Renders compact 368x368 left/right navigation JPEGs.
- Alternates them at a configurable interval.
- Records JPEG size, encode time, BLE upload time, total cycle time, and failures.
- Includes an offline Face Lab for comparing centered navigation layouts before
  the badge is available.

## Badge Face Lab

The **Face Lab** tab renders the intended information hierarchy: the next exit or
street name, distance, then a simple left, straight, or right arrow. It currently
supports clean, divider, and exit-shield treatments.

Each treatment can be encoded using the E87-compatible encoder, UIKit, Image I/O,
or a true one-component grayscale Image I/O path. The lab reports the exact JPEG
size, 490-byte transfer chunk count, and whether the image fits inside the E87's
3,920-byte transfer window. It can also export the compressed JPEG through the
iOS share sheet.

Physical-device testing found that Apple's JPEG encoders use image-optimized
Huffman tables that the badge accepts over BLE but renders as a black screen.
The E87-compatible path instead emits a baseline, one-component JFIF with the
fixed standard luminance tables used by the working web uploader. It is now the
default for both Face Lab and cadence tests. UIKit and Image I/O remain available
only for size and decoder comparisons.

This is a transport benchmark, not a navigation app. It deliberately excludes a
maps SDK until the badge update cadence has been measured on real hardware.

## Open and run

1. Install and launch full Xcode.
2. Install XcodeGen (`brew install xcodegen`).
3. From this directory run `xcodegen generate`.
4. Open `PheonixGPMoto.xcodeproj`.
5. Select your development team and a physical iPhone target.
6. Wake the badge, launch the app, tap **Scan**, and select the badge.

Bluetooth testing requires a physical iPhone. The Simulator cannot communicate
with the badge.

## Formatting and checks

The project uses SwiftFormat with rules stored in the repository root. Before
committing Swift changes, run:

```sh
swiftformat --lint --cache ignore ios/PheonixGPMoto ios/ProtocolSelfTest
```

## Test protocol

Start at 2.0 seconds for 20 cycles, then try 1.0, 0.5, and 0.25 seconds. A cadence
is viable only if all transfers succeed and the upload p95 stays below the chosen
interval. The app measures transport completion; visually verify when the badge
screen actually changes because the E87 provides no display-presented callback.
