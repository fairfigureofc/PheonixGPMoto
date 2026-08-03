import CoreLocation
@preconcurrency import GoogleMaps
import SwiftUI

struct MapsHomeView: View {
    @State private var locationModel = RiderLocationModel()
    @State private var planner = RidePlannerModel()
    @State private var searchTarget: SearchTarget?
    @State private var showSavedRides = false
    @State private var showStartedRide = false
    @State private var showNavigation = false
    @State private var showRoutePreview = false
    @State private var showSavedConfirmation = false

    var body: some View {
        NavigationStack {
            if let searchTarget {
                PlaceSearchView(title: searchTarget.title) { place in
                    apply(place, to: searchTarget)
                    self.searchTarget = nil
                } onCancel: {
                    self.searchTarget = nil
                }
            } else {
                plannerView
            }
        }
    }

    private var plannerView: some View {
        ZStack(alignment: .bottom) {
            RideMapView(
                riderCoordinate: locationModel.coordinate,
                origin: planner.usesCurrentLocation ? nil : planner.origin,
                destination: planner.destination,
                routes: planner.routes,
                selectedRouteID: planner.selectedRouteID,
                onSelectRoute: { planner.selectedRouteID = $0 }
            )
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                endpointCard
                Spacer()
                if !planner.routes.isEmpty {
                    routePicker
                }
                controlsCard
            }
            .padding()
        }
        .navigationTitle("Plan a ride")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Saved", systemImage: "bookmark") {
                    showSavedRides = true
                }
            }
        }
        .task { await locationModel.start() }
        .sheet(isPresented: $showSavedRides) {
            SavedRidesView(planner: planner) { ride in
                planner.load(ride)
                showSavedRides = false
            }
        }
        .sheet(isPresented: $showRoutePreview) {
            if let route = planner.selectedRoute, let destination = planner.destination {
                RoutePreviewView(
                    route: route,
                    originName: planner.usesCurrentLocation ? "Current location" : planner.origin?.name ?? "Starting point",
                    riderCoordinate: locationModel.coordinate,
                    origin: planner.usesCurrentLocation ? nil : planner.origin,
                    destination: destination,
                    onSave: { description in
                        planner.saveRide(description: description)
                        showRoutePreview = false
                        showSavedConfirmation = true
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showNavigation) {
            if let route = planner.startedRoute, let destination = planner.destination {
                WalkingNavigationView(
                    initialRoute: route,
                    destination: destination,
                    avoidHighways: planner.avoidHighways,
                    avoidTolls: planner.avoidTolls
                )
            }
        }
        .alert("Couldn’t plan ride", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(planner.errorMessage ?? "Unknown error")
        }
        .alert("Ride ready", isPresented: $showStartedRide) {
            Button("Continue", role: .cancel) {}
        } message: {
            Text("The route is selected. Next we’ll connect its maneuver steps to the ESP32 ride display.")
        }
        .alert("Route saved", isPresented: $showSavedConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can find it under Saved rides.")
        }
    }

    private var endpointCard: some View {
        VStack(spacing: 0) {
            Button {
                searchTarget = .origin
            } label: {
                endpointRow(
                    icon: "circle.circle",
                    title: planner.usesCurrentLocation ? "Current location" : planner.origin?.name ?? "Choose starting point",
                    subtitle: planner.usesCurrentLocation ? "Using your phone’s GPS" : planner.origin?.address
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 42)

            Button {
                searchTarget = .destination
            } label: {
                endpointRow(
                    icon: "location.fill",
                    title: planner.destination?.name ?? "Choose destination",
                    subtitle: planner.destination?.address
                )
            }
            .buttonStyle(.plain)

            if !planner.usesCurrentLocation {
                Divider().padding(.leading, 42)
                Button("Use current location instead", systemImage: "location") {
                    planner.usesCurrentLocation = true
                    clearCalculatedRoutes()
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func endpointRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                if let subtitle, subtitle != title {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding()
    }

    private var routePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(planner.routes.enumerated()), id: \.element.id) { index, route in
                    Button {
                        planner.selectedRouteID = route.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(index == 0 ? "Recommended" : "Route \(index + 1)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(route.durationText).font(.headline)
                            Text(route.distanceText).font(.subheadline)
                        }
                        .frame(width: 120, alignment: .leading)
                        .padding(12)
                        .background(
                            planner.selectedRouteID == route.id ? Color.primary : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(planner.selectedRouteID == route.id ? Color(uiColor: .systemBackground) : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controlsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("Avoid highways", isOn: $planner.avoidHighways)
                Toggle("Avoid tolls", isOn: $planner.avoidTolls)
            }
            .font(.caption)
            .onChange(of: planner.avoidHighways) { clearCalculatedRoutes() }
            .onChange(of: planner.avoidTolls) { clearCalculatedRoutes() }

            if planner.routes.isEmpty {
                Button {
                    Task { await planner.calculateRoutes(currentLocation: locationModel.coordinate) }
                } label: {
                    if planner.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Show routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(planner.destination == nil || planner.isLoading)
            } else {
                HStack {
                    Button("Preview", systemImage: "list.bullet.rectangle") {
                        showRoutePreview = planner.selectedRoute != nil
                    }
                    .buttonStyle(.bordered)

                    Button("Start", systemImage: "figure.outdoor.cycle") {
                        planner.startedRoute = planner.selectedRoute
                        showNavigation = planner.startedRoute != nil
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { planner.errorMessage != nil },
            set: {
                if !$0 {
                    planner.errorMessage = nil
                }
            }
        )
    }

    private func clearCalculatedRoutes() {
        planner.routes = []
        planner.selectedRouteID = nil
    }

    private func apply(_ place: RidePlace, to target: SearchTarget) {
        switch target {
        case .origin:
            planner.usesCurrentLocation = false
            planner.origin = place
        case .destination:
            planner.destination = place
        }
        clearCalculatedRoutes()
    }

    private enum SearchTarget {
        case origin
        case destination

        var title: String {
            switch self {
            case .origin: "Starting point"
            case .destination: "Destination"
            }
        }
    }
}

private struct RideMapView: UIViewRepresentable {
    let riderCoordinate: CLLocationCoordinate2D?
    let origin: RidePlace?
    let destination: RidePlace?
    let routes: [RouteOption]
    let selectedRouteID: String?
    let onSelectRoute: (String) -> Void

    func makeUIView(context: Context) -> GMSMapView {
        let fallback = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition.camera(withTarget: riderCoordinate ?? fallback, zoom: 12)
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(on: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, @MainActor GMSMapViewDelegate {
        var parent: RideMapView
        private var routeSignature = ""
        private var polylines: [GMSPolyline: String] = [:]
        private var markers: [GMSMarker] = []

        init(parent: RideMapView) {
            self.parent = parent
        }

        @MainActor
        func render(on mapView: GMSMapView) {
            let signature = parent.routes.map(\.id).joined() + (parent.selectedRouteID ?? "")
            guard signature != routeSignature else { return }
            routeSignature = signature
            polylines.keys.forEach { $0.map = nil }
            markers.forEach { $0.map = nil }
            polylines.removeAll()
            markers.removeAll()

            if let origin = parent.origin {
                markers.append(marker(at: origin.coordinate, title: origin.name, map: mapView))
            }
            if let destination = parent.destination {
                markers.append(marker(at: destination.coordinate, title: destination.name, map: mapView))
            }

            var bounds = GMSCoordinateBounds()
            for route in parent.routes.reversed() {
                guard let path = GMSPath(fromEncodedPath: route.encodedPolyline) else { continue }
                let polyline = GMSPolyline(path: path)
                let selected = route.id == parent.selectedRouteID
                polyline.strokeColor = selected ? .label : .systemGray2
                polyline.strokeWidth = selected ? 7 : 4
                polyline.zIndex = selected ? 2 : 1
                polyline.isTappable = true
                polyline.map = mapView
                polylines[polyline] = route.id
                if selected {
                    bounds = bounds.includingPath(path)
                }
            }
            if !parent.routes.isEmpty {
                mapView.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 70))
            }
        }

        @MainActor
        func mapView(_: GMSMapView, didTap overlay: GMSOverlay) {
            guard let polyline = overlay as? GMSPolyline, let routeID = polylines[polyline] else { return }
            parent.onSelectRoute(routeID)
        }

        @MainActor
        private func marker(at coordinate: CLLocationCoordinate2D, title: String, map: GMSMapView) -> GMSMarker {
            let marker = GMSMarker(position: coordinate)
            marker.title = title
            marker.map = map
            return marker
        }
    }
}

private struct SavedRidesView: View {
    @Bindable var planner: RidePlannerModel
    let onSelect: (SavedRide) -> Void

    var body: some View {
        NavigationStack {
            List {
                if planner.savedRides.isEmpty {
                    ContentUnavailableView("No saved rides", systemImage: "bookmark", description: Text("Plan and save a route to reuse it later."))
                } else {
                    ForEach(planner.savedRides) { ride in
                        Button {
                            onSelect(ride)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ride.name).font(.headline)
                                Text(ride.usesCurrentLocation ? "Current location" : ride.origin?.name ?? "Starting point")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let description = ride.description {
                                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                    .onDelete(perform: planner.deleteSavedRides)
                }
            }
            .navigationTitle("Saved rides")
        }
    }
}

private struct RoutePreviewView: View {
    let route: RouteOption
    let originName: String
    let riderCoordinate: CLLocationCoordinate2D?
    let origin: RidePlace?
    let destination: RidePlace
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RideMapView(
                        riderCoordinate: riderCoordinate,
                        origin: origin,
                        destination: destination,
                        routes: [route],
                        selectedRouteID: route.id,
                        onSelectRoute: { _ in }
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    LabeledContent("From", value: originName)
                    LabeledContent("To", value: destination.name)
                    LabeledContent("Ride time", value: route.durationText)
                    LabeledContent("Distance", value: route.distanceText)
                }

                Section("Ride notes") {
                    TextField("Description, meeting point, road notes…", text: $description, axis: .vertical)
                        .lineLimit(2 ... 4)
                }

                Section("Roads and turns") {
                    ForEach(Array(route.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: step.symbolName)
                                .font(.title3)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.instruction).font(.body)
                                Text(step.distanceText).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(index + 1)").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle("Route preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(description) }
                }
            }
        }
    }
}
