import SwiftUI
import MapKit

/// The real city map: every station at its position, the planned journey drawn on top, and the user's location.
struct StationsMapView: View {
    @Environment(MetroNetwork.self) private var network
    @Environment(LocationService.self) private var location
    let journey: Journey?

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: String?
    @State private var picked: Station?

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            UserAnnotation()

            ForEach(network.lines) { line in
                MapPolyline(coordinates: line.stations.compactMap { network.coordinate(of: $0) })
                    .stroke(Theme.lineColor(line).opacity(journey == nil ? 0.85 : 0.3), lineWidth: 4)
            }
            if let journey {
                ForEach(Array(journey.legs.enumerated()), id: \.offset) { _, leg in
                    if let line = network.lineByID[leg.line] {
                        MapPolyline(coordinates: leg.stops.compactMap { network.coordinate(of: $0) })
                            .stroke(Theme.lineColor(line), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    }
                }
            }

            ForEach(network.stations) { st in
                if let c = network.coordinate(of: st.id) {
                    Annotation(L10n.stationName(st), coordinate: c, anchor: .center) {
                        StationPin(station: st, role: role(of: st.id))
                    }
                    .tag(st.id)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            if network.hasApproximatePositions {
                Label(L10n.t("approx_pos"), systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle(L10n.t("map_city"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { NetworkMapView(journey: journey) } label: {
                    Label(L10n.t("map_schematic"), systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
        }
        .onChange(of: selectedID) {
            picked = selectedID.flatMap { network.stationByID[$0] }
            selectedID = nil
        }
        .stationActions($picked)
        .task {
            // Show the user on the map (asks for permission the first time, like the location button).
            if location.location == nil, !location.isDenied, location.status == .idle { _ = await location.locate() }
        }
    }

    private func role(of id: String) -> StationPin.Role {
        guard let journey else { return network.isInterchange(id) ? .interchange : .plain }
        if id == journey.legs.last?.alighting { return .destination }
        if id == journey.legs.first?.boarding { return .origin }
        if journey.legs.contains(where: { $0.stops.contains(id) }) { return .onRoute }
        return network.isInterchange(id) ? .interchange : .plain
    }
}

/// Station marker in the brand language: dot, interchange ring, and the gold-centred arrival ring.
struct StationPin: View {
    enum Role { case plain, interchange, onRoute, origin, destination }
    @Environment(MetroNetwork.self) private var network
    let station: Station
    let role: Role

    var body: some View {
        let color = network.linesAt[station.id]?.first.flatMap { network.lineByID[$0] }.map(Theme.lineColor) ?? .gray
        Group {
            switch role {
            case .destination:
                ZStack {
                    Circle().fill(Color(.systemBackground))
                    Circle().strokeBorder(Color.primary, lineWidth: 4)
                    Circle().fill(Brand.gold).frame(width: 9, height: 9)
                }
                .frame(width: 24, height: 24)
            case .origin:
                Circle().fill(Color.primary).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
            case .interchange:
                Circle().fill(Color(.systemBackground)).frame(width: 15, height: 15)
                    .overlay(Circle().strokeBorder(Color.primary, lineWidth: 3))
            case .onRoute:
                Circle().fill(Color(.systemBackground)).frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(color, lineWidth: 3))
            case .plain:
                Circle().fill(color).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            }
        }
        .frame(width: 30, height: 30)          // comfortable tap target
        .contentShape(Rectangle())
        .accessibilityLabel(L10n.stationName(station))
    }
}

/// "Stations near you" card used on the Plan screen.
struct NearbyCard: View {
    @Environment(MetroNetwork.self) private var network
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    let nearby: [NearbyStation]

    var body: some View {
        ForEach(nearby) { n in
            HStack(spacing: 12) {
                LineDots(stationID: n.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.stationName(n.station)).font(.body.weight(.semibold))
                    Text((n.approximate ? "~ " : "") + L10n.t("walk_info", ["m": L10n.minutes(n.walkMinutes), "d": distanceText(n.meters)]))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(L10n.t("start_here")) { router.setFrom(.station(n.id)) }
                    if let c = network.coordinate(of: n.id) {
                        Button { MapsLink.appleWalk(to: n.station, at: c) } label: {
                            Label(L10n.t("apple_maps"), systemImage: "map")
                        }
                        Button { openURL(MapsLink.googleWalk(to: c)) } label: {
                            Label(L10n.t("google_maps"), systemImage: "globe")
                        }
                    }
                } label: {
                    Image(systemName: "figure.walk.circle.fill").font(.title2).foregroundStyle(Brand.green)
                }
                .accessibilityLabel(L10n.t("walk_dir"))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func distanceText(_ m: Double) -> String {
        m < 1000 ? L10n.t("m_unit", ["n": (Int((m / 10).rounded()) * 10).formatted()])
                 : L10n.t("km", ["n": (m / 1000).formatted(.number.precision(.fractionLength(1)))])
    }
}
