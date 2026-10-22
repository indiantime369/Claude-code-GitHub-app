import AuthenticationServices
import Foundation
import UIKit

struct SpotifyToken: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var isExpired: Bool { expiresAt.addingTimeInterval(-60) < Date() }
}

/// Spotify sign-in using Authorization Code with PKCE (no client secret in the app).
@MainActor
@Observable
final class SpotifyAuth {
    private static let keychainKey = "spotify.token"

    private(set) var isSignedIn = false
    private var token: SpotifyToken?
    private var refreshTask: Task<SpotifyToken, Error>?
    private var webSession: ASWebAuthenticationSession?
    private let anchorProvider = PresentationAnchorProvider()

    init() {
        if let data = Keychain.load(Self.keychainKey),
           let saved = try? JSONDecoder().decode(SpotifyToken.self, from: data) {
            token = saved
            isSignedIn = true
        }
    }

    func signIn() async throws {
        guard SpotifyConfig.isConfigured else { throw SpotifyError.notConfigured }

        let verifier = PKCE.makeVerifier()
        let state = UUID().uuidString
        var components = URLComponents(url: SpotifyConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes.joined(separator: " ")),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: SpotifyConfig.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyError.authCancelled)
                } else {
                    continuation.resume(throwing: SpotifyError.authFailed(error?.localizedDescription ?? "Unknown error"))
                }
            }
            session.presentationContextProvider = anchorProvider
            webSession = session
            if !session.start() {
                continuation.resume(throwing: SpotifyError.authFailed("Couldn't open the sign-in page."))
            }
        }
        webSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw error == "access_denied" ? SpotifyError.authCancelled : SpotifyError.authFailed(error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyError.authFailed("Invalid response from Spotify.")
        }

        let newToken = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier,
        ], previousRefreshToken: nil)
        store(newToken)
    }

    func signOut() {
        token = nil
        refreshTask?.cancel()
        refreshTask = nil
        Keychain.delete(Self.keychainKey)
        isSignedIn = false
    }

    /// A valid access token, refreshed if needed.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = token else { throw SpotifyError.notSignedIn }
        if !forceRefresh && !current.isExpired { return current.accessToken }

        if let refreshTask { return try await refreshTask.value.accessToken }

        let task = Task { () throws -> SpotifyToken in
            try await self.requestToken([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": SpotifyConfig.clientID,
            ], previousRefreshToken: current.refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let refreshed = try await task.value
            store(refreshed)
            return refreshed.accessToken
        } catch SpotifyError.http(let status, _) where status == 400 || status == 401 {
            // Refresh token revoked or expired: the user must sign in again.
            signOut()
            throw SpotifyError.notSignedIn
        }
    }

    private func store(_ newToken: SpotifyToken) {
        token = newToken
        if let data = try? JSONEncoder().encode(newToken) {
            Keychain.save(data, for: Self.keychainKey)
        }
        isSignedIn = true
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    private func requestToken(_ form: [String: String], previousRefreshToken: String?) async throws -> SpotifyToken {
        var request = URLRequest(url: SpotifyConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" unescaped, which form decoding reads as a space.
        request.httpBody = body.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Token request failed"
            throw SpotifyError.http(status: status, message: message)
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = decoded.refresh_token ?? previousRefreshToken else {
            throw SpotifyError.authFailed("Spotify did not return a refresh token.")
        }
        return SpotifyToken(
            accessToken: decoded.access_token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }
}

private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first {
                return window
            }
            return ASPresentationAnchor()
        }
    }
}
