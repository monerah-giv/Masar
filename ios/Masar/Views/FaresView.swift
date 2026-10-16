import SwiftUI

struct FaresView: View {
    @Environment(FareBook.self) private var fares
    @AppStorage("fare.class") private var fareClassRaw = FareClass.standard.rawValue
    @AppStorage("fare.discount") private var discount = false
    @AppStorage("fare.tripsPerWeek") private var tripsPerWeek = 10

    private var fareClass: FareClass { FareClass(rawValue: fareClassRaw) ?? .standard }

    var body: some View {
        let options = fares.monthlyOptions(tripsPerWeek: tripsPerWeek, fareClass: fareClass, discountEligible: discount)
        let cheapest = options.map(\.monthly).min() ?? 0
        let dearest = options.map(\.monthly).max() ?? 1

        Form {
            if let p = fares.price("t_2h", fareClass: fareClass, discountEligible: discount) {
                Section {
                    TicketCard(price: p)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                Picker(L10n.t("default_class"), selection: $fareClassRaw) {
                    Text(L10n.t("class_std")).tag(FareClass.standard.rawValue)
                    Text(L10n.t("class_first")).tag(FareClass.first.rawValue)
                }
                .pickerStyle(.segmented)
                ForEach(fares.file.tickets) { t in
                    if let p = fares.price(t.id, fareClass: fareClass, discountEligible: discount) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t(t.id)).font(.headline)
                                Text(L10n.t("unlimited")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                if p.discounted {
                                    Text(L10n.price(p.base)).font(.caption).strikethrough().foregroundStyle(.secondary)
                                }
                                Text(L10n.price(p.now)).font(.headline.monospacedDigit())
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if let url = fares.darbURL {
                    Link(destination: url) { Label(L10n.t("buy"), systemImage: "arrow.up.forward.app") }
                }
            } header: {
                Text(L10n.t("fares_title"))
            } footer: {
                Text("\(L10n.t("price_note")) \(L10n.t("kids_free"))")
            }

            Section {
                Toggle(L10n.t("eligible"), isOn: $discount)
            } header: {
                Text(L10n.t("discount_title"))
            } footer: {
                Text(discount ? "\(L10n.t("discount_body")) \(L10n.t("disc_note"))" : L10n.t("discount_body"))
            }

            Section {
                Stepper(value: $tripsPerWeek, in: 1...30) {
                    LabeledContent(L10n.t("trips_week"), value: tripsPerWeek.formatted())
                }
                ForEach(options) { o in
                    let best = o.monthly == cheapest
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.t(o.id)).font(.subheadline.weight(.semibold))
                            if best {
                                Text(L10n.t("best")).font(.caption.weight(.bold))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer()
                            Text(L10n.t("per_month", ["p": L10n.price(o.monthly.rounded())])).font(.subheadline.monospacedDigit())
                        }
                        ProgressView(value: o.monthly, total: max(dearest, 1))
                            .tint(best ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(L10n.t("advisor"))
            }
        }
        .navigationTitle(L10n.t("tab_fares"))
    }
}

/// The everyday 2-hour ticket as a gold ticket stub: perforation and side notches.
struct TicketCard: View {
    let price: TicketPrice
    private let ink = Color(red: 0.11, green: 0.08, blue: 0.0)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("most_used")).font(.caption.weight(.bold)).textCase(.uppercase).opacity(0.75)
                Text(L10n.t("t_2h")).font(.system(.title, design: .rounded).weight(.heavy))
                Text(L10n.t("unlimited")).font(.footnote).opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            VStack(spacing: 4) {   // perforation with half-circle notches cut by the clip below
                Circle().fill(Color(.systemGroupedBackground)).frame(width: 20, height: 20).offset(y: -12)
                Line().stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 5])).frame(width: 2).opacity(0.45)
                Circle().fill(Color(.systemGroupedBackground)).frame(width: 20, height: 20).offset(y: 12)
            }
            .frame(width: 20)
            VStack(spacing: 0) {
                if price.discounted {
                    Text(L10n.price(price.base)).font(.caption).strikethrough().opacity(0.7)
                }
                Text(L10n.price(price.now)).font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit()
            }
            .padding(18)
        }
        .foregroundStyle(ink)
        .background(Brand.gold)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); return p }
    }
}
