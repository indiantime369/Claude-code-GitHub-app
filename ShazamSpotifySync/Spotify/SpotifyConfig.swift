import Foundation

enum SpotifyConfig {
    /// Set SPOTIFY_CLIENT_ID in Config/Secrets.xcconfig.
    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String) ?? ""
    }

    static var isConfigured: Bool {
        let id = clientID
        return !id.isEmpty && !id.hasPrefix("REPLACE_") && !id.hasPrefix("your_") && !id.hasPrefix("$(")
    }

    /// Must also be added to your app in the Spotify developer dashboard.
    static let callbackScheme = "shazamspotifysync"
    static let redirectURI = "shazamspotifysync://callback"

    static let scopes = [
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-public",
        "playlist-modify-private",
    ]

    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let apiBase = URL(string: "https://api.spotify.com/v1/")!
}

enum SpotifyError: LocalizedError {
    case notConfigured
    case notSignedIn
    case authCancelled
    case authFailed(String)
    case http(status: Int, message: String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your Spotify client ID to Config/Secrets.xcconfig and rebuild."
        case .notSignedIn: return "Sign in to Spotify first."
        case .authCancelled: return "Spotify sign-in was cancelled."
        case .authFailed(let m): return "Spotify sign-in failed: \(m)"
        case .http(let status, let message): return "Spotify error \(status): \(message)"
        case .rateLimited: return "Spotify is rate limiting requests. Try again in a few minutes."
        }
    }
}
