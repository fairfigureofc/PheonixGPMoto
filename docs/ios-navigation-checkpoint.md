# iOS navigation checkpoint

Checkpoint date: August 3, 2026

This checkpoint records the first end-to-end iPhone navigation prototype for
PheonixGPMoto. The ESP32 display is not yet receiving live route guidance; the
phone UI is being used to validate route selection and maneuver progression
before BLE integration.

## Implemented

- Google Maps SDK for iOS through Swift Package Manager.
- API-key configuration through an ignored `Secrets.xcconfig` file and a
  committed example template.
- Places API (New) search for manual starting points and destinations.
- Current-location or manually selected ride origins.
- Routes API route calculation with alternative route choices.
- Avoid-highways and avoid-tolls route options.
- Selectable route polylines, distance, and estimated ride time.
- Route preview with a map and numbered road-by-road maneuver instructions.
- Saved rides with optional descriptions and a visible save confirmation.
- A full-screen, phone-based maneuver display modeled after the ESP32 design.
- Live Core Location updates, distance-to-turn display, basic step advancement,
  arrival handling, and experimental automatic rerouting.
- Two shareable diagnostic CSV files per navigation session:
  - sampled GPS coordinates, accuracy, speed, and course;
  - guidance decisions, displayed distance, active step, off-route state, and
    reroute events.
- Compact diagnostic sampling: GPS every two seconds or after roughly 10 meters
  of movement; guidance on meaningful display/state changes or a ten-second
  heartbeat. State transitions and failures are always recorded.

## Tests completed

### Google services and planning

- Confirmed Google Maps renders on a physical iPhone.
- Confirmed Places API search returns suggestions after enabling and restricting
  the required Google Cloud APIs.
- Confirmed Routes API returns route alternatives after resolving the initial
  HTTP 403 configuration failure.
- Confirmed current/manual origins, destinations, highway avoidance, toll
  avoidance, route selection, route preview, and route saving work on-device.
- Confirmed saved rides persist after the app is closed and reopened.

### UI behavior

- Investigated a 22–30 second destination-keyboard delay. The delay occurs when
  the app is launched with the Xcode debugger attached and Google Maps is
  active. Launching the installed app directly from the iPhone Home Screen
  resolves it.
- Confirmed the Google Maps shared-App-Group console warning is emitted by the
  SDK and does not require adding an App Group entitlement to this app.

### Walking navigation

- Completed an initial outdoor walking test of the phone maneuver screen.
- Result: failed. The app displayed incorrect turns, distance-to-turn sometimes
  moved in the wrong direction, and rerouting was unreliable.
- Confirmed the dual-log export works in a short smoke test.
- Reduced log volume before the next field test so the files remain practical to
  inspect.
- A new five-minute walking test using the sampled logs is in progress. Its CSV
  files will be analyzed before changing navigation behavior again.

## Known navigation weaknesses

The current walking implementation is intentionally experimental and should not
be used for motorcycle guidance.

- It starts at route step zero instead of map-matching the rider to the most
  likely current step.
- Distance-to-turn is straight-line distance to the step endpoint, not remaining
  distance along the road geometry. It can therefore increase while the rider
  is following a curved or indirect road correctly.
- A step advances only when the phone comes within 25 meters of its endpoint.
  GPS drift or a route geometry mismatch can prevent advancement or advance the
  wrong step.
- Off-route distance is approximated using distances to polyline vertices rather
  than the closest point on each line segment. Sparse geometry can make a rider
  appear off-route while still on the correct road.
- Rerouting depends on that approximate off-route calculation, so its trigger is
  not yet trustworthy.
- Remaining time and mileage are estimated from completed step totals rather
  than continuously map-matched route progress.

## Next diagnostic step

Compare `gps-live.csv` and `app-guidance.csv` by timestamp from the same walk.
The analysis should identify:

1. whether the initial step selection matched the rider's actual starting point;
2. where displayed distance diverged from progress along the route;
3. whether step endpoints or GPS accuracy prevented advancement;
4. when off-route readings accumulated and why rerouting did or did not fire;
5. whether the Routes API returned maneuver metadata consistent with the route
   preview.

The likely next implementation is proper map matching: project each GPS fix onto
route segments, track monotonic progress along the selected polyline, associate
that progress with step geometry, and use hysteresis for step advancement and
off-route detection.

## Validation at checkpoint

- SwiftFormat lint passes for the iOS sources.
- An unsigned physical-iOS target build succeeds with Google Maps SDK 10.15.0.
- The real Google API key remains excluded by `.gitignore`; only the example
  configuration is committed.
