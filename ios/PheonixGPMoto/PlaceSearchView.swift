import SwiftUI

struct PlaceSearchView: View {
    let title: String
    let onSelection: (RidePlace) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var suggestions: [PlaceSuggestion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Address or place", text: $query)
                        .focused($searchIsFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") {
                            query = ""
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if query.isEmpty {
                ContentUnavailableView(
                    "Search for a place",
                    systemImage: "magnifyingglass",
                    description: Text("Enter an address, landmark, or business.")
                )
            } else if isLoading, suggestions.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                ForEach(suggestions) { suggestion in
                    Button {
                        select(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.title).font(.headline)
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .disabled(isLoading)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            await updateSuggestions()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel", action: onCancel)
            }
        }
        .alert("Place search failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )
    }

    private func updateSuggestions() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let apiKey else { return }
            suggestions = try await PlacesAPIClient.autocomplete(trimmed, apiKey: apiKey)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ suggestion: PlaceSuggestion) {
        guard let apiKey else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let place = try await PlacesAPIClient.fetchPlace(id: suggestion.id, apiKey: apiKey)
                onSelection(place)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var apiKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !value.isEmpty else { return nil }
        return value
    }
}
