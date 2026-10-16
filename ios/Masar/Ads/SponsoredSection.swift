import SwiftUI
import CoreLocation

/// The ad for the station a rider is heading to — or, when the station has a free slot,
/// a quiet invitation for local businesses to take it. Always labelled as an ad.
struct SponsoredSection: View {
    let stationID: String
    @Environment(AdsService.self) private var ads
    @Environment(MetroNetwork.self) private var network
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let station = network.stationByID[stationID] {
            if let c = ads.ads(at: stationID).first {
                Section {
                    card(c, station: station)
                } header: {
                    HStack(spacing: 8) {
                        Text(L10n.t("ad_tag"))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Brand.gold.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.primary)
                        Text(L10n.t("ad_near", ["st": L10n.stationName(station)]))
                    }
                    .textCase(nil)
                }
            } else if ads.freeSlots(at: stationID) > 0, let url = ads.advertiseURL(station: stationID) {
                Section {
                    Button { openURL(url) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "megaphone").foregroundStyle(Brand.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("ad_slot", ["st": L10n.stationName(station)])).font(.subheadline.weight(.semibold))
                                Text(L10n.t("ad_slot_sub")).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ c: AdCampaign, station: Station) -> some View {
        let name = AdsService.localized(c.name)
        let place = c.lat.flatMap { lat in c.lng.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
        let from = network.coordinate(of: station.id)
        let walk: Double? = {
            guard let p = place, let s = from else { return nil }
            return CLLocation(latitude: p.latitude, longitude: p.longitude)
                .distance(from: CLLocation(latitude: s.latitude, longitude: s.longitude)) * 1.25 / 80
        }()
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Self.symbol(c.category))
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Brand.gold.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name).font(.headline)
                        Text(L10n.t("cat_" + c.category)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(AdsService.localized(c.title)).font(.subheadline.weight(.semibold))
                    if let b = c.body, !b.isEmpty {
                        Text(AdsService.localized(b)).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let w = walk {
                        Label(L10n.t("ad_from_st", ["m": L10n.minutes(w)]), systemImage: "figure.walk")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.t("ad_tag") + ": " + name + ". " + AdsService.localized(c.title))

            HStack(spacing: 8) {
                if let url = AdsService.trackedURL(c, station: station.id) {
                    Button { openURL(url) } label: { Label(L10n.t("ad_visit"), systemImage: "arrow.up.right.square") }
                }
                if let p = place {
                    Menu {
                        Button { MapsLink.appleWalk(from: from, fromName: L10n.stationName(station), to: p, toName: name) } label: {
                            Label(L10n.t("apple_maps"), systemImage: "map")
                        }
                        Button { openURL(MapsLink.googleWalk(from: from, to: p)) } label: {
                            Label(L10n.t("google_maps"), systemImage: "globe")
                        }
                    } label: { Label(L10n.t("walk_dir"), systemImage: "figure.walk") }
                }
                if let phone = c.phone, let url = URL(string: "tel:" + phone.filter { !$0.isWhitespace }) {
                    Button { openURL(url) } label: { Label(L10n.t("ad_call"), systemImage: "phone") }
                }
            }
            // Bordered buttons stay separately tappable inside a List row.
            .buttonStyle(.bordered)
            .menuStyle(.button)
            .controlSize(.small)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
    }

    static func symbol(_ category: String) -> String {
        switch category {
        case "food": return "fork.knife"
        case "cafe": return "cup.and.saucer.fill"
        case "shop": return "bag.fill"
        case "health": return "heart.fill"
        case "services": return "wrench.and.screwdriver.fill"
        case "hotel": return "bed.double.fill"
        case "fun": return "sparkles"
        default: return "storefront.fill"
        }
    }
}
