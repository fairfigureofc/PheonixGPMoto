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

This repository is an early hardware and transport experiment. The native iOS
benchmark currently focuses on the riskiest technical question: how quickly and
reliably an iPhone can refresh navigation-style images on an E87/L8 electronic
display badge over Bluetooth Low Energy.

The proof of concept includes:

- Native SwiftUI interface
- CoreBluetooth discovery and connection
- Jieli RCSP authentication
- Windowed JPEG transfer to the E87 badge
- Minimal 368×368 navigation-arrow rendering
- Configurable refresh-cadence benchmarking
- Per-update encoding, BLE transfer, average, and p95 timing metrics

See the [iOS prototype instructions](./ios/README.md) to build and run the current
benchmark on a physical iPhone.

## Intended direction

Once the badge refresh rate is validated on hardware, the next phase is to add:

- Destination search and route calculation
- GPS and heading updates
- Simple next-maneuver graphics
- Distance-to-turn updates
- Adaptive refresh intervals to reduce battery and BLE traffic
- A ride mode designed to work while the phone remains put away

This is a proof of concept and should not be treated as a safety-certified
navigation device. Riders remain responsible for road awareness and safe vehicle
operation.

## Hardware

The current target is the round E87/L8 family of Bluetooth electronic display
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
