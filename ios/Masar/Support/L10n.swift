import Foundation

/// Strings come from Localizable.xcstrings, generated from data/strings.json.
/// Named placeholders like {line} are substituted here; plurals use the catalog's plural variations.
enum L10n {
    static func t(_ key: String, _ vars: [String: String] = [:]) -> String {
        var s = NSLocalizedString(key, comment: "")
        for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    static func plural(_ key: String, _ n: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString(key, comment: ""), n)
    }

    static func minutes(_ m: Double) -> String { plural("p_min", max(1, Int(m.rounded()))) }
    static func stops(_ n: Int) -> String { plural("p_stop", n) }
    static func stations(_ n: Int) -> String { plural("p_station", n) }
    static func transfers(_ n: Int) -> String { n == 0 ? t("no_xfer") : plural("p_xfer", n) }
    static func lineName(_ id: Int) -> String { t("line_\(id)") }

    static func price(_ value: Double) -> String {
        let n = value.formatted(.number.precision(.fractionLength(0...2)))
        return t("sar", ["p": n])
    }

    /// Station signage is Arabic + English; every non-Arabic UI shows the English name.
    static var arabicUI: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("ar") == true }
    static func stationName(_ s: Station) -> String { arabicUI ? s.ar : s.en }
    static func secondaryName(_ s: Station) -> String { arabicUI ? s.en : s.ar }
}
