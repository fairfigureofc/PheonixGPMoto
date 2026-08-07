# Pheonix Moto ESP32 display firmware

The primary hardware target is now the **Waveshare ESP32-S3-Knob-Touch-LCD-1.8**.
It renders the existing BLE navigation packet on the board's round 360×360
SH8601 AMOLED. The original E32R28T target remains available for experiments
and for the Wokwi rectangular-screen preview.

## Waveshare round display

The new PlatformIO environment is `waveshare-knob-s3`. It uses the board's
ESP32-S3, 16 MB flash, 8 MB octal PSRAM, and the official Waveshare QSPI panel
initialization sequence.

Hardware details and the panel command table come from the
[official Waveshare wiki and demo](https://www.waveshare.com/wiki/ESP32-S3-Knob-Touch-LCD-1.8).
The bundled SH8601 driver retains Espressif's Apache-2.0 license header.

| Display signal | GPIO |
| --- | ---: |
| SH8601 CS | 14 |
| QSPI clock | 13 |
| QSPI data 0–3 | 15, 16, 17, 18 |
| Display reset | 21 |
| Brightness PWM | 47 |
| Touch SDA/SCL (reserved) | 11, 12 |

In VS Code, open the `firmware` folder and run **Terminal → Run Task → Pheonix:
Build Waveshare Knob**, followed by **Pheonix: Upload Waveshare Knob**. If the
USB serial device does not appear or upload cannot connect, unplug the USB-C
connector at the device, rotate it 180°, and reconnect it; the board routes the
two plug orientations to different ESP32 chips.

The navigation view keeps every important element inside the round safe area: a
small Bluetooth glyph and three-line battery gauge sit above the street name,
long instructions wrap across two static lines without distracting animation,
the dot-matrix maneuver and distance stay in the center, and time/distance
remaining sit at the bottom. The battery gauge reads the board's divided GPIO 1
system-voltage input every 30 seconds. The BLE packet format and iPhone app
remain unchanged.

## Original rectangular prototype

This first milestone sends one 64-byte sample navigation packet from the iPhone
to the E32R28T over Bluetooth Low Energy. The ESP32 renders the packet locally
on its ILI9341 display. No map tiles or JPEGs are transferred.

## Hardware confirmed

- LCDWiki/DIYmalls E32R28T
- ESP32-WROOM-32E
- ILI9341, 240×320, 4-wire SPI
- XPT2046 resistive touch (not used in this milestone)

The display is already wired on the board:

| Signal | GPIO |
| --- | ---: |
| TFT CS | 15 |
| TFT DC/RS | 2 |
| TFT SCK | 14 |
| TFT MOSI | 13 |
| TFT MISO | 12 |
| Backlight | 21 |
| Reset | Shared ESP32 EN |

## 1. Install the ESP32 tools

1. Install [Arduino IDE 2](https://www.arduino.cc/en/software).
2. Open **Arduino IDE → Settings**.
3. Add this Board Manager URL:
   `https://espressif.github.io/arduino-esp32/package_esp32_index.json`
4. Open **Tools → Board → Boards Manager**.
5. Search for `esp32` and install **esp32 by Espressif Systems**.
6. Open **Tools → Manage Libraries**.
7. Search for `LovyanGFX` and install it.

The BLE library used by this sketch is included with the Espressif ESP32 board
package.

## 2. Open and flash the firmware

1. Connect the E32R28T with a USB-C data cable.
2. For Arduino IDE use, copy `firmware/PheonixMotoDisplay/main.cpp` to an
   Arduino sketch named `PheonixMotoDisplay.ino`, then open that sketch.
3. Choose **Tools → Board → ESP32 Arduino → ESP32 Dev Module**.
4. Select the new USB serial port under **Tools → Port**.
5. Click **Upload**.
6. If Arduino reports `Connecting...` for a long time, hold the board's
   **BOOT** button, click Upload, and release BOOT when writing begins.

After reset, the display should immediately show the sample `VAN NESS AVE`
navigation screen. Open **Tools → Serial Monitor** at `115200` baud to see
`Pheonix Moto display ready`.

## 3. Build and run the iPhone app

1. In Terminal, run `cd ios && xcodegen generate` if the Xcode project needs to
   be regenerated.
2. Open `ios/PheonixGPMoto.xcodeproj` in Xcode.
3. Select your development team and connected iPhone.
4. Build and run the app.
5. Open the **ESP32 Demo** tab.
6. Tap **Scan for display**.
7. Tap **Connect to Pheonix Moto** when it appears.
8. Adjust the sample data and tap **Send sample navigation**.

The ESP32 display should update immediately. Toggle **Light mode** and send
again to verify that both themes are rendered by the ESP32 rather than the
iPhone.

## Packet version 1

Every test packet is exactly 64 bytes, little-endian:

| Offset | Size | Meaning |
| ---: | ---: | --- |
| 0 | 1 | Protocol version (`1`) |
| 1 | 2 | Sequence number |
| 3 | 1 | Maneuver (`0` straight, `1` left, `2` right) |
| 4 | 1 | Flags (bit 0 requests light mode) |
| 5 | 4 | Distance to next turn, meters |
| 9 | 4 | Total remaining distance, meters |
| 13 | 4 | Total remaining time, seconds |
| 17 | 1 | UTF-8 road-name length |
| 18 | 46 | Road name followed by zero padding |

BLE service: `6F4A0001-6F74-4F4D-8A48-50484F454E58`

Navigation characteristic: `6F4A0002-6F74-4F4D-8A48-50484F454E58`

## What success means

The milestone passes when:

- The ESP32 boots directly into the sample navigation screen.
- The iPhone discovers and connects to `Pheonix Moto`.
- Pressing Send changes the road, maneuver, distance, and theme on the display.
- Repeated packets do not disconnect or restart the ESP32.

Fragment Mono and Google Navigation SDK integration come after this transport
and display loop is reliable.

## Faster development with PlatformIO

After installing VS Code and the PlatformIO extension:

1. In VS Code, choose **File → Open Folder**.
2. Open the repository's `firmware` folder, not the repository root and not the
   `PheonixMotoDisplay` folder inside it.
3. Wait for PlatformIO to finish its first dependency installation and index.
4. Use the ✓ icon in the bottom status bar to build.
5. Use the → icon to upload to the connected E32R28T.
6. Use the plug icon to open the serial monitor at 115200 baud.

The first PlatformIO build still downloads and compiles the ESP32 framework.
Later builds reuse `.pio` and should be much faster. The checked-in
`platformio.ini` fixes the board, framework, LovyanGFX dependency, DIO flash
mode, and reliable 115200 upload speed for the project.

### Fast cached upload

After a successful normal build, choose **Terminal → Run Task → Pheonix: Upload
Existing Firmware** in VS Code. This flashes the existing `firmware.bin`
directly and skips PlatformIO's build checks. Run the normal PlatformIO build
whenever firmware source or font assets change, then use the cached upload task
as many times as needed.

The cached task automatically detects the connected ESP32 serial port. If more
than one compatible USB serial device is connected, run the script directly
with the desired port as its first argument.

### Fragment Mono

The interface uses printable-ASCII subsets of Fragment Mono at three pixel
sizes. The official source font and OFL license are in `assets/fonts`.
Regenerate `PheonixMotoDisplay/fragment_mono.hpp` after changing the configured
sizes with:

```sh
python3 tools/generate_fragment_mono.py
```

### Preview with Wokwi

The checked-in `wokwi.toml` and `diagram.json` simulate an ESP32 DevKit with a
240×320 ILI9341 wired to the same GPIO pins as the E32R28T. Build the firmware,
then press **F1 → Wokwi: Start Simulator** in VS Code. Wokwi loads the existing
PlatformIO binary, so starting and restarting the simulator does not upload to
the physical board.

The simulator verifies boot-state typography and layout. Phone-to-device BLE
behavior should still be verified on the physical ESP32.
