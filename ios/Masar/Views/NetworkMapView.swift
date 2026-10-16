import SwiftUI

/// Schematic network map drawn from the coordinates in network.json, with the current journey highlighted.
struct NetworkMapView: View {
    @Environment(MetroNetwork.self) private var network
    let journey: Journey?

    @State private var zoom: CGFloat = 1
    @State private var picked: Station?

    private let canvasSize = CGSize(width: 1000, height: 980)
    private let labelled: Set<String> = ["sabb", "kafd", "stc", "museum", "qasrhokm", "moe", "hamra", "naseem", "sabic",
                                         "darbaida", "ksu", "kfstadium", "jeddahrd", "khashm", "t12"]

    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width / canvasSize.width, 0.36) * zoom
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in draw(&ctx, scale: s) }
                        .frame(width: canvasSize.width * s, height: canvasSize.height * s)
                        .accessibilityHidden(true)
                    ForEach(network.stations) { st in
                        Button { picked = st } label: { Color.clear.frame(width: 34, height: 34).contentShape(Rectangle()) }
                            .position(x: st.x * s, y: st.y * s)
                            .accessibilityLabel(L10n.stationName(st))
                    }
                }
                .frame(width: canvasSize.width * s, height: canvasSize.height * s)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                Divider().frame(height: 24)
                Button { zoom = min(3, zoom + 0.5) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
            }
            .background(.regularMaterial, in: Capsule())
            .padding()
        }
        .navigationTitle(L10n.t("map_title"))
        .navigationBarTitleDisplayMode(.inline)
        .stationActions($picked)
    }

    private func point(_ id: String, line: Int, scale s: CGFloat) -> CGPoint {
        guard let st = network.stationByID[id] else { return .zero }
        var dy: CGFloat = 0
        if ["kafd", "rabi", "uthman", "sabic"].contains(id) { dy = line == 4 ? -5 : (line == 6 ? 5 : 0) }
        return CGPoint(x: st.x * s, y: (st.y + dy) * s)
    }

    private func draw(_ ctx: inout GraphicsContext, scale s: CGFloat) {
        let routed = journey != nil
        let base = routed ? 0.22 : 1.0
        for line in network.lines {
            var path = Path()
            for (i, id) in line.stations.enumerated() {
                let p = point(id, line: line.id, scale: s)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(Theme.lineColor(line).opacity(base)),
                       style: StrokeStyle(lineWidth: 8 * s, lineCap: .round, lineJoin: .round))
        }
        for st in network.stations {
            let p = CGPoint(x: st.x * s, y: st.y * s)
            if network.isInterchange(st.id) {
                let r = 9 * s
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(.systemBackground).opacity(base)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(Color.primary.opacity(base)), lineWidth: 3 * s)
            }
        }
        var keys = Set<String>()
        if let journey {
            for leg in journey.legs {
                var path = Path()
                for (i, id) in leg.stops.enumerated() {
                    let p = point(id, line: leg.line, scale: s)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                let color = network.lineByID[leg.line].map(Theme.lineColor) ?? .gray
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 12 * s, lineCap: .round, lineJoin: .round))
                keys.insert(leg.boarding); keys.insert(leg.alighting)
            }
            for id in keys {
                guard let st = network.stationByID[id] else { continue }
                let r = 11 * s
                let rect = CGRect(x: st.x * s - r, y: st.y * s - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(.systemBackground)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.primary), lineWidth: 4 * s)
            }
        }
        for id in labelled.union(keys) {
            guard let st = network.stationByID[id] else { continue }
            let text = Text(L10n.stationName(st))
                .font(.system(size: max(10, 19 * s), weight: keys.contains(id) ? .bold : .semibold))
                .foregroundStyle(Color.primary.opacity(routed && !keys.contains(id) ? 0.35 : 1))
            let left = st.x > 500
            ctx.draw(text, at: CGPoint(x: (st.x + (left ? -16 : 16)) * s, y: (st.y - 16) * s),
                     anchor: left ? .bottomTrailing : .bottomLeading)
        }
    }
}
