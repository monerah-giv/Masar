import SwiftUI
import SwiftData

struct SavedView: View {
    @Environment(MetroNetwork.self) private var network
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \FavoritePlace.createdAt) private var places: [FavoritePlace]
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var routes: [SavedRoute]
    @Query(sort: \TripRecord.plannedAt, order: .reverse) private var recents: [TripRecord]
    @State private var adding = false

    var body: some View {
        List {
            Section {
                if places.isEmpty { Text(L10n.t("empty_places")).foregroundStyle(.secondary) }
                ForEach(places) { p in
                    Button { router.open(from: nil, to: p.stationID) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.displayLabel).foregroundStyle(.primary)
                                Text(name(p.stationID)).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: p.kind.symbol) }
                    }
                }
                .onDelete { idx in idx.map { places[$0] }.forEach { context.delete($0) } }
                Button { adding = true } label: { Label(L10n.t("add_place"), systemImage: "plus.circle.fill") }
            } header: { Text(L10n.t("places")) }

            Section {
                if routes.isEmpty { Text(L10n.t("empty_routes")).foregroundStyle(.secondary) }
                ForEach(routes) { r in
                    Button { router.open(from: r.fromID, to: r.toID) } label: { pair(r.fromID, r.toID, symbol: "star.fill") }
                }
                .onDelete { idx in idx.map { routes[$0] }.forEach { context.delete($0) } }
            } header: { Text(L10n.t("routes")) }

            Section {
                if recents.isEmpty { Text(L10n.t("empty_recent")).foregroundStyle(.secondary) }
                ForEach(recents) { r in
                    Button { router.open(from: r.fromID, to: r.toID) } label: { pair(r.fromID, r.toID, symbol: "clock.arrow.circlepath") }
                }
            } header: {
                HStack {
                    Text(L10n.t("recent"))
                    Spacer()
                    if !recents.isEmpty {
                        Button(L10n.t("clear")) { recents.forEach { context.delete($0) } }.font(.footnote)
                    }
                }
            }
        }
        .navigationTitle(L10n.t("tab_saved"))
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) { AddPlaceView(initialStation: nil) }
    }

    private func name(_ id: String) -> String { network.stationByID[id].map(L10n.stationName) ?? id }

    private func pair(_ a: String, _ b: String, symbol: String) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(name(a))
                Image(systemName: "arrow.forward").font(.caption).foregroundStyle(.secondary)
                Text(name(b))
            }
            .foregroundStyle(.primary)
        } icon: { Image(systemName: symbol) }
    }
}

struct AddPlaceView: View {
    @Environment(MetroNetwork.self) private var network
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var places: [FavoritePlace]

    let initialStation: String?
    @State private var kind: PlaceKind = .home
    @State private var label = ""
    @State private var stationID: String?
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.t("place_name"), selection: $kind) {
                    ForEach(PlaceKind.allCases) { Text(L10n.t($0.labelKey)).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField(L10n.t(kind.labelKey), text: $label)
                    .accessibilityLabel(L10n.t("place_name"))
                Button { picking = true } label: {
                    HStack {
                        Text(L10n.t("station")).foregroundStyle(.primary)
                        Spacer()
                        Text(stationID.flatMap { network.stationByID[$0] }.map(L10n.stationName) ?? L10n.t("search_station"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("add_place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("save")) { save() }.disabled(stationID == nil)
                }
            }
            .sheet(isPresented: $picking) {
                StationPicker(title: L10n.t("station")) { stationID = $0.id }
            }
            .onAppear {
                if stationID == nil { stationID = initialStation }
                if initialStation != nil || places.contains(where: { $0.kind == .home }) { kind = .other }
            }
        }
    }

    private func save() {
        guard let stationID else { return }
        if kind != .other { places.filter { $0.kind == kind }.forEach { context.delete($0) } }
        context.insert(FavoritePlace(kind: kind, label: label.trimmingCharacters(in: .whitespaces), stationID: stationID))
        dismiss()
    }
}
