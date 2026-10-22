import Foundation
import MusicKit

/// Reads the "My Shazam Tracks" playlist that the Shazam app creates in the
/// user's Apple Music library when "Sync to Apple Music" is turned on.
@MainActor
struct AppleMusicShazamSource {
    enum SourceError: LocalizedError {
        case notAuthorized
        case playlistNotFound(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Apple Music access is off. Allow it in Settings \u{203A} Privacy \u{203A} Media & Apple Music."
            case .playlistNotFound(let name):
                return "No \u{201C}\(name)\u{201D} playlist in your Apple Music library. In the Shazam app, turn on Settings \u{203A} Apple Music sync."
            }
        }
    }

    var playlistName: String

    func fetchTracks() async throws -> [SourceTrack] {
        let status = await MusicAuthorization.request()
        guard status == .authorized else { throw SourceError.notAuthorized }

        guard let playlist = try await findPlaylist() else {
            throw SourceError.playlistNotFound(playlistName)
        }
        let detailed = try await playlist.with([.tracks])
        guard var batch = detailed.tracks else { return [] }

        var tracks = Array(batch)
        while batch.hasNextBatch, let next = try await batch.nextBatch() {
            tracks.append(contentsOf: next)
            batch = next
        }

        return tracks.map { track in
            var added: Date? = nil
            if case .song(let song) = track { added = song.libraryAddedDate }
            return SourceTrack(
                title: track.title,
                artist: track.artistName,
                album: track.albumTitle,
                isrc: track.isrc,
                durationMs: track.duration.map { Int($0 * 1000) },
                shazamedAt: added,
                source: .appleMusicShazamPlaylist
            )
        }
    }

    private func findPlaylist() async throws -> Playlist? {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 100
        var batch = try await request.response().items
        let target = playlistName.trimmingCharacters(in: .whitespaces)
        while true {
            if let match = batch.first(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame }) {
                return match
            }
            guard batch.hasNextBatch, let next = try await batch.nextBatch() else { return nil }
            batch = next
        }
    }
}
