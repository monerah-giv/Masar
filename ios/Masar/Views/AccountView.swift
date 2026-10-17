import SwiftUI
import UIKit
import SwiftData
import AuthenticationServices

struct AccountView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FareBook.self) private var fares
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(AdsService.self) private var ads
    @AppStorage("fare.class") private var fareClassRaw = FareClass.standard.rawValue
    @State private var confirmDelete = false

    /// Published from tools/pages.py with the website.
    private let privacyURL = URL(string: "https://monerah-giv.github.io/Masar/privacy/")!
    private let termsURL = URL(string: "https://monerah-giv.github.io/Masar/terms/")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    if auth.isSignedIn {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Brand.green)
                    } else {
                        MasarSymbol().frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.isSignedIn
                             ? (auth.displayName.map { L10n.t("signed_in_as", ["name": $0]) } ?? L10n.t("signed_in"))
                             : L10n.t("guest"))
                            .font(.headline)
                        Text(auth.isSignedIn ? L10n.t("synced_body") : L10n.t("guest_body"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if !auth.isSignedIn {
                    SignInWithAppleButton(.signIn, onRequest: auth.configure, onCompletion: auth.handle)
                        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                        .frame(height: 50)
                }
            }

            Section(L10n.t("settings")) {
                // iOS offers a per-app language in Settings for every localization the app ships.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    LabeledContent(L10n.t("language"), value: Locale.current.localizedString(forIdentifier: Bundle.main.preferredLocalizations.first ?? "en") ?? "")
                }
                Picker(L10n.t("default_class"), selection: $fareClassRaw) {
                    Text(L10n.t("class_std")).tag(FareClass.standard.rawValue)
                    Text(L10n.t("class_first")).tag(FareClass.first.rawValue)
                }
            }

            Section(L10n.t("hours")) {
                ServiceStatusBadge()
                Text(L10n.t("hours_body")).font(.footnote)
            }

            if let url = ads.advertiseURL(station: nil) {
                Section(L10n.t("adv_open")) {
                    Text(L10n.t("adv_sub")).font(.footnote)
                    Button { openURL(url) } label: { Label(L10n.t("adv_title"), systemImage: "megaphone") }
                }
            }

            Section(L10n.t("about")) {
                MasarLockup(height: 40).padding(.vertical, 6)
                Text(L10n.t("about_body")).font(.footnote)
                Link(L10n.t("privacy"), destination: privacyURL)
                Link(L10n.t("terms"), destination: termsURL)
            }

            if auth.isSignedIn {
                Section {
                    Button(L10n.t("sign_out")) { auth.signOut() }
                    Button(L10n.t("delete_data"), role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(L10n.t("tab_account"))
        .confirmationDialog(L10n.t("delete_data"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.t("delete"), role: .destructive) { deleteEverything() }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("delete_confirm"))
        }
    }

    private func deleteEverything() {
        // Delete record by record so the deletions also sync to iCloud.
        (try? context.fetch(FetchDescriptor<FavoritePlace>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<SavedRoute>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<TripRecord>()))?.forEach { context.delete($0) }
        try? context.save()
        auth.signOut()
    }
}
