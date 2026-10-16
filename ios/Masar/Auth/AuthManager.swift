import Foundation
import Observation
import AuthenticationServices
import Security

/// Sign in with Apple. The Apple user id is kept in the Keychain; the person's records
/// sync through their own iCloud (CloudKit private database), so no password or server is needed.
///
/// If you later add your own backend: send `identityToken` to it, create the account there,
/// and on account deletion call Apple's token revocation endpoint (App Store Review Guideline 5.1.1(v)).
@Observable
final class AuthManager {
    private(set) var userID: String?
    private(set) var displayName: String?
    var isSignedIn: Bool { userID != nil }

    private let userKey = "apple.userID"
    private let nameKey = "apple.displayName"

    init() {
        userID = Keychain.read(userKey)
        displayName = UserDefaults.standard.string(forKey: nameKey)
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        userID = cred.user
        Keychain.save(cred.user, for: userKey)
        // Apple only sends the name on the first sign-in, so keep it.
        if let parts = cred.fullName {
            let name = PersonNameComponentsFormatter().string(from: parts)
            if !name.isEmpty {
                displayName = name
                UserDefaults.standard.set(name, forKey: nameKey)
            }
        }
    }

    @MainActor
    func refreshCredentialState() async {
        guard let id = userID else { return }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: id)
            if state == .revoked || state == .notFound { signOut() }
        } catch {
            // Offline: keep the current session.
        }
    }

    func signOut() {
        userID = nil
        displayName = nil
        Keychain.delete(userKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }
}

enum Keychain {
    private static let service = "sa.masar.app"

    static func save(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
