import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

enum Theme {
    static func lineColor(_ line: MetroLine) -> Color {
        let light = UIColor(hex: line.colorLight), dark = UIColor(hex: line.colorDark)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    /// Text on a line-coloured badge: dark on yellow, white elsewhere.
    static func onLine(_ id: Int) -> Color { id == 4 ? Color(white: 0.1) : .white }
}

struct LineBadge: View {
    @Environment(MetroNetwork.self) private var network
    let id: Int
    var body: some View {
        Text(id.formatted())
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.onLine(id))
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 4)
            .background(Capsule().fill(network.lineByID[id].map(Theme.lineColor) ?? .gray))
            .accessibilityLabel(L10n.lineName(id))
    }
}

struct LineDots: View {
    @Environment(MetroNetwork.self) private var network
    let stationID: String
    var body: some View {
        HStack(spacing: 3) {
            ForEach(network.linesAt[stationID] ?? [], id: \.self) { id in
                Circle().fill(network.lineByID[id].map(Theme.lineColor) ?? .gray).frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

struct StationRow: View {
    @Environment(MetroNetwork.self) private var network
    let station: Station
    var body: some View {
        HStack(spacing: 12) {
            LineDots(stationID: station.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.stationName(station)).foregroundStyle(.primary)
                Text(L10n.secondaryName(station)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if network.isInterchange(station.id) {
                Image(systemName: "arrow.triangle.swap").foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.t("interchange"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
