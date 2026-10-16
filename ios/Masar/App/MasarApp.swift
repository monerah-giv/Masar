import SwiftUI
import SwiftData

@main
struct MasarApp: App {
    @State private var network = MetroNetwork.load()
    @State private var fares = FareBook.load()
    @State private var auth = AuthManager()
    @State private var router = AppRouter()
    @State private var location = LocationService()
    @State private var ads = AdsService()

    /// User records (places, saved routes, trip history) live in SwiftData.
    /// With iCloud signed in they sync through the user's private CloudKit database,
    /// so they follow the person to every device without a server of our own.
    private let container: ModelContainer = {
        let schema = Schema([FavoritePlace.self, SavedRoute.self, TripRecord.self])
        do {
            let synced = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: synced)
        } catch {
            do {
                let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: local)
            } catch {
                fatalError("Could not open the local store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(network)
                .environment(fares)
                .environment(auth)
                .environment(router)
                .environment(location)
                .environment(ads)
                .task { await auth.refreshCredentialState() }
                .task { await ads.refresh() }
        }
        .modelContainer(container)
    }
}
