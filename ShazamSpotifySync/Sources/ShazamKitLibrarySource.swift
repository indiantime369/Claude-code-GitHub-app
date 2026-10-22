import Foundation
import ShazamKit

/// Songs in the ShazamKit library. Apple only lets an app read the items it
/// added itself, so this holds the songs identified with this app's
/// Identify button (they also show up in the user's Shazam library).
@MainActor
struct ShazamKitLibrarySource {
    func fetchTracks() async throws -> [SourceTrack] {
        SHLibrary.default.items.compactMap { item in
            guard let title = item.title, let artist = item.artist else { return nil }
            return SourceTrack(
                title: title,
                artist: artist,
                isrc: item.isrc,
                shazamedAt: item.creationDate,
                source: .shazamKitLibrary
            )
        }
    }
}

/// Identifies the song playing nearby and saves it to the Shazam library.
@MainActor
@Observable
final class ShazamRecognizer {
    enum State: Equatable {
        case idle
        case listening
        case matched(title: String, artist: String)
        case noMatch
        case failed(String)
    }

    private(set) var state: State = .idle
    private var session: SHManagedSession?

    func identify() async {
        let session = SHManagedSession()
        self.session = session
        state = .listening
        let result = await session.result()
        self.session = nil

        switch result {
        case .match(let match):
            guard let item = match.mediaItems.first else { state = .noMatch; return }
            do {
                try await SHLibrary.default.addItems([item])
                state = .matched(title: item.title ?? "Unknown", artist: item.artist ?? "")
            } catch {
                state = .failed(error.localizedDescription)
            }
        case .noMatch:
            state = .noMatch
        case .error(let error, _):
            state = .failed(error.localizedDescription)
        @unknown default:
            state = .noMatch
        }
    }

    func cancel() {
        session?.cancel()
        session = nil
        state = .idle
    }

    func reset() { state = .idle }
}
