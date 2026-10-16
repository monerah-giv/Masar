import SwiftUI

/// Masar brand marks, drawn as vectors so they stay sharp at every size and follow light/dark mode.
/// Geometry matches brand/src/geo.py exactly: one monoline, octilinear (0°/45°/90°), round caps,
/// ring radius : stroke = 1.43, gold dot = 0.42 × ring radius.
enum Brand {
    static let green = Color.accentColor
    static let gold = Color("BrandGold")
    static let night = Color("BrandNight")
    static let mist = Color("BrandMist")
}

/// The wordmark مسار: م station ring, س three station ticks, ا mast, ر 45° branch.
struct MasarWordmark: View {
    var color: Color = Brand.night
    var dot: Color = Brand.gold

    var body: some View {
        Canvas { ctx, size in
            let vb = CGRect(x: 78, y: -7, width: 213, height: 158)
            let k = min(size.width / vb.width, size.height / vb.height)
            let ox = (size.width - vb.width * k) / 2 - vb.minX * k
            let oy = (size.height - vb.height * k) / 2 - vb.minY * k
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * k, y: oy + y * k) }
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: ox + (x - r) * k, y: oy + (y - r) * k, width: 2 * r * k, height: 2 * r * k))
            }
            let r: CGFloat = 20, base: CGFloat = 100, cx: CGFloat = 262
            let ax = cx - 118, rx = ax - 28

            var path = circle(cx, base - r, r)
            path.move(to: p(cx, base)); path.addLine(to: p(ax, base)); path.addLine(to: p(ax, base - 92))
            for t in [cx - 42, cx - 64, cx - 86] { path.move(to: p(t, base)); path.addLine(to: p(t, base - 24)) }
            path.move(to: p(rx, base - 18)); path.addLine(to: p(rx, base)); path.addLine(to: p(rx - 34, base + 34))

            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 14 * k, lineCap: .round, lineJoin: .round))
            ctx.fill(circle(cx, base - r, r * 0.42), with: .color(dot))
        }
        .aspectRatio(213 / 158, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(L10n.t("app_name"))
    }
}

/// The app symbol: a white leg rises at 45°, changes at the station ring, and leaves on a gold leg.
struct MasarSymbol: View {
    var background: Color? = Brand.green
    var leg: Color = .white
    var accent: Color = Brand.gold
    var cornerRadius: CGFloat = 0.225   // fraction of the side, matches the iOS icon mask

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let k = side / 1024
            let s = 90 * k, R = 128 * k, c = 512 * k, d = 236 * k, e = R * 0.7071
            if let background {
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                              cornerRadius: side * cornerRadius, style: .continuous), with: .color(background))
                ctx.clip(to: Path(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                                  cornerRadius: side * cornerRadius, style: .continuous))
            }
            let style = StrokeStyle(lineWidth: s, lineCap: .round, lineJoin: .round)
            var leg1 = Path()
            leg1.move(to: CGPoint(x: -60 * k, y: c + d)); leg1.addLine(to: CGPoint(x: c - d, y: c + d))
            leg1.addLine(to: CGPoint(x: c - e, y: c + e))
            var leg2 = Path()
            leg2.move(to: CGPoint(x: c + e, y: c - e)); leg2.addLine(to: CGPoint(x: c + d, y: c - d))
            leg2.addLine(to: CGPoint(x: side + 60 * k, y: c - d))
            ctx.stroke(leg1, with: .color(leg), style: style)
            ctx.stroke(leg2, with: .color(accent), style: style)
            let ring = Path(ellipseIn: CGRect(x: c - R, y: c - R, width: 2 * R, height: 2 * R))
            if let background { ctx.fill(ring, with: .color(background)) }
            ctx.stroke(ring, with: .color(leg), lineWidth: s)
            let dr = R * 0.42
            ctx.fill(Path(ellipseIn: CGRect(x: c - dr, y: c - dr, width: 2 * dr, height: 2 * dr)), with: .color(accent))
        }
        .aspectRatio(1, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// Symbol + wordmark, used in About and on sign-in.
struct MasarLockup: View {
    var height: CGFloat = 44
    var body: some View {
        HStack(spacing: height * 0.3) {
            MasarSymbol().frame(width: height, height: height)
            MasarWordmark(color: .primary).frame(height: height * 0.95)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The trip in one line: origin dot → legs sized by riding time → interchange rings → arrival ring with gold dot.
/// Runs in reading direction (SwiftUI mirrors layouts), so it flows right-to-left in Arabic and Urdu.
struct RouteRibbon: View {
    @Environment(MetroNetwork.self) private var network
    let journey: Journey
    /// When the trip starts at the user's location: minutes of walking before the first station.
    var walkMinutes: Double? = nil

    var body: some View {
        var weights: [Double] = walkMinutes.map { [0, max($0, 1), 0] } ?? [0]
        for (i, leg) in journey.legs.enumerated() {
            weights.append(max(leg.minutes, 1))
            if i < journey.legs.count - 1 { weights.append(0) }
        }
        weights.append(0)

        return WeightedRow(weights: weights) {
            if let walkMinutes {
                Circle().fill(Brand.green).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2.5)).padding(.top, 4)
                VStack(alignment: .leading, spacing: 6) {
                    DashLine().stroke(Color.secondary, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
                        .frame(height: 8).padding(.top, 7)
                    HStack(spacing: 3) {
                        Image(systemName: "figure.walk").font(.caption2.weight(.bold))
                        Text(Int(walkMinutes.rounded()).formatted()).font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            Circle().fill(Color.primary).frame(width: 12, height: 12).padding(.top, 5)
            ForEach(Array(journey.legs.enumerated()), id: \.offset) { i, leg in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(network.lineByID[leg.line].map(Theme.lineColor) ?? .gray)
                        .frame(height: 8)
                        .padding(.top, 7)
                    HStack(spacing: 4) {
                        LineBadge(id: leg.line)
                        Text(Int(leg.minutes.rounded()).formatted())
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                .padding(.horizontal, 2)
                if i < journey.legs.count - 1 {
                    Circle().strokeBorder(Color.primary, lineWidth: 3.5)
                        .background(Circle().fill(Color(.systemBackground)))
                        .frame(width: 16, height: 16).padding(.top, 3)
                }
            }
            ZStack {
                Circle().strokeBorder(Color.primary, lineWidth: 4).background(Circle().fill(Color(.systemBackground)))
                Circle().fill(Brand.gold).frame(width: 9, height: 9)
            }
            .frame(width: 22, height: 22)
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.t("ribbon_label"))
        .accessibilityValue(((walkMinutes.map { [L10n.t("walk_info", ["m": L10n.minutes($0), "d": ""])] } ?? [])
            + journey.legs.map { "\(L10n.lineName($0.line)), \(L10n.minutes($0.minutes))" }).joined(separator: "; "))
    }
}

/// A horizontal centre line, used for the dotted walking segment.
struct DashLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX + 2, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX - 2, y: r.midY)); return p
    }
}

/// A row whose children with weight 0 keep their natural width and the rest share what is left by weight.
/// Children must be passed in the same order as `weights`.
struct WeightedRow: Layout {
    var weights: [Double]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let widths = allocate(width: width, subviews: subviews)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, w) in zip(subviews, allocate(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: nil))
            x += w
        }
    }

    private func allocate(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let w = subviews.indices.map { $0 < weights.count ? weights[$0] : 0 }
        let fixed = subviews.indices.filter { w[$0] == 0 }.reduce(CGFloat(0)) { $0 + subviews[$1].sizeThatFits(.unspecified).width }
        let total = w.reduce(0, +)
        let free = max(0, width - fixed)
        return subviews.indices.map { i in
            w[i] == 0 ? subviews[i].sizeThatFits(.unspecified).width : free * CGFloat(w[i] / max(total, 1))
        }
    }
}
