import CoreLocation
import Foundation

enum RoutesAPIClient {
    static func computeRoutes(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        avoidHighways: Bool,
        avoidTolls: Bool,
        apiKey: String
    ) async throws -> [RouteOption] {
        let endpoint = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "routes.routeLabels,routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.legs.steps.distanceMeters,routes.legs.steps.navigationInstruction,routes.legs.steps.polyline.encodedPolyline,routes.legs.steps.endLocation",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let body = ComputeRoutesRequest(
            origin: .init(location: .init(latLng: .init(latitude: origin.latitude, longitude: origin.longitude))),
            destination: .init(location: .init(latLng: .init(latitude: destination.latitude, longitude: destination.longitude))),
            travelMode: "DRIVE",
            routingPreference: "TRAFFIC_AWARE",
            computeAlternativeRoutes: true,
            routeModifiers: .init(avoidTolls: avoidTolls, avoidHighways: avoidHighways),
            units: "IMPERIAL"
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoutesError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            let message = (try? JSONDecoder().decode(GoogleAPIError.self, from: data))?.error.message
            throw RoutesError.server(message ?? "Routes API returned status \(httpResponse.statusCode).")
        }

        let decoded = try JSONDecoder().decode(ComputeRoutesResponse.self, from: data)
        return decoded.routes.enumerated().map { index, route in
            RouteOption(
                id: "route-\(index)-\(route.distanceMeters)-\(route.duration)",
                distanceMeters: route.distanceMeters,
                durationSeconds: parseDuration(route.duration),
                encodedPolyline: route.polyline.encodedPolyline,
                isDefault: route.routeLabels.contains("DEFAULT_ROUTE"),
                steps: route.legs.flatMap(\.steps).enumerated().map { stepIndex, step in
                    RouteStep(
                        id: "route-\(index)-step-\(stepIndex)",
                        instruction: step.navigationInstruction.instructions,
                        maneuver: step.navigationInstruction.maneuver,
                        distanceMeters: step.distanceMeters,
                        encodedPolyline: step.polyline.encodedPolyline,
                        endLatitude: step.endLocation.latLng.latitude,
                        endLongitude: step.endLocation.latLng.longitude
                    )
                }
            )
        }
    }

    private static func parseDuration(_ value: String) -> Int {
        Int(Double(value.dropLast()) ?? 0)
    }
}

private struct ComputeRoutesRequest: Encodable, Sendable {
    struct Waypoint: Encodable, Sendable {
        struct Location: Encodable, Sendable {
            struct LatLng: Encodable, Sendable {
                let latitude: Double
                let longitude: Double
            }

            let latLng: LatLng
        }

        let location: Location
    }

    struct RouteModifiers: Encodable, Sendable {
        let avoidTolls: Bool
        let avoidHighways: Bool
    }

    let origin: Waypoint
    let destination: Waypoint
    let travelMode: String
    let routingPreference: String
    let computeAlternativeRoutes: Bool
    let routeModifiers: RouteModifiers
    let units: String
}

private struct ComputeRoutesResponse: Decodable, Sendable {
    struct Route: Decodable, Sendable {
        struct Polyline: Decodable, Sendable {
            let encodedPolyline: String
        }

        struct Leg: Decodable, Sendable {
            struct Step: Decodable, Sendable {
                struct NavigationInstruction: Decodable, Sendable {
                    let maneuver: String
                    let instructions: String
                }

                struct Polyline: Decodable, Sendable {
                    let encodedPolyline: String
                }

                struct Location: Decodable, Sendable {
                    struct LatLng: Decodable, Sendable {
                        let latitude: Double
                        let longitude: Double
                    }

                    let latLng: LatLng
                }

                let distanceMeters: Int
                let navigationInstruction: NavigationInstruction
                let polyline: Polyline
                let endLocation: Location
            }

            let steps: [Step]
        }

        let routeLabels: [String]
        let distanceMeters: Int
        let duration: String
        let polyline: Polyline
        let legs: [Leg]
    }

    let routes: [Route]
}

private struct GoogleAPIError: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let message: String
    }

    let error: Detail
}

private enum RoutesError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Google Routes returned an invalid response."
        case let .server(message): message
        }
    }
}
