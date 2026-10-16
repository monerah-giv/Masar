import SwiftUI

struct StationPicker: View {
    @Environment(MetroNetwork.self) private var network
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// Shows "Current location" as the first choice (used for the From field).
    var onCurrentLocation: (() -> Void)? = nil
    /// Enables Apple Maps place search (malls, hospitals, addresses…) under the stations.
    var onPlace: ((PlacePoint) -> Void)? = nil
    let onPick: (Station) -> Void
    @State private var query = ""
    @State private var places = PlaceSearch()

    var body: some View {
        let results = StationSearch.filter(query, in: network)
        NavigationStack {
            List {
                if let onCurrentLocation, query.isEmpty {
                    Section {
                        Button {
                            onCurrentLocation()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Brand.green))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t("cur_loc")).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(L10n.t("cur_loc_sub")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityHint(L10n.t("cur_loc_sub"))
                    }
                }
                Section {
                    ForEach(results) { st in
                        Button {
                            onPick(st)
                            dismiss()
                        } label: { StationRow(station: st) }
                    }
                } header: {
                    if onPlace != nil, !query.isEmpty { Text(L10n.t("stations_section")) }
                }
                if let onPlace, !places.results.isEmpty {
                    Section(L10n.t("places_section")) {
                        ForEach(places.results, id: \.self) { c in
                            Button {
                                Task {
                                    if let p = await places.resolve(c) { onPlace(p); dismiss() }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).foregroundStyle(.primary)
                                        if !c.subtitle.isEmpty {
                                            Text(c.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .disabled(places.resolving)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: query) { if onPlace != nil { places.update(query) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.t("search_station"))
            .overlay {
                if results.isEmpty, places.results.isEmpty, !query.isEmpty {
                    ContentUnavailableView(L10n.t("no_match"), systemImage: "magnifyingglass")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("cancel")) { dismiss() } }
            }
        }
    }
}

struct LinesView: View {
    @Environment(MetroNetwork.self) private var network
    @State private var picked: Station?

    var body: some View {
        List {
            ForEach(network.lines) { line in
                Section {
                    ForEach(line.stations, id: \.self) { id in
                        if let st = network.stationByID[id] {
                            Button { picked = st } label: { StationRow(station: st) }
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        LineBadge(id: line.id)
                        Text(L10n.lineName(line.id))
                        Spacer()
                        Text("\(L10n.stations(line.stations.count)) · \(L10n.t("km", ["n": line.lengthKm.formatted()]))")
                    }
                }
            }
        }
        .navigationTitle(L10n.t("lines_title"))
        .stationActions($picked)
    }
}
