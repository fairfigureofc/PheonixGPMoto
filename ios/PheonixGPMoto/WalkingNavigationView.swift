import AVFAudio
import CoreLocation
@preconcurrency import GoogleMaps
import SwiftUI

struct WalkingNavigationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: WalkingNavigationModel
    @StateObject private var bluetooth = ESP32BluetoothClient()

    init(
        initialRoute: RouteOption,
        destination: RidePlace,
        avoidHighways: Bool,
        avoidTolls: Bool,
        travelMode: RouteTravelMode
    ) {
        _model = State(initialValue: WalkingNavigationModel(
            route: initialRoute,
            destination: destination,
            avoidHighways: avoidHighways,
            avoidTolls: avoidTolls,
            travelMode: travelMode
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                statusBar
                Spacer(minLength: 18)
                if !model.hasArrived {
                    Image(systemName: model.guidanceSymbolName)
                        .font(.system(size: 88, weight: .bold))
                    Text(model.distanceToTurnText)
                        .font(.system(size: 54, weight: .medium, design: .monospaced))
                        .padding(.top, 20)
                    Text(model.guidanceInstruction.uppercased())
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
        .task {
            model.attachDisplay(bluetooth)
            bluetooth.startAutoConnect()
            await model.start()
        }
        .onDisappear {
            bluetooth.stop()
            model.stop()
        }
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
            Button {
                model.toggleVoiceGuidance()
            } label: {
                Image(systemName: model.isVoiceGuidanceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .accessibilityLabel(model.isVoiceGuidanceEnabled ? "Turn voice guidance off" : "Turn voice guidance on")
            Image(systemName: bluetooth.isConnected ? "display.and.arrow.down" : "display")
                .foregroundStyle(bluetooth.isConnected ? .green : .secondary)
                .accessibilityLabel(bluetooth.state)
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
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let destination: RidePlace
    private let avoidHighways: Bool
    private let avoidTolls: Bool
    private let travelMode: RouteTravelMode
    private var offRouteReadings = 0
    private var wrongWayReadings = 0
    private var lastRerouteDate: Date?
    private let logWriter: NavigationLogWriter
    private var lastGPSLogDate: Date?
    private var lastGPSLogLocation: CLLocation?
    private var lastGuidanceLogDate: Date?
    private var lastGuidanceStepIndex: Int?
    private var lastGuidanceDistanceBucket: Int?
    private var hasLoggedArrival = false
    private var hasInitialMatch = false
    private var maximumStepProgressMeters = 0.0
    private var voiceStepIndex: Int?
    private var announcedDistanceThresholds: Set<Int> = []
    private weak var display: ESP32BluetoothClient?
    private var displaySequence: UInt16 = 1
    private var lastDisplaySendDate: Date?
    private var lastDisplaySignature: String?

    var route: RouteOption
    var stepIndex = 0
    var distanceToTurnMeters: Double?
    var isRerouting = false
    var gpsStatus = "WAITING FOR GPS"
    var isEnded = false
    var hasArrived = false
    var remainingRouteMeters: Double
    var isVoiceGuidanceEnabled = true

    var gpsLogURL: URL {
        logWriter.gpsURL
    }

    var guidanceLogURL: URL {
        logWriter.guidanceURL
    }

    init(
        route: RouteOption,
        destination: RidePlace,
        avoidHighways: Bool,
        avoidTolls: Bool,
        travelMode: RouteTravelMode
    ) {
        self.route = route
        self.destination = destination
        self.avoidHighways = avoidHighways
        self.avoidTolls = avoidTolls
        self.travelMode = travelMode
        remainingRouteMeters = Double(route.distanceMeters)
        logWriter = NavigationLogWriter()
        logWriter.appendGuidance(
            event: "session_started",
            details: "route_id=\(route.id);steps=\(route.steps.count);travel_mode=\(travelMode.rawValue)"
        )
    }

    var currentStep: RouteStep? {
        route.steps.indices.contains(stepIndex) ? route.steps[stepIndex] : nil
    }

    private var upcomingStep: RouteStep? {
        let upcomingIndex = stepIndex + 1
        return route.steps.indices.contains(upcomingIndex) ? route.steps[upcomingIndex] : nil
    }

    var guidanceInstruction: String {
        upcomingStep?.instruction ?? "Continue to \(destination.name)"
    }

    var guidanceSymbolName: String {
        upcomingStep?.symbolName ?? "flag.checkered"
    }

    var distanceToTurnText: String {
        guard let distanceToTurnMeters else { return "—" }
        if distanceToTurnMeters < 161 {
            return "\(max(0, Int(distanceToTurnMeters * 3.28084))) FT"
        }
        return String(format: "%.1f MI", distanceToTurnMeters / 1609.344)
    }

    var remainingDistanceText: String {
        String(format: "%.1f MI", max(0, remainingRouteMeters) / 1609.344)
    }

    var remainingTimeText: String {
        let seconds = estimatedRemainingSeconds
        return seconds >= 3600 ? "\(seconds / 3600)H \((seconds % 3600) / 60)M" : "\(max(1, seconds / 60)) MIN"
    }

    private var estimatedRemainingSeconds: Int {
        let fractionRemaining = min(1, max(0, remainingRouteMeters / Double(max(route.distanceMeters, 1))))
        return Int(Double(route.durationSeconds) * fractionRemaining)
    }

    func attachDisplay(_ display: ESP32BluetoothClient) {
        self.display = display
    }

    func start() async {
        guard updatesTask == nil else { return }
        configureAudioSession()
        manager.requestWhenInUseAuthorization()
        backgroundActivitySession = CLBackgroundActivitySession()
        let configuration: CLLocationUpdate.LiveConfiguration = travelMode == .walk ? .fitness : .automotiveNavigation
        updatesTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
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
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func toggleVoiceGuidance() {
        isVoiceGuidanceEnabled.toggle()
        if isVoiceGuidanceEnabled {
            speak("Voice guidance on.")
            voiceStepIndex = nil
            announcedDistanceThresholds.removeAll()
        } else {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
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
        guard !route.steps.isEmpty else { return }
        if !hasInitialMatch {
            matchInitialStep(to: location)
        }
        guard let step = currentStep,
              var stepProjection = RouteGeometry.project(location.coordinate, onto: step.encodedPolyline)
        else { return }

        if shouldAdvanceStep(from: location, currentProjection: stepProjection) {
            let previousStep = stepIndex
            stepIndex += 1
            maximumStepProgressMeters = 0
            lastGuidanceStepIndex = nil
            lastGuidanceDistanceBucket = nil
            logWriter.appendGuidance(
                location: location,
                event: "step_advanced",
                details: "from_step=\(previousStep);to_step=\(stepIndex);reason=entered_next_geometry"
            )
            guard let advancedStep = currentStep,
                  let advancedProjection = RouteGeometry.project(location.coordinate, onto: advancedStep.encodedPolyline)
            else { return }
            stepProjection = advancedProjection
        }

        let matchingTolerance = max(25, location.horizontalAccuracy * 2.5)
        if stepProjection.distanceToPathMeters <= matchingTolerance {
            maximumStepProgressMeters = max(maximumStepProgressMeters, stepProjection.distanceAlongMeters)
        }
        distanceToTurnMeters = max(0, stepProjection.totalLengthMeters - maximumStepProgressMeters)
        remainingRouteMeters = (distanceToTurnMeters ?? 0) + Double(
            route.steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distanceMeters }
        )
        sendDisplayUpdate()
        announceGuidanceIfNeeded()

        if stepIndex == route.steps.count - 1,
           let distanceToTurnMeters,
           distanceToTurnMeters < 12,
           stepProjection.distanceToPathMeters < matchingTolerance
        {
            markArrived(at: location)
            return
        }

        guard let routeProjection = RouteGeometry.project(location.coordinate, onto: route.encodedPolyline) else { return }
        updateDeviationCounters(location: location, stepProjection: stepProjection, routeProjection: routeProjection)
        if shouldLogGuidance(distance: distanceToTurnMeters ?? 0) {
            logWriter.appendGuidance(
                location: location,
                event: "guidance_update",
                details: guidanceDetails(stepProjection: stepProjection, offRouteDistance: routeProjection.distanceToPathMeters)
            )
        }

        let offRouteLimit = travelMode == .walk ? 2 : 5
        let wrongWayLimit = travelMode == .walk ? 5 : 8
        let rerouteCooldown = travelMode == .walk ? 12.0 : 20.0
        let rerouteCooldownElapsed = lastRerouteDate.map { Date().timeIntervalSince($0) >= rerouteCooldown } ?? true
        if offRouteReadings >= offRouteLimit || wrongWayReadings >= wrongWayLimit,
           !isRerouting,
           rerouteCooldownElapsed
        {
            let reason = offRouteReadings >= offRouteLimit ? "off_route" : "wrong_way"
            logWriter.appendGuidance(
                location: location,
                event: "reroute_triggered",
                details: "reason=\(reason);off_route_m=\(routeProjection.distanceToPathMeters);off_route_readings=\(offRouteReadings);wrong_way_readings=\(wrongWayReadings)"
            )
            lastRerouteDate = Date()
            await reroute(from: location)
        }
    }

    private func reroute(from location: CLLocation) async {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty else {
            logWriter.appendGuidance(event: "reroute_failed", details: "missing_api_key")
            return
        }
        isRerouting = true
        defer { isRerouting = false }
        do {
            let heading = reliableCourse(from: location).map { Int($0.rounded()) % 360 }
            let routes = try await RoutesAPIClient.computeRoutes(
                origin: location.coordinate,
                destination: destination.coordinate,
                avoidHighways: avoidHighways,
                avoidTolls: avoidTolls,
                travelMode: travelMode,
                originHeading: heading,
                apiKey: apiKey
            )
            if let selection = selectReroute(from: routes, at: location) {
                let freshRoute = selection.route
                let headingText = heading.map(String.init) ?? "none"
                let scoreText = String(format: "%.1f", selection.score)
                let headingDifferenceText = selection.headingDifference
                    .map { String(format: "%.1f", $0) } ?? "none"
                let details = "old_route_id=\(route.id);new_route_id=\(freshRoute.id);" +
                    "new_steps=\(freshRoute.steps.count);origin_heading=\(headingText);" +
                    "selection_score=\(scoreText);initial_heading_difference=\(headingDifferenceText)"
                logWriter.appendGuidance(
                    location: location,
                    event: "reroute_succeeded",
                    details: details
                )
                route = freshRoute
                stepIndex = 0
                offRouteReadings = 0
                wrongWayReadings = 0
                hasInitialMatch = false
                maximumStepProgressMeters = 0
                hasArrived = false
                hasLoggedArrival = false
                remainingRouteMeters = Double(freshRoute.distanceMeters)
                lastGuidanceStepIndex = nil
                lastGuidanceDistanceBucket = nil
                voiceStepIndex = nil
                announcedDistanceThresholds.removeAll()
                speak("Route updated.")
            } else {
                logWriter.appendGuidance(location: location, event: "reroute_failed", details: "no_usable_route")
            }
        } catch {
            logWriter.appendGuidance(event: "reroute_failed", details: "error=\(error.localizedDescription)")
            gpsStatus = "REROUTE FAILED"
            offRouteReadings = 0
        }
    }

    private func reliableCourse(from location: CLLocation) -> CLLocationDirection? {
        guard location.speed >= 0.8, location.course >= 0, location.course < 360 else { return nil }
        return location.course
    }

    private func announceGuidanceIfNeeded() {
        guard isVoiceGuidanceEnabled, let distance = distanceToTurnMeters else { return }
        let stepChanged = voiceStepIndex != stepIndex
        if stepChanged {
            voiceStepIndex = stepIndex
            announcedDistanceThresholds.removeAll()
        }

        let thresholds = [160, 60, 20]
        let crossedThreshold = thresholds.first {
            distance <= Double($0) && !announcedDistanceThresholds.contains($0)
        }
        guard stepChanged || crossedThreshold != nil else { return }
        if stepChanged {
            announcedDistanceThresholds.formUnion(thresholds.filter { distance <= Double($0) })
        } else if let crossedThreshold {
            announcedDistanceThresholds.insert(crossedThreshold)
        }

        let cleanInstruction = guidanceInstruction
            .replacingOccurrences(of: "\n", with: ". ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = "\(voiceDistancePhrase(distance)). \(cleanInstruction)"
        speak(prompt)
        logWriter.appendGuidance(event: "voice_prompt", details: "step=\(stepIndex);text=\(prompt)")
    }

    private func voiceDistancePhrase(_ meters: Double) -> String {
        if meters < 20 {
            return "Now"
        }
        let feet = meters * 3.28084
        if feet < 1000 {
            let roundedFeet = max(25, Int((feet / 25).rounded()) * 25)
            return "In \(roundedFeet) feet"
        }
        let miles = meters / 1609.344
        return String(format: "In %.1f miles", miles)
    }

    private func speak(_ text: String) {
        guard isVoiceGuidanceEnabled else { return }
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.usesApplicationAudioSession = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        speechSynthesizer.speak(utterance)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true)
        } catch {
            logWriter.appendGuidance(event: "audio_session_failed", details: "error=\(error.localizedDescription)")
        }
    }

    private func sendDisplayUpdate() {
        guard let display, display.isConnected else { return }
        let maneuver = displayManeuver
        let roadName = hasArrived ? "ARRIVED" : guidanceInstruction
        let distance = UInt32(clamping: Int(max(0, distanceToTurnMeters ?? 0).rounded()))
        let remaining = UInt32(clamping: Int(max(0, remainingRouteMeters).rounded()))
        let seconds = UInt32(clamping: estimatedRemainingSeconds)
        let signature = "\(maneuver.rawValue)|\(roadName)|\(distance)|\(remaining)|\(seconds)"
        let elapsed = lastDisplaySendDate.map { Date().timeIntervalSince($0) } ?? .infinity
        guard signature != lastDisplaySignature, elapsed >= 0.75 else { return }

        display.send(NavigationPacket(
            sequence: displaySequence,
            maneuver: maneuver,
            lightMode: false,
            distanceToTurnMeters: distance,
            remainingMeters: remaining,
            remainingSeconds: seconds,
            roadName: roadName
        ))
        displaySequence &+= 1
        lastDisplaySignature = signature
        lastDisplaySendDate = Date()
    }

    private var displayManeuver: NavigationPacket.Maneuver {
        let maneuver = upcomingStep?.maneuver.uppercased() ?? ""
        if maneuver.contains("LEFT") {
            return .left
        }
        if maneuver.contains("RIGHT") {
            return .right
        }
        return .straight
    }

    private func selectReroute(
        from routes: [RouteOption],
        at location: CLLocation
    ) -> (route: RouteOption, score: Double, headingDifference: Double?)? {
        let course = reliableCourse(from: location)
        let candidates = routes.compactMap { route -> (RouteOption, Double, Double?)? in
            let projections = route.steps.prefix(3).enumerated().compactMap { index, step -> (Int, RouteProjection)? in
                guard let projection = RouteGeometry.project(location.coordinate, onto: step.encodedPolyline) else {
                    return nil
                }
                return (index, projection)
            }
            guard let bestProjection = projections.min(by: {
                $0.1.distanceToPathMeters + Double($0.0) * 30 <
                    $1.1.distanceToPathMeters + Double($1.0) * 30
            }) else { return nil }

            let headingDifference = course.map {
                RouteGeometry.headingDifference($0, bestProjection.1.segmentBearingDegrees)
            }
            var score = bestProjection.1.distanceToPathMeters + Double(bestProjection.0) * 30
            if let headingDifference {
                score += headingDifference * 1.5
                if headingDifference > 120 {
                    score += 500
                }
            }
            score += Double(route.durationSeconds) / 300
            return (route, score, headingDifference)
        }
        return candidates.min(by: { $0.1 < $1.1 }).map {
            (route: $0.0, score: $0.1, headingDifference: $0.2)
        }
    }

    private func guidanceDetails(stepProjection: RouteProjection, offRouteDistance: Double) -> String {
        let distance = distanceToTurnMeters ?? -1
        let maneuver = upcomingStep?.maneuver ?? "ARRIVE"
        return "active_step=\(stepIndex);upcoming_maneuver=\(maneuver);instruction=\(guidanceInstruction);distance_to_turn_m=\(distance);projected_step_progress_m=\(stepProjection.distanceAlongMeters);step_length_m=\(stepProjection.totalLengthMeters);off_route_m=\(offRouteDistance);off_route_readings=\(offRouteReadings);wrong_way_readings=\(wrongWayReadings);display=\(distanceToTurnText)"
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

    private func matchInitialStep(to location: CLLocation) {
        let candidates = route.steps.enumerated().compactMap { index, step -> (Int, RouteProjection, Double)? in
            guard let projection = RouteGeometry.project(location.coordinate, onto: step.encodedPolyline) else { return nil }
            var score = projection.distanceToPathMeters
            if location.speed >= 0.8, location.course >= 0 {
                score += RouteGeometry.headingDifference(location.course, projection.segmentBearingDegrees) / 180 * 35
            }
            score += Double(index) * 0.05
            return (index, projection, score)
        }
        guard let match = candidates.min(by: { $0.2 < $1.2 }) else { return }
        stepIndex = match.0
        maximumStepProgressMeters = match.1.distanceAlongMeters
        hasInitialMatch = true
        logWriter.appendGuidance(
            location: location,
            event: "initial_map_match",
            details: "step=\(stepIndex);off_step_m=\(match.1.distanceToPathMeters);progress_m=\(match.1.distanceAlongMeters);bearing=\(match.1.segmentBearingDegrees)"
        )
    }

    private func shouldAdvanceStep(from location: CLLocation, currentProjection: RouteProjection) -> Bool {
        let nextIndex = stepIndex + 1
        guard route.steps.indices.contains(nextIndex),
              let nextProjection = RouteGeometry.project(location.coordinate, onto: route.steps[nextIndex].encodedPolyline)
        else { return false }
        let tolerance = max(18, location.horizontalAccuracy * 2)
        return nextProjection.distanceToPathMeters <= tolerance &&
            nextProjection.distanceAlongMeters >= 8 &&
            currentProjection.remainingMeters <= 30
    }

    private func updateDeviationCounters(
        location: CLLocation,
        stepProjection: RouteProjection,
        routeProjection: RouteProjection
    ) {
        let minimumOffRouteDistance = travelMode == .walk ? 20.0 : 35.0
        let accuracyMultiplier = travelMode == .walk ? 2.0 : 3.0
        let offRouteThreshold = max(minimumOffRouteDistance, location.horizontalAccuracy * accuracyMultiplier)
        if routeProjection.distanceToPathMeters > offRouteThreshold, location.horizontalAccuracy < 30 {
            offRouteReadings += 1
        } else {
            offRouteReadings = 0
        }

        if location.speed >= 0.8, location.course >= 0, stepProjection.distanceToPathMeters < 25 {
            let headingDifference = RouteGeometry.headingDifference(location.course, stepProjection.segmentBearingDegrees)
            wrongWayReadings = headingDifference > 120 ? wrongWayReadings + 1 : 0
        } else {
            wrongWayReadings = 0
        }
    }

    private func markArrived(at location: CLLocation) {
        hasArrived = true
        distanceToTurnMeters = 0
        remainingRouteMeters = 0
        if !hasLoggedArrival {
            logWriter.appendGuidance(location: location, event: "arrived", details: "matched_final_step")
            speak("You have arrived.")
            hasLoggedArrival = true
        }
    }
}

private struct RouteProjection {
    let distanceToPathMeters: Double
    let distanceAlongMeters: Double
    let totalLengthMeters: Double
    let segmentBearingDegrees: Double

    var remainingMeters: Double {
        max(0, totalLengthMeters - distanceAlongMeters)
    }
}

private enum RouteGeometry {
    private static let earthRadiusMeters = 6_371_000.0

    static func project(_ coordinate: CLLocationCoordinate2D, onto encodedPolyline: String) -> RouteProjection? {
        guard let path = GMSPath(fromEncodedPath: encodedPolyline), path.count() >= 2 else { return nil }
        var cumulativeDistance = 0.0
        var bestDistance = Double.greatestFiniteMagnitude
        var bestDistanceAlong = 0.0
        var bestBearing = 0.0

        for index in 0 ..< path.count() - 1 {
            let start = path.coordinate(at: index)
            let end = path.coordinate(at: index + 1)
            let segmentLength = distance(start, end)
            let localStart = localPoint(start, relativeTo: coordinate)
            let localEnd = localPoint(end, relativeTo: coordinate)
            let dx = localEnd.x - localStart.x
            let dy = localEnd.y - localStart.y
            let denominator = dx * dx + dy * dy
            let rawFraction = denominator > 0 ? -(localStart.x * dx + localStart.y * dy) / denominator : 0
            let fraction = min(1, max(0, rawFraction))
            let projectedX = localStart.x + fraction * dx
            let projectedY = localStart.y + fraction * dy
            let distanceToSegment = hypot(projectedX, projectedY)

            if distanceToSegment < bestDistance {
                bestDistance = distanceToSegment
                bestDistanceAlong = cumulativeDistance + segmentLength * fraction
                bestBearing = bearing(from: start, to: end)
            }
            cumulativeDistance += segmentLength
        }

        return RouteProjection(
            distanceToPathMeters: bestDistance,
            distanceAlongMeters: bestDistanceAlong,
            totalLengthMeters: cumulativeDistance,
            segmentBearingDegrees: bestBearing
        )
    }

    static func headingDifference(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func localPoint(
        _ coordinate: CLLocationCoordinate2D,
        relativeTo origin: CLLocationCoordinate2D
    ) -> (x: Double, y: Double) {
        let latitudeRadians = origin.latitude * .pi / 180
        let x = (coordinate.longitude - origin.longitude) * .pi / 180 * cos(latitudeRadians) * earthRadiusMeters
        let y = (coordinate.latitude - origin.latitude) * .pi / 180 * earthRadiusMeters
        return (x, y)
    }

    private static func distance(_ first: CLLocationCoordinate2D, _ second: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
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
