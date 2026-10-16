import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack { PlanView() }
                .tabItem { Label(L10n.t("tab_plan"), systemImage: "tram.fill") }
                .tag(AppRouter.Tab.plan)
            NavigationStack { SavedView() }
                .tabItem { Label(L10n.t("tab_saved"), systemImage: "bookmark.fill") }
                .tag(AppRouter.Tab.saved)
            NavigationStack { FaresView() }
                .tabItem { Label(L10n.t("tab_fares"), systemImage: "ticket.fill") }
                .tag(AppRouter.Tab.fares)
            NavigationStack { AccountView() }
                .tabItem { Label(L10n.t("tab_account"), systemImage: "person.crop.circle") }
                .tag(AppRouter.Tab.account)
        }
    }
}

/// Station action dialog shared by the map and the line list.
struct StationActions: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(MetroNetwork.self) private var network
    @Environment(\.openURL) private var openURL
    @Binding var picked: Station?
    @State private var addingPlace: Station?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(picked.map(L10n.stationName) ?? "",
                                isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }),
                                titleVisibility: .visible,
                                presenting: picked) { st in
                Button(L10n.t("start_here")) { router.open(from: st.id, to: nil) }
                Button(L10n.t("go_here")) { router.open(from: nil, to: st.id) }
                Button(L10n.t("save_place")) { addingPlace = st }
                if let c = network.coordinate(of: st.id) {
                    Button("\(L10n.t("walk_dir")) · \(L10n.t("apple_maps"))") { MapsLink.appleWalk(to: st, at: c) }
                    Button("\(L10n.t("walk_dir")) · \(L10n.t("google_maps"))") { openURL(MapsLink.googleWalk(to: c)) }
                }
                Button(L10n.t("cancel"), role: .cancel) {}
            }
            .sheet(item: $addingPlace) { st in AddPlaceView(initialStation: st.id) }
    }
}

extension View {
    func stationActions(_ picked: Binding<Station?>) -> some View { modifier(StationActions(picked: picked)) }
}

struct ServiceStatusBadge: View {
    @Environment(FareBook.self) private var fares

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let open = fares.hours.isOpen(at: ctx.date)
            Label(open ? L10n.t("open_now") : L10n.t("closed_now", ["t": fares.hours.format(fares.hours.opening(on: ctx.date))]),
                  systemImage: open ? "circle.fill" : "moon.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(open ? Color.accentColor : Color.orange)
        }
    }
}
