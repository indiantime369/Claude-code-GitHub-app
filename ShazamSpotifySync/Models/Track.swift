import Foundation

/// Where a Shazam song came from.
enum TrackSource: String, Codable, CaseIterable, Identifiable, Hashable {
    /// The "My Shazam Tracks" playlist the Shazam app keeps in Apple Music.
    case appleMusicShazamPlaylist
    /// Songs identified inside this app (stored in the ShazamKit library).
    case shazamKitLibrary
    /// A CSV export of the Shazam library.
    case csvImport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusicShazamPlaylist: return "Apple Music \u{201C}My Shazam Tracks\u{201D}"
        case .shazamKitLibrary: return "Songs identified in this app"
        case .csvImport: return "Imported Shazam CSV"
        }
    }

    var systemImage: String {
        switch self {
        case .appleMusicShazamPlaylist: return "music.note.list"
        case .shazamKitLibrary: return "shazam.logo"
        case .csvImport: return "doc.text"
        }
    }
}

/// A song from the user's Shazam library.
struct SourceTrack: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var artist: String
    var album: String?
    var isrc: String?
    var durationMs: Int?
    var shazamedAt: Date?
    var source: TrackSource

    init(title: String, artist: String, album: String? = nil, isrc: String? = nil,
         durationMs: Int? = nil, shazamedAt: Date? = nil, source: TrackSource) {
        let cleanISRC = isrc?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album
        self.isrc = (cleanISRC?.isEmpty ?? true) ? nil : cleanISRC
        self.durationMs = durationMs
        self.shazamedAt = shazamedAt
        self.source = source
        self.id = SourceTrack.stableID(title: self.title, artist: self.artist)
    }

    /// Same song from different sources gets the same ID, so it is synced once.
    static func stableID(title: String, artist: String) -> String {
        TextNormalizer.coreTitle(title) + "|" + TextNormalizer.primaryArtist(artist)
    }
}

/// A track in the Spotify catalog.
struct SpotifyTrack: Codable, Hashable, Identifiable {
    let id: String
    let uri: String
    let name: String
    let artists: [String]
    let album: String
    let durationMs: Int
    let isrc: String?
    let imageURL: URL?
    let externalURL: URL?

    var artistLine: String { artists.joined(separator: ", ") }
}

struct SpotifyPlaylist: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let ownerID: String
    let ownerName: String
    let imageURL: URL?
    let trackCount: Int?
    let collaborative: Bool
}

struct SpotifyUser: Codable, Hashable {
    let id: String
    let displayName: String?
}

/// A Spotify search result with a 0...1 confidence score.
struct ScoredCandidate: Codable, Hashable, Identifiable {
    var track: SpotifyTrack
    var score: Double
    var id: String { track.id }
}

enum MatchOutcome: Equatable {
    case matched(ScoredCandidate)
    case needsReview([ScoredCandidate])
    case notFound
}

/// A Shazam song we could not confidently sync, with suggested alternatives.
struct UnmatchedTrack: Codable, Hashable, Identifiable {
    enum Reason: String, Codable {
        /// Spotify had similar songs but none was a confident match.
        case lowConfidence
        /// Spotify returned nothing usable.
        case notFound
    }

    var source: SourceTrack
    var alternatives: [ScoredCandidate]
    var reason: Reason
    var lastAttempt: Date

    var id: String { source.id }
}

struct SyncReport: Codable, Hashable {
    var date: Date
    var scanned: Int
    var added: Int
    var alreadyInPlaylist: Int
    var unmatched: Int
    var warnings: [String]
}
