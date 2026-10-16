import SwiftUI
import SwiftData
import UIKit
import CoreLocation

/// The trip screen. Opens already located ("From: Current location") when permission was given,
/// so the whole flow is: pick a destination → the result appears, scrolls into view and taps the phone.
struct PlanView: View {
    @Environment(MetroNetwork.self) private var network
    @Environment(FareBook.self) private var fares
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FavoritePlace.createdAt) private var places: [FavoritePlace]
    @Query(sort: \TripRecord.plannedAt, order: .reverse) private var recents: [TripRecord]
    @Query private var savedRoutes: [SavedRoute]
    @AppStorage("fare.class") private var fareClassRaw = FareClass.standard.rawValue
    @AppStorage("fare.discount") private var discount = false

    @State private var picking: Field?
    @State private var leaveNow = true
    @State private var departure = Date()
    @State private var nearby: [NearbyStation] = []
    @State private var best: DoorTrip?
    @State private var alt: DoorTrip?
    @State private var resultStamp = 0
    @State private var lastDestKey = ""
    @State private var scrollRequest = 0
    @State private var didAutoLocate = false
    @State private var speaker = TripSpeaker()

    enum Field: String, Identifiable { case from, to; var id: String { rawValue } }

    private var planner: RoutePlanner { RoutePlanner(network: network) }
    private var otherPreference: RoutePreference { router.preference == .fastest ? .fewestTransfers : .fastest }

    // MARK: inputs → cached result

    private func key(_ e: Endpoint?) -> String {
        switch e {
        case .station(let id)?: return "s:\(id)"
        case .currentLocation?: return "here"
        case .place(let p)?: return "p:\(p.lat),\(p.lng)"
        case nil: return "-"
        }
    }
    /// Everything the result depends on. The location is rounded to ~10 m so GPS jitter doesn't recompute.
    private var inputsKey: String {
        let loc = location.location.map { String(format: "%.4f,%.4f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "none"
        return [key(router.origin), key(router.destination), router.preference.rawValue, loc, "\(network.refined.count)"].joined(separator: "|")
    }

    private func point(_ e: Endpoint?) -> RoutePoint? {
        switch e {
        case .station(let id)?: return .station(id)
        case .currentLocation?: return location.location.map(RoutePoint.location)
        case .place(let p)?: return .location(p.location)
        case nil: return nil
        }
    }

    /// Runs only when an input changes (not on every redraw).
    private func recompute() {
        guard let o = point(router.origin), let d = point(router.destination) else { best = nil; alt = nil; return }
        let newBest = planner.plan(o, d, preference: router.preference)
        alt = planner.plan(o, d, preference: otherPreference)
        if newBest != best { best = newBest; if newBest != nil { resultStamp += 1 } }
        let dk = key(router.destination)
        if dk != lastDestKey { lastDestKey = dk; if newBest != nil { scrollRequest += 1 } }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                inputSection

                if router.fromCurrentLocation, !nearby.isEmpty {
                    Section {
                        DisclosureGroup(L10n.t("nearest_title")) { NearbyCard(nearby: nearby) }
                    }
                }

                if let t = best {
                    summarySection(t).id("summary")
                    if let a = alt, a.transfers != t.transfers || Int(a.totalMinutes.rounded()) != Int(t.totalMinutes.rounded()) {
                        alternativeRow(current: t, alt: a)
                    }
                    stepsSection(t)
                } else {
                    Section { Text(emptyMessage).foregroundStyle(.secondary) }
                }

                Section {
                    NavigationLink { StationsMapView(journey: best?.journey) } label: { Label(L10n.t("map_city"), systemImage: "map") }
                    NavigationLink { NetworkMapView(journey: best?.journey) } label: { Label(L10n.t("map_schematic"), systemImage: "point.3.connected.trianglepath.dotted") }
                    NavigationLink { LinesView() } label: { Label(L10n.t("lines_title"), systemImage: "list.bullet.rectangle") }
                }
            }
            .onChange(of: scrollRequest) {
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo("summary", anchor: .top) }
            }
        }
        .navigationTitle(L10n.t("app_name"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { MasarWordmark(color: .primary).frame(height: 30) }
            ToolbarItem(placement: .topBarTrailing) { ServiceStatusBadge() }
        }
        .sheet(item: $picking) { field in
            StationPicker(title: L10n.t(field == .from ? "from_ph" : "to_ph"),
                          onCurrentLocation: field == .from ? { Task { await useCurrentLocation() } } : nil,
                          onPlace: { p in field == .from ? router.setFrom(.place(p)) : router.setTo(.place(p)) }) { st in
                field == .from ? router.setFrom(.station(st.id)) : router.setTo(.station(st.id))
            }
        }
        .onChange(of: inputsKey, initial: true) { recompute() }
        .sensoryFeedback(.success, trigger: resultStamp)
        .onChange(of: key(router.origin) + ">" + key(router.destination)) {
            // History keeps station-to-station trips only; locations and addresses are never stored.
            if case .station(let f)? = router.origin, case .station(let t)? = router.destination, f != t {
                TripRecord.record(from: f, to: t, in: context)
            }
        }
        .task {
            // One tap less: if the user already allowed location, start from where they are.
            guard !didAutoLocate else { return }
            didAutoLocate = true
            if location.isAuthorized { await useCurrentLocation() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active, router.fromCurrentLocation,
               abs(location.location?.timestamp.timeIntervalSinceNow ?? .infinity) > 120 {
                Task { await useCurrentLocation() }
            }
        }
        .onDisappear { speaker.stop() }
    }

    private var emptyMessage: String {
        if router.fromCurrentLocation, location.location == nil {
            return location.status == .locating ? L10n.t("locating") : L10n.t("pick_both")
        }
        if case .station(let a)? = router.origin, case .station(let b)? = router.destination, a == b {
            return L10n.t("same_station")
        }
        return L10n.t("pick_both")
    }

    // MARK: inputs

    @ViewBuilder
    private var inputSection: some View {
        @Bindable var router = router
        Section {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    endpointButton(.from)
                    Divider()
                    endpointButton(.to)
                }
                Button {
                    router.swap(boarding: best?.boardingID)
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.t("swap"))
            }
            quickDestinations
            locationRow
            Picker(selection: $router.preference) {
                Text(L10n.t("fastest")).tag(RoutePreference.fastest)
                Text(L10n.t("fewest")).tag(RoutePreference.fewestTransfers)
            } label: { EmptyView() }
            .pickerStyle(.segmented)
            Toggle(L10n.t("leave_now"), isOn: $leaveNow)
            if !leaveNow {
                DatePicker(L10n.t("depart_at"), selection: $departure, displayedComponents: .hourAndMinute)
            }
        }
    }

    /// One tap to go home, to work, or back to a recent destination.
    @ViewBuilder
    private var quickDestinations: some View {
        let recentTo = recents.map(\.toID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .filter { id in !places.contains { $0.stationID == id } && key(router.destination) != "s:\(id)" }
            .prefix(4)
        if !places.isEmpty || !recentTo.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(places) { p in
                        Button { router.setTo(.station(p.stationID)) } label: {
                            Label(p.displayLabel, systemImage: p.kind.symbol)
                        }
                        .buttonStyle(.bordered)
                    }
                    ForEach(Array(recentTo), id: \.self) { id in
                        if let st = network.stationByID[id] {
                            Button { router.setTo(.station(id)) } label: {
                                Label(L10n.stationName(st), systemImage: "clock.arrow.circlepath")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityLabel(L10n.t("quick_dest"))
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        switch location.status {
        case .locating where router.fromCurrentLocation:
            Label(L10n.t("locating"), systemImage: "location.fill").foregroundStyle(.secondary)
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.t("loc_denied"), systemImage: "location.slash").font(.footnote)
                Button(L10n.t("open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
            }
        default:
            if !router.fromCurrentLocation {
                Button { Task { await useCurrentLocation() } } label: {
                    Label(L10n.t("use_location"), systemImage: "location.fill").font(.body.weight(.semibold))
                }
            }
            if location.status == .failed {
                Text(L10n.t("loc_failed")).font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    /// Make "Current location" the start of the trip. Reuses a fix under two minutes old,
    /// otherwise asks for a fresh one; goes back to the last station if location is unavailable.
    private func useCurrentLocation() async {
        router.setFrom(.currentLocation)
        var here = location.location
        if here == nil || abs(here!.timestamp.timeIntervalSinceNow) > 120 {
            here = await location.locate()
        }
        guard let here else {
            if let last = router.fromID { router.setFrom(.station(last)) }
            return
        }
        nearby = network.nearest(to: here)
        await StationRefiner.refine(network.nearest(to: here, count: RoutePlanner.candidates).map(\.station), in: network)
        nearby = network.nearest(to: here)
    }

    private func endpointButton(_ field: Field) -> some View {
        let e = field == .from ? router.origin : router.destination
        return Button { picking = field } label: {
            HStack(spacing: 12) {
                Text(L10n.t(field.rawValue)).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
                switch e {
                case .currentLocation?:
                    Image(systemName: "location.fill").foregroundStyle(Brand.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("cur_loc")).foregroundStyle(.primary)
                        Text(accessLine).font(.caption).foregroundStyle(.secondary)
                    }
                case .place(let p)?:
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).foregroundStyle(.primary).lineLimit(1)
                        Text(p.subtitle.isEmpty ? L10n.t("places_section") : p.subtitle)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                case .station(let id)?:
                    if let st = network.stationByID[id] {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.stationName(st)).foregroundStyle(.primary)
                            Text(L10n.secondaryName(st)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                case nil:
                    Text(L10n.t(field == .from ? "from_ph" : "to_ph")).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private var accessLine: String {
        if location.status == .locating { return L10n.t("locating") }
        guard let a = best?.access else { return L10n.t("cur_loc_sub") }
        return (a.approximate ? "~ " : "") + L10n.t("via_station", ["st": L10n.stationName(a.station), "m": L10n.minutes(a.walkMinutes)])
    }

    // MARK: names and coordinates of the ends

    private func name(_ e: Endpoint?) -> String {
        switch e {
        case .station(let id)?: return network.stationByID[id].map(L10n.stationName) ?? id
        case .currentLocation?: return L10n.t("cur_loc")
        case .place(let p)?: return p.name
        case nil: return ""
        }
    }

    private func coordinate(_ e: Endpoint?) -> CLLocationCoordinate2D? {
        switch e {
        case .station(let id)?: return network.coordinate(of: id)
        case .currentLocation?: return location.location?.coordinate
        case .place(let p)?: return p.coordinate
        case nil: return nil
        }
    }

    // MARK: result

    @ViewBuilder
    private func summarySection(_ t: DoorTrip) -> some View {
        let fare = fares.price("t_2h", fareClass: FareClass(rawValue: fareClassRaw) ?? .standard, discountEligible: discount)
        let eta = etaText(t.totalMinutes)
        let far = max(t.access?.meters ?? 0, t.egress?.meters ?? 0) > RoutePlanner.maxWalkMeters
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Int(t.totalMinutes.rounded()).formatted())
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(Brand.green)
                        .contentTransition(.numericText())
                    Text(L10n.t("approx_min")).font(.subheadline).foregroundStyle(.secondary)
                }
                if let w = t.walkOnlyMinutes {
                    Text(L10n.t("walk_direct", ["m": L10n.minutes(w)])).font(.subheadline.weight(.semibold))
                } else if t.journey == nil, let a = t.access {
                    Text(L10n.t("walk_only", ["m": L10n.minutes(a.walkMinutes)])).font(.subheadline.weight(.semibold))
                }
                ViewThatFits(in: .horizontal) {
                    HStack { facts(t, fare: fare) }
                    VStack(alignment: .leading, spacing: 6) { facts(t, fare: fare) }
                }
                Text(eta.text)
                    .font(.subheadline)
                    .foregroundStyle(eta.warning ? Color.orange : Color.secondary)
                if far, let d = [t.access, t.egress].compactMap({ $0 }).max(by: { $0.meters < $1.meters }) {
                    Label(L10n.t("far_metro", ["d": distanceText(d.meters)]), systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                } else if let a = t.access, let nearest = nearby.first, nearest.id != a.id {
                    Text(L10n.t("best_stop_note")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            if let j = t.journey {
                RouteRibbon(journey: j, walkMinutes: t.access?.walkMinutes).padding(.vertical, 6)
            }

            HStack(spacing: 10) {
                Button { speaker.toggle(spokenText(t)) } label: {
                    Label(L10n.t(speaker.speaking ? "stop_listen" : "listen"),
                          systemImage: speaker.speaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)
                if t.journey != nil { ShareLink(item: tripText(t)).buttonStyle(.bordered) }
            }

            if t.journey != nil, case .station(let f)? = router.origin, case .station(let to)? = router.destination {
                let saved = savedRoutes.first { $0.fromID == f && $0.toID == to }
                Button {
                    if let saved { context.delete(saved) } else { context.insert(SavedRoute(fromID: f, toID: to)) }
                } label: {
                    Label(L10n.t(saved == nil ? "save_route" : "route_saved"), systemImage: saved == nil ? "star" : "star.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func facts(_ t: DoorTrip, fare: TicketPrice?) -> some View {
        if t.walkMinutes > 0 {
            Label(L10n.minutes(t.walkMinutes), systemImage: "figure.walk").chip()
        }
        if let j = t.journey {
            Text(L10n.stops(j.rideCount)).chip()
            Text(L10n.transfers(j.transfers)).chip()
            Text(L10n.t("fare_chip", ["price": L10n.price(fare?.now ?? 4)])).chip()
        }
    }

    private func alternativeRow(current: DoorTrip, alt: DoorTrip) -> some View {
        let d = Int((alt.totalMinutes - current.totalMinutes).rounded())
        let text = router.preference == .fastest
            ? L10n.t("alt_fewer", ["x": L10n.transfers(alt.transfers), "m": L10n.minutes(Double(max(1, d)))])
            : L10n.t("alt_faster", ["m": L10n.minutes(alt.totalMinutes), "x": L10n.transfers(alt.transfers)])
        return Section {
            HStack {
                Text(text).font(.subheadline)
                Spacer()
                Button(L10n.t("alt_show")) { router.preference = otherPreference }
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func stepsSection(_ t: DoorTrip) -> some View {
        Section {
            if t.walkOnlyMinutes != nil, let to = coordinate(router.destination) {
                walkStep(title: name(router.origin), detail: L10n.t("walk_direct", ["m": L10n.minutes(t.totalMinutes)]),
                         symbol: "figure.walk", from: originWalkStart, fromName: name(router.origin),
                         to: to, toName: name(router.destination))
            }
            if let a = t.access, let c = network.coordinate(of: a.id) {
                walkStep(title: name(router.origin),
                         detail: (a.approximate ? "~ " : "") + L10n.t("walk_to", ["st": L10n.stationName(a.station)]) + " · " + L10n.minutes(a.walkMinutes),
                         symbol: router.fromCurrentLocation ? "location.fill" : "mappin.circle.fill",
                         from: originWalkStart, fromName: name(router.origin), to: c, toName: L10n.stationName(a.station))
            }
            if let j = t.journey {
                if let from = network.stationByID[j.legs.first?.boarding ?? ""] {
                    node(title: L10n.stationName(from), detail: L10n.t("start_sub", ["m": L10n.minutes(network.params.initialWaitMin)]), symbol: "circle.circle")
                }
                ForEach(Array(j.legs.enumerated()), id: \.offset) { i, leg in
                    legRow(leg)
                    if i < j.legs.count - 1, let x = network.stationByID[leg.alighting] {
                        node(title: L10n.t("change_at", ["st": L10n.stationName(x)]),
                             detail: L10n.t("change_sub", ["a": L10n.lineName(leg.line), "b": L10n.lineName(j.legs[i + 1].line),
                                                           "m": L10n.minutes(network.params.transferMin)]),
                             symbol: "arrow.triangle.swap")
                    }
                }
            }
            if let e = t.egress, let from = network.coordinate(of: e.id), let to = coordinate(router.destination) {
                node(title: L10n.t("get_off", ["st": L10n.stationName(e.station)]), detail: "", symbol: "circle.circle")
                walkStep(title: L10n.t("walk_from_to", ["st": L10n.stationName(e.station), "place": name(router.destination)]),
                         detail: (e.approximate ? "~ " : "") + L10n.minutes(e.walkMinutes) + " · " + distanceText(e.meters),
                         symbol: "figure.walk", from: from, fromName: L10n.stationName(e.station), to: to, toName: name(router.destination))
            }
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(router.destination)).font(.body.weight(.semibold))
                    Text(L10n.t("arrive")).font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                ZStack {
                    Circle().strokeBorder(Color.primary, lineWidth: 3.5)
                    Circle().fill(Brand.gold).frame(width: 8, height: 8)
                }
                .frame(width: 20, height: 20)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// nil = start the directions from wherever the phone is (Maps handles it); a place starts from its own point.
    private var originWalkStart: CLLocationCoordinate2D? {
        if case .place(let p)? = router.origin { return p.coordinate }
        return nil
    }

    private func walkStep(title: String, detail: String, symbol: String,
                          from: CLLocationCoordinate2D?, fromName: String,
                          to: CLLocationCoordinate2D, toName: String) -> some View {
        HStack(spacing: 12) {
            node(title: title, detail: detail, symbol: symbol)
            Spacer(minLength: 0)
            Menu {
                Button { MapsLink.appleWalk(from: from, fromName: fromName, to: to, toName: toName) } label: {
                    Label(L10n.t("apple_maps"), systemImage: "map")
                }
                Button { openURL(MapsLink.googleWalk(from: from, to: to)) } label: {
                    Label(L10n.t("google_maps"), systemImage: "globe")
                }
            } label: {
                Image(systemName: "figure.walk.circle.fill").font(.title2).foregroundStyle(Brand.green)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(L10n.t("walk_dir"))
        }
    }

    private func node(title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
        } icon: { Image(systemName: symbol) }
        .accessibilityElement(children: .combine)
    }

    private func legRow(_ leg: JourneyLeg) -> some View {
        let color = network.lineByID[leg.line].map(Theme.lineColor) ?? .gray
        let toward = network.stationByID[leg.toward].map(L10n.stationName) ?? ""
        let mid = Array(leg.stops.dropFirst().dropLast())
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                LineBadge(id: leg.line)
                Text(L10n.t("ride", ["line": L10n.lineName(leg.line), "st": toward])).font(.body.weight(.semibold))
            }
            Text("\(L10n.stops(leg.rideCount)) · \(L10n.minutes(leg.minutes))").font(.footnote).foregroundStyle(.secondary)
            if let also = leg.alsoLine {
                Text(L10n.t("also_line", ["line": L10n.lineName(also)])).font(.footnote).foregroundStyle(.secondary)
            }
            if !mid.isEmpty {
                DisclosureGroup(L10n.t("mid_stops", ["n": mid.count.formatted()])) {
                    ForEach(mid, id: \.self) { id in
                        Text(network.stationByID[id].map(L10n.stationName) ?? id).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 5) }
        .padding(.vertical, 4)
    }

    // MARK: text

    private func distanceText(_ m: Double) -> String {
        m < 1000 ? L10n.t("m_unit", ["n": (Int((m / 10).rounded()) * 10).formatted()])
                 : L10n.t("km", ["n": (m / 1000).formatted(.number.precision(.fractionLength(1)))])
    }

    private func etaText(_ minutes: Double) -> (text: String, warning: Bool) {
        let h = fares.hours
        let dep = leaveNow ? Date() : departure
        guard h.isOpen(at: dep) else {
            return (L10n.t("closed_at", ["time": h.format(dep), "open": h.format(h.opening(on: dep))]), true)
        }
        let arrival = dep.addingTimeInterval(minutes * 60)
        return leaveNow
            ? (L10n.t("arrive_at", ["time": h.format(arrival)]), false)
            : (L10n.t("arrive_at_t", ["dep": h.format(dep), "time": h.format(arrival)]), false)
    }

    /// The trip as numbered steps, for sharing.
    private func steps(_ t: DoorTrip) -> [String] {
        var out: [String] = []
        if let w = t.walkOnlyMinutes { out.append(L10n.t("walk_direct", ["m": L10n.minutes(w)])) }
        if let a = t.access { out.append(L10n.t("walk_to", ["st": L10n.stationName(a.station)]) + " (\(L10n.minutes(a.walkMinutes)))") }
        if let j = t.journey {
            for (i, leg) in j.legs.enumerated() {
                let toward = network.stationByID[leg.toward].map(L10n.stationName) ?? ""
                out.append(L10n.t("ride", ["line": L10n.lineName(leg.line), "st": toward]) + " (\(L10n.stops(leg.rideCount)))")
                if i < j.legs.count - 1, let x = network.stationByID[leg.alighting] {
                    out.append(L10n.t("change_at", ["st": L10n.stationName(x)]))
                }
            }
        }
        if let e = t.egress {
            out.append(L10n.t("get_off", ["st": L10n.stationName(e.station)]))
            out.append(L10n.t("walk_from_to", ["st": L10n.stationName(e.station), "place": name(router.destination)]) + " (\(L10n.minutes(e.walkMinutes)))")
        }
        out.append(L10n.t("arrive") + ": " + name(router.destination))
        return out
    }

    private func tripText(_ t: DoorTrip) -> String {
        (["\(L10n.t("app_name")): \(name(router.origin)) → \(name(router.destination))",
          "\(L10n.minutes(t.totalMinutes)) · \(L10n.transfers(t.transfers))"]
         + steps(t).enumerated().map { "\($0.offset + 1). \($0.element)" }).joined(separator: "\n")
    }

    /// Plain sentences for the speech synthesiser (no arrows or numbering).
    private func spokenText(_ t: DoorTrip) -> String {
        ([L10n.minutes(t.totalMinutes) + ", " + L10n.transfers(t.transfers), etaText(t.totalMinutes).text] + steps(t))
            .joined(separator: ". ")
    }
}

private struct Chip: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.footnote.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().strokeBorder(.quaternary))
    }
}
extension View { func chip() -> some View { modifier(Chip()) } }
