import CoreLocation
@preconcurrency import GoogleMaps
import SwiftUI

struct WalkingNavigationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: WalkingNavigationModel

    init(initialRoute: RouteOption, destination: RidePlace, avoidHighways: Bool, avoidTolls: Bool) {
        _model = State(initialValue: WalkingNavigationModel(
            route: initialRoute,
            destination: destination,
            avoidHighways: avoidHighways,
            avoidTolls: avoidTolls
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                statusBar
                Spacer(minLength: 18)
                if let step = model.currentStep {
                    Image(systemName: step.symbolName)
                        .font(.system(size: 88, weight: .bold))
                    Text(model.distanceToTurnText)
                        .font(.system(size: 54, weight: .medium, design: .monospaced))
                        .padding(.top, 20)
                    Text(step.instruction.uppercased())
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                } else {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 80))
                    Text("ARRIVED").font(.system(size: 34, design: .monospaced))
                }
                Spacer()
                HStack {
                    metric(title: "TIME LEFT", value: model.remainingTimeText)
                    Divider().overlay(.white).frame(height: 48)
                    metric(title: "MILES LEFT", value: model.remainingDistanceText)
                }
                .padding(.bottom, 28)
            }
            .foregroundStyle(.white)
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var statusBar: some View {
        HStack {
            Button(model.isEnded ? "Close" : "End", systemImage: "xmark") {
                if model.isEnded {
                    dismiss()
                } else {
                    model.endSession()
                }
            }
            Spacer()
            Menu {
                ShareLink(item: model.gpsLogURL) {
                    Label("Share GPS log", systemImage: "location")
                }
                ShareLink(item: model.guidanceLogURL) {
                    Label("Share guidance log", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
            } label: {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
            }
            Spacer()
            if model.isRerouting {
                Label("Rerouting…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .foregroundStyle(.yellow)
            } else {
                Label(model.gpsStatus, systemImage: "location.fill")
            }
        }
        .font(.system(.footnote, design: .monospaced, weight: .semibold))
        .padding()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(.caption, design: .monospaced))
            Text(value).font(.system(.title3, design: .monospaced, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
@Observable
final class WalkingNavigationModel {
    private let manager = CLLocationManager()
    private var updatesTask: Task<Void, Never>?
    private let destination: RidePlace
    private let avoidHighways: Bool
    private let avoidTolls: Bool
    private var offRouteReadings = 0
    private let logWriter: NavigationLogWriter
    private var lastGPSLogDate: Date?
    private var lastGPSLogLocation: CLLocation?
    private var lastGuidanceLogDate: Date?
    private var lastGuidanceStepIndex: Int?
    private var lastGuidanceDistanceBucket: Int?
    private var hasLoggedArrival = false

    var route: RouteOption
    var stepIndex = 0
    var distanceToTurnMeters: Double?
    var isRerouting = false
    var gpsStatus = "WAITING FOR GPS"
    var isEnded = false

    var gpsLogURL: URL {
        logWriter.gpsURL
    }

    var guidanceLogURL: URL {
        logWriter.guidanceURL
    }

    init(route: RouteOption, destination: RidePlace, avoidHighways: Bool, avoidTolls: Bool) {
        self.route = route
        self.destination = destination
        self.avoidHighways = avoidHighways
        self.avoidTolls = avoidTolls
        logWriter = NavigationLogWriter()
        logWriter.appendGuidance(event: "session_started", details: "route_id=\(route.id);steps=\(route.steps.count)")
    }

    var currentStep: RouteStep? {
        route.steps.indices.contains(stepIndex) ? route.steps[stepIndex] : nil
    }

    var distanceToTurnText: String {
        guard let distanceToTurnMeters else { return "—" }
        if distanceToTurnMeters < 161 {
            return "\(max(0, Int(distanceToTurnMeters * 3.28084))) FT"
        }
        return String(format: "%.1f MI", distanceToTurnMeters / 1609.344)
    }

    var remainingDistanceText: String {
        let completed = route.steps.prefix(stepIndex).reduce(0) { $0 + $1.distanceMeters }
        let remaining = max(0, route.distanceMeters - completed)
        return String(format: "%.1f MI", Double(remaining) / 1609.344)
    }

    var remainingTimeText: String {
        let progress = Double(route.steps.prefix(stepIndex).reduce(0) { $0 + $1.distanceMeters }) / Double(max(route.distanceMeters, 1))
        let seconds = Int(Double(route.durationSeconds) * (1 - progress))
        return seconds >= 3600 ? "\(seconds / 3600)H \((seconds % 3600) / 60)M" : "\(max(1, seconds / 60)) MIN"
    }

    func start() async {
        guard updatesTask == nil else { return }
        manager.requestWhenInUseAuthorization()
        updatesTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard !Task.isCancelled, let location = update.location else { continue }
                    await process(location)
                }
            } catch {
                gpsStatus = "GPS ERROR"
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    func endSession() {
        guard !isEnded else { return }
        logWriter.appendGuidance(event: "session_ended", details: "step_index=\(stepIndex)")
        stop()
        isEnded = true
        gpsStatus = "LOGS READY"
    }

    private func process(_ location: CLLocation) async {
        if shouldLogGPS(location) {
            logWriter.appendGPS(location)
        }
        gpsStatus = location.horizontalAccuracy <= 30 ? "GPS" : "LOW GPS"
        guard let step = currentStep else {
            if !hasLoggedArrival {
                logWriter.appendGuidance(location: location, event: "arrived", details: "no_current_step")
                hasLoggedArrival = true
            }
            return
        }
        distanceToTurnMeters = location.distance(from: CLLocation(latitude: step.endLatitude, longitude: step.endLongitude))
        let distanceFromRoute = nearestDistance(from: location.coordinate, encodedPolyline: route.encodedPolyline)
        if shouldLogGuidance(distance: distanceToTurnMeters ?? 0) {
            logWriter.appendGuidance(
                location: location,
                event: "guidance_update",
                details: guidanceDetails(step: step, offRouteDistance: distanceFromRoute)
            )
        }

        if let distanceToTurnMeters, distanceToTurnMeters < 25 {
            logWriter.appendGuidance(
                location: location,
                event: "step_advanced",
                details: "from_step=\(stepIndex);distance_to_end_m=\(distanceToTurnMeters)"
            )
            stepIndex += 1
            offRouteReadings = 0
            return
        }

        if distanceFromRoute > 65, location.horizontalAccuracy < 40 {
            offRouteReadings += 1
        } else {
            offRouteReadings = 0
        }
        if offRouteReadings >= 3, !isRerouting {
            logWriter.appendGuidance(
                location: location,
                event: "reroute_triggered",
                details: "off_route_m=\(distanceFromRoute);readings=\(offRouteReadings)"
            )
            await reroute(from: location.coordinate)
        }
    }

    private func reroute(from coordinate: CLLocationCoordinate2D) async {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty else {
            logWriter.appendGuidance(event: "reroute_failed", details: "missing_api_key")
            return
        }
        isRerouting = true
        defer { isRerouting = false }
        do {
            let routes = try await RoutesAPIClient.computeRoutes(
                origin: coordinate,
                destination: destination.coordinate,
                avoidHighways: avoidHighways,
                avoidTolls: avoidTolls,
                apiKey: apiKey
            )
            if let freshRoute = routes.first {
                logWriter.appendGuidance(
                    event: "reroute_succeeded",
                    details: "old_route_id=\(route.id);new_route_id=\(freshRoute.id);new_steps=\(freshRoute.steps.count)"
                )
                route = freshRoute
                stepIndex = 0
                offRouteReadings = 0
                lastGuidanceStepIndex = nil
                lastGuidanceDistanceBucket = nil
            }
        } catch {
            logWriter.appendGuidance(event: "reroute_failed", details: "error=\(error.localizedDescription)")
            gpsStatus = "REROUTE FAILED"
            offRouteReadings = 0
        }
    }

    private func guidanceDetails(step: RouteStep, offRouteDistance: Double) -> String {
        let distance = distanceToTurnMeters ?? -1
        return "step_index=\(stepIndex);maneuver=\(step.maneuver);instruction=\(step.instruction);distance_to_turn_m=\(distance);off_route_m=\(offRouteDistance);off_route_readings=\(offRouteReadings);display=\(distanceToTurnText)"
    }

    private func shouldLogGPS(_ location: CLLocation) -> Bool {
        let elapsed = lastGPSLogDate.map { Date().timeIntervalSince($0) } ?? .infinity
        let movement = lastGPSLogLocation.map { location.distance(from: $0) } ?? .infinity
        guard elapsed >= 2 || movement >= 10 else { return false }
        lastGPSLogDate = Date()
        lastGPSLogLocation = location
        return true
    }

    private func shouldLogGuidance(distance: Double) -> Bool {
        let bucketSize = distance < 100 ? 10.0 : distance < 500 ? 25.0 : 100.0
        let bucket = Int(distance / bucketSize)
        let elapsed = lastGuidanceLogDate.map { Date().timeIntervalSince($0) } ?? .infinity
        let stateChanged = lastGuidanceStepIndex != stepIndex || lastGuidanceDistanceBucket != bucket
        guard stateChanged || elapsed >= 10 else { return false }
        lastGuidanceLogDate = Date()
        lastGuidanceStepIndex = stepIndex
        lastGuidanceDistanceBucket = bucket
        return true
    }

    private func nearestDistance(from coordinate: CLLocationCoordinate2D, encodedPolyline: String) -> Double {
        guard let path = GMSPath(fromEncodedPath: encodedPolyline), path.count() > 0 else { return 0 }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return (0 ..< path.count()).reduce(Double.greatestFiniteMagnitude) { nearest, index in
            let point = path.coordinate(at: index)
            let distance = location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            return min(nearest, distance)
        }
    }
}

private final class NavigationLogWriter {
    let gpsURL: URL
    let guidanceURL: URL

    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let sessionName = "walk-\(formatter.string(from: Date()))"
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Navigation Logs", isDirectory: true)
            .appendingPathComponent(sessionName, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        gpsURL = root.appendingPathComponent("gps-live.csv")
        guidanceURL = root.appendingPathComponent("app-guidance.csv")
        try? "recorded_at,location_timestamp,latitude,longitude,horizontal_accuracy_m,vertical_accuracy_m,speed_mps,course_degrees\n"
            .write(to: gpsURL, atomically: true, encoding: .utf8)
        try? "recorded_at,event,latitude,longitude,details\n"
            .write(to: guidanceURL, atomically: true, encoding: .utf8)
    }

    func appendGPS(_ location: CLLocation) {
        append(
            "\(timestamp()),\(timestamp(location.timestamp)),\(location.coordinate.latitude),\(location.coordinate.longitude),\(location.horizontalAccuracy),\(location.verticalAccuracy),\(location.speed),\(location.course)\n",
            to: gpsURL
        )
    }

    func appendGuidance(location: CLLocation? = nil, event: String, details: String) {
        let latitude = location.map { String($0.coordinate.latitude) } ?? ""
        let longitude = location.map { String($0.coordinate.longitude) } ?? ""
        append("\(timestamp()),\(csv(event)),\(latitude),\(longitude),\(csv(details))\n", to: guidanceURL)
    }

    private func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8), let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Navigation must continue even when diagnostic storage is unavailable.
        }
    }

    private func timestamp(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
