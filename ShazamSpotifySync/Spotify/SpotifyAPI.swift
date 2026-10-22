import Foundation

/// Thin client for the Spotify Web API endpoints this app needs.
@MainActor
final class SpotifyAPI: SpotifySearching {
    private let auth: SpotifyAuth
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Spotify renamed playlist ".../tracks" endpoints to ".../items".
    /// Try the new name first and fall back if this account still needs the old one.
    private var playlistSegment = "items"

    init(auth: SpotifyAuth, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: Endpoints

    func currentUser() async throws -> SpotifyUser {
        let dto: UserDTO = try await get("me")
        return SpotifyUser(id: dto.id, displayName: dto.displayName)
    }

    /// Playlists the user can add songs to (owned or collaborative).
    func editablePlaylists() async throws -> [SpotifyPlaylist] {
        let me = try await currentUser()
        var result: [SpotifyPlaylist] = []
        var page: PagingDTO<PlaylistDTO> = try await get("me/playlists", query: ["limit": "50"])
        while true {
            result += page.items.map(\.model).filter { $0.ownerID == me.id || $0.collaborative }
            guard let next = page.next, let url = URL(string: next) else { break }
            page = try await send("GET", url: url)
        }
        return result
    }

    func createPlaylist(named name: String) async throws -> SpotifyPlaylist {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "public": false,
            "description": "Songs from my Shazam library, synced by ShazSync.",
        ])
        do {
            let dto: PlaylistDTO = try await send("POST", url: url("me/playlists"), body: body)
            return dto.model
        } catch SpotifyError.http(let status, _) where status == 404 || status == 405 {
            let me = try await currentUser()
            let dto: PlaylistDTO = try await send("POST", url: url("users/\(me.id)/playlists"), body: body)
            return dto.model
        }
    }

    func searchTracks(query: String, limit: Int) async throws -> [SpotifyTrack] {
        let response: SearchResponseDTO = try await get("search", query: [
            "q": query,
            "type": "track",
            "limit": String(min(limit, 10)),
        ])
        return response.tracks.items.compactMap(\.model)
    }

    /// Every track currently in a playlist (to avoid adding duplicates).
    func playlistTracks(_ playlistID: String) async throws -> [SpotifyTrack] {
        try await withPlaylistSegment { segment in
            var result: [SpotifyTrack] = []
            var page: PagingDTO<PlaylistItemDTO> = try await self.get(
                "playlists/\(playlistID)/\(segment)", query: ["limit": "100"]
            )
            while true {
                result += page.items.compactMap { $0.track?.model }
                guard let next = page.next, let url = URL(string: next) else { break }
                page = try await self.send("GET", url: url)
            }
            return result
        }
    }

    func addTracks(uris: [String], to playlistID: String) async throws {
        guard !uris.isEmpty else { return }
        for start in stride(from: 0, to: uris.count, by: 100) {
            let chunk = Array(uris[start..<min(start + 100, uris.count)])
            let body = try JSONSerialization.data(withJSONObject: ["uris": chunk])
            _ = try await withPlaylistSegment { segment -> SnapshotDTO in
                try await self.send("POST", url: self.url("playlists/\(playlistID)/\(segment)"), body: body)
            }
        }
    }

    // MARK: Plumbing

    private func withPlaylistSegment<T>(_ operation: (String) async throws -> T) async throws -> T {
        do {
            return try await operation(playlistSegment)
        } catch SpotifyError.http(let status, _) where status == 404 || status == 410 {
            let other = playlistSegment == "items" ? "tracks" : "items"
            let result = try await operation(other)
            playlistSegment = other
            return result
        }
    }

    private func url(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: SpotifyConfig.apiBase.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await send("GET", url: url(path, query: query))
    }

    private func send<T: Decodable>(_ method: String, url: URL, body: Data? = nil, attempt: Int = 0) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let token = try await auth.accessToken(forceRefresh: attempt > 0 && attempt < 2)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        switch status {
        case 200..<300:
            return try decoder.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        case 401 where attempt == 0:
            // Token expired early or was revoked; refresh and retry once.
            return try await send(method, url: url, body: body, attempt: 1)
        case 429:
            guard attempt < 4 else { throw SpotifyError.rateLimited }
            let wait = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
            try await Task.sleep(for: .seconds(min(max(wait, 1), 30)))
            return try await send(method, url: url, body: body, attempt: max(attempt, 2) + 1)
        case 500..<600 where attempt < 2:
            try await Task.sleep(for: .seconds(1))
            return try await send(method, url: url, body: body, attempt: 2)
        default:
            let message = (try? decoder.decode(ErrorEnvelopeDTO.self, from: data).error.message)
                ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw SpotifyError.http(status: status, message: message)
        }
    }
}
