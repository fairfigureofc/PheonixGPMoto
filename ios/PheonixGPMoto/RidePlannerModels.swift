import CoreLocation
import Foundation

struct RidePlace: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, address: String, coordinate: CLLocationCoordinate2D) {
        id = "\(coordinate.latitude),\(coordinate.longitude)"
        self.name = name
        self.address = address
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

struct RouteOption: Identifiable, Equatable, Sendable {
    let id: String
    let distanceMeters: Int
    let durationSeconds: Int
    let encodedPolyline: String
    let isDefault: Bool
    let steps: [RouteStep]

    var distanceText: String {
        Measurement(value: Double(distanceMeters), unit: UnitLength.meters)
            .converted(to: .miles)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = durationSeconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(durationSeconds)) ?? "—"
    }
}

struct RouteStep: Identifiable, Equatable, Sendable {
    let id: String
    let instruction: String
    let maneuver: String
    let distanceMeters: Int
    let encodedPolyline: String
    let endLatitude: Double
    let endLongitude: Double

    var endCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude)
    }

    var distanceText: String {
        if distanceMeters < 161 {
            return Measurement(value: Double(distanceMeters), unit: UnitLength.meters)
                .converted(to: .feet)
                .formatted(.measurement(width: .abbreviated, usage: .road))
        }
        return Measurement(value: Double(distanceMeters), unit: UnitLength.meters)
            .converted(to: .miles)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var symbolName: String {
        let value = maneuver.uppercased()
        if value.contains("UTURN") {
            return "arrow.uturn.backward"
        }
        if value.contains("LEFT") {
            return "arrow.turn.up.left"
        }
        if value.contains("RIGHT") {
            return "arrow.turn.up.right"
        }
        if value.contains("RAMP") || value.contains("MERGE") {
            return "arrow.triangle.merge"
        }
        if value.contains("ROUNDABOUT") {
            return "arrow.clockwise"
        }
        return "arrow.up"
    }
}

struct SavedRide: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let origin: RidePlace?
    let usesCurrentLocation: Bool
    let destination: RidePlace
    let avoidHighways: Bool
    let avoidTolls: Bool
    let savedAt: Date
    var description: String?
}

@MainActor
@Observable
final class RiderLocationModel {
    private let manager = CLLocationManager()
    private var updatesTask: Task<Void, Never>?
    var coordinate: CLLocationCoordinate2D?

    func start() async {
        guard updatesTask == nil else { return }
        manager.requestWhenInUseAuthorization()
        updatesTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard !Task.isCancelled, let location = update.location else { continue }
                    coordinate = location.coordinate
                }
            } catch {
                // Planning still works with a manually selected starting point.
            }
        }
    }
}

@MainActor
@Observable
final class RidePlannerModel {
    var usesCurrentLocation = true
    var origin: RidePlace?
    var destination: RidePlace?
    var avoidHighways = false
    var avoidTolls = false
    var routes: [RouteOption] = []
    var selectedRouteID: String?
    var isLoading = false
    var errorMessage: String?
    var savedRides: [SavedRide] = SavedRideStore.load()
    var startedRoute: RouteOption?

    var selectedRoute: RouteOption? {
        routes.first { $0.id == selectedRouteID }
    }

    func calculateRoutes(currentLocation: CLLocationCoordinate2D?) async {
        guard let destination else {
            errorMessage = "Choose a destination first."
            return
        }
        guard let originCoordinate = usesCurrentLocation ? currentLocation : origin?.coordinate else {
            errorMessage = usesCurrentLocation ? "Current location is not available yet." : "Choose a starting point."
            return
        }
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty else {
            errorMessage = "The Google Maps API key is missing."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            routes = try await RoutesAPIClient.computeRoutes(
                origin: originCoordinate,
                destination: destination.coordinate,
                avoidHighways: avoidHighways,
                avoidTolls: avoidTolls,
                apiKey: apiKey
            )
            selectedRouteID = routes.first?.id
            if routes.isEmpty {
                errorMessage = "Google did not return a route for this trip."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveRide(description: String) {
        guard let destination else { return }
        let savedRide = SavedRide(
            id: UUID(),
            name: destination.name,
            origin: origin,
            usesCurrentLocation: usesCurrentLocation,
            destination: destination,
            avoidHighways: avoidHighways,
            avoidTolls: avoidTolls,
            savedAt: Date(),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        savedRides.insert(savedRide, at: 0)
        SavedRideStore.save(savedRides)
    }

    func load(_ ride: SavedRide) {
        usesCurrentLocation = ride.usesCurrentLocation
        origin = ride.origin
        destination = ride.destination
        avoidHighways = ride.avoidHighways
        avoidTolls = ride.avoidTolls
        routes = []
        selectedRouteID = nil
    }

    func deleteSavedRides(at offsets: IndexSet) {
        savedRides.remove(atOffsets: offsets)
        SavedRideStore.save(savedRides)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum SavedRideStore {
    private static let key = "saved-rides-v1"

    static func load() -> [SavedRide] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedRide].self, from: data)) ?? []
    }

    static func save(_ rides: [SavedRide]) {
        guard let data = try? JSONEncoder().encode(rides) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
