import Foundation

enum AppTab: Hashable { case sync, review, settings }

/// Owns the app's shared services.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let store: AppStore
    let auth: SpotifyAuth
    let api: SpotifyAPI
    let notifications: NotificationManager
    let engine: SyncEngine
    let recognizer: ShazamRecognizer

    var selectedTab: AppTab = .sync

    private init() {
        store = AppStore()
        auth = SpotifyAuth()
        api = SpotifyAPI(auth: auth)
        notifications = NotificationManager()
        engine = SyncEngine(store: store, auth: auth, api: api, notifications: notifications)
        recognizer = ShazamRecognizer()
    }
}
