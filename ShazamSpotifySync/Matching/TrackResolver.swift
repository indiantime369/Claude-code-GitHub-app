import Foundation

@MainActor
protocol SpotifySearching: AnyObject {
    func searchTracks(query: String, limit: Int) async throws -> [SpotifyTrack]
}

/// Runs a series of increasingly loose Spotify searches for one Shazam song.
@MainActor
final class TrackResolver {
    private let search: SpotifySearching
    private let matcher: TrackMatcher
    private let limit = 10

    init(search: SpotifySearching, matcher: TrackMatcher = TrackMatcher()) {
        self.search = search
        self.matcher = matcher
    }

    func resolve(_ track: SourceTrack) async throws -> MatchOutcome {
        var candidates: [SpotifyTrack] = []

        for query in Self.queries(for: track) {
            try Task.checkCancellation()
            candidates += try await search.searchTracks(query: query, limit: limit)
            if case .matched(let best) = matcher.evaluate(track, candidates: candidates) {
                return .matched(best)
            }
        }
        return matcher.evaluate(track, candidates: candidates)
    }

    /// Exact ISRC first, then field search, then free text.
    static func queries(for track: SourceTrack) -> [String] {
        let title = TextNormalizer.queryText(stripDecorations(track.title))
        let artist = TextNormalizer.queryText(primaryArtistDisplay(track.artist))

        var queries: [String] = []
        if let isrc = track.isrc { queries.append("isrc:\(isrc)") }
        if !artist.isEmpty {
            queries.append("track:\"\(title)\" artist:\"\(artist)\"")
            queries.append("\(title) \(artist)")
        } else {
            queries.append("track:\"\(title)\"")
        }
        return queries
    }

    /// Title without bracketed parts or " - Remastered" style suffixes, but
    /// keeping the original casing and accents for better search results.
    static func stripDecorations(_ title: String) -> String {
        var s = title.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+[-\u{2013}\u{2014}]\\s+.*$", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? title : s
    }

    /// First credited artist, keeping original casing.
    static func primaryArtistDisplay(_ artist: String) -> String {
        let pattern = "\\s*(,|&|;|/|\\+|\\bfeat\\.?|\\bft\\.?|\\bfeaturing\\b|\\bwith\\b|\\bx\\b|\\bvs\\.?)\\s*"
        let first = artist
            .replacingOccurrences(of: pattern, with: "|", options: [.regularExpression, .caseInsensitive])
            .split(separator: "|")
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        return (first?.isEmpty ?? true) ? artist : first!
    }
}
