import Foundation

struct PlaceSuggestion: Decodable, Identifiable, Sendable {
    struct Prediction: Decodable, Sendable {
        struct TextValue: Decodable, Sendable {
            let text: String
        }

        struct StructuredFormat: Decodable, Sendable {
            let mainText: TextValue
            let secondaryText: TextValue?
        }

        let placeId: String
        let text: TextValue
        let structuredFormat: StructuredFormat
    }

    let placePrediction: Prediction

    var id: String {
        placePrediction.placeId
    }

    var title: String {
        placePrediction.structuredFormat.mainText.text
    }

    var subtitle: String {
        placePrediction.structuredFormat.secondaryText?.text ?? placePrediction.text.text
    }
}

enum PlacesAPIClient {
    static func autocomplete(_ query: String, apiKey: String) async throws -> [PlaceSuggestion] {
        let endpoint = URL(string: "https://places.googleapis.com/v1/places:autocomplete")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        setCommonHeaders(on: &request, apiKey: apiKey)
        request.httpBody = try JSONEncoder().encode(AutocompleteBody(input: query))
        let response: AutocompleteResponse = try await perform(request)
        return response.suggestions
    }

    static func fetchPlace(id: String, apiKey: String) async throws -> RidePlace {
        let endpoint = URL(string: "https://places.googleapis.com/v1/places/\(id)")!
        var request = URLRequest(url: endpoint)
        setCommonHeaders(on: &request, apiKey: apiKey)
        request.setValue("id,displayName,formattedAddress,location", forHTTPHeaderField: "X-Goog-FieldMask")
        let response: PlaceDetailsResponse = try await perform(request)
        return RidePlace(
            name: response.displayName.text,
            address: response.formattedAddress,
            coordinate: .init(latitude: response.location.latitude, longitude: response.location.longitude)
        )
    }

    private static func setCommonHeaders(on request: inout URLRequest, apiKey: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
    }

    private static func perform<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlacesAPIError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            let message = (try? JSONDecoder().decode(PlacesErrorEnvelope.self, from: data))?.error.message
            throw PlacesAPIError.server(message ?? "Places API returned status \(httpResponse.statusCode).")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct AutocompleteBody: Encodable, Sendable {
    let input: String
}

private struct AutocompleteResponse: Decodable, Sendable {
    let suggestions: [PlaceSuggestion]
}

private struct PlaceDetailsResponse: Decodable, Sendable {
    struct DisplayName: Decodable, Sendable {
        let text: String
    }

    struct Location: Decodable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    let id: String
    let displayName: DisplayName
    let formattedAddress: String
    let location: Location
}

private struct PlacesErrorEnvelope: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let message: String
    }

    let error: Detail
}

private enum PlacesAPIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Google Places returned an invalid response."
        case let .server(message): message
        }
    }
}
