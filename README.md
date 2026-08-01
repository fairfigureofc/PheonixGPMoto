# PheonixGPMoto

PheonixGPMoto is a proof-of-concept for a simple, distraction-free GPS navigation
badge for motorcycles and bicycles.

Choose a destination in the iPhone app, start the ride, and put the phone away.
The clip-on E87 display badge presents only the turn information needed for the
road ahead—such as the next direction and distance—without a map, notifications,
or another attention-heavy screen.

## The idea

- Enter a destination before riding.
- Clip the compact display somewhere visible.
- Put the phone safely in a pocket or bag.
- Follow minimal turn-by-turn prompts on the badge.

The goal is intentionally narrow: provide enough information to navigate while
keeping the rider's attention on the road.

## Current status

**The generic-badge BLE approach is an archived, unsuccessful hardware
experiment.** Authentication and image transfer work, but the stock firmware on
the tested E38 badge requires pairing mode for the BLE connection. While it is in
pairing mode, the display does not automatically refresh after receiving an
image. That behavior makes the badge unsuitable for dependable turn-by-turn
navigation without replacing its firmware.

The code is intentionally retained for anyone who wants to experiment with BLE
image transfer to generic Jieli-based badges. It documents the protocol work,
successful transfers, JPEG compatibility investigation, and practical firmware
limitation discovered on physical hardware.

The proof of concept includes:

- Native SwiftUI interface
- CoreBluetooth discovery and connection
- Jieli RCSP authentication
- Windowed JPEG transfer to the E87 badge
- Minimal 368×368 navigation-arrow rendering
- Configurable refresh-cadence benchmarking
- Per-update encoding, BLE transfer, average, and p95 timing metrics
- Offline Badge Face Lab for comparing 368×368 navigation treatments and JPEG encoders
- Exportable UIKit, Image I/O, and one-component grayscale JPEG samples
- Byte-budget checks for the 3,500-byte comfort target and 3,920-byte BLE window

The iPhone app builds and runs on a physical phone, but this implementation is no
longer the planned navigation hardware.

See the [iOS prototype instructions](./ios/README.md) to build and run the current
benchmark on a physical iPhone.

The new ESP32 phone-to-display hello world is documented in
[`firmware/README.md`](./firmware/README.md).

## Intended direction

Development is moving to an ESP32 touchscreen with an ILI9341 display driver
(240x320, SKU E32R28T). Direct control of the screen refresh removes the stock
badge firmware limitation. The next phase is to add:

- Destination search and route calculation
- GPS and heading updates
- Simple next-maneuver graphics
- Distance-to-turn updates
- Adaptive refresh intervals to reduce battery and BLE traffic
- A ride mode designed to work while the phone remains put away

This is a proof of concept and should not be treated as a safety-certified
navigation device. Riders remain responsible for road awareness and safe vehicle
operation.

## Archived badge hardware

The archived target is the E38/E87/L8 family of Bluetooth electronic display
badges using the Jieli BLE protocol. Protocol notes are retained in
[PROTOCOL.md](./PROTOCOL.md), with reverse-engineering material under
[`protocol-understanding/`](./protocol-understanding/).

## Acknowledgments

PheonixGPMoto began with the open-source
[AuraCast](https://github.com/Manaiakalani/auracast) codebase. We are grateful to
the AuraCast contributors for the original E87/L8 connectivity implementation,
Jieli authentication work, BLE upload flow, and protocol documentation that made
this experiment possible.

PheonixGPMoto is an independent proof-of-concept project and is not affiliated
with or endorsed by AuraCast.

## License

This project retains the original repository's [MIT License](./LICENSE).
