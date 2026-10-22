import Foundation

/// Collects Shazam songs, finds them on Spotify, adds confident matches to
/// the chosen playlist and keeps the rest for review.
@MainActor
@Observable
final class SyncEngine {
    enum Phase: Equatable {
        case idle
        case collecting
        case matching(done: Int, total: Int)
        case adding(count: Int)
        case finished
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .collecting, .matching, .adding: return true
            default: return false
            }
        }
    }

    enum Trigger { case manual, background }

    private(set) var phase: Phase = .idle

    private let store: AppStore
    private let auth: SpotifyAuth
    private let api: SpotifyAPI
    private let notifications: NotificationManager

    init(store: AppStore, auth: SpotifyAuth, api: SpotifyAPI, notifications: NotificationManager) {
        self.store = store
        self.auth = auth
        self.api = api
        self.notifications = notifications
    }

    @discardableResult
    func sync(trigger: Trigger = .manual) async -> SyncReport? {
        guard !phase.isRunning else { return nil }
        guard auth.isSignedIn else { phase = .failed(SpotifyError.notSignedIn.localizedDescription); return nil }
        guard let playlist = store.selectedPlaylist else {
            phase = .failed("Choose a Spotify playlist first.")
            return nil
        }

        do {
            phase = .collecting
            var warnings: [String] = []
            let all = await collectSourceTracks(warnings: &warnings)

            let handled = store.handledIDs(for: playlist.id)
            let waiting = Set(store.unmatched.map(\.id))
            let pending = all.filter { !handled.contains($0.id) && !waiting.contains($0.id) }

            var added: [SourceTrack] = []
            var alreadyPresent: [SourceTrack] = []
            var newUnmatched: [UnmatchedTrack] = []

            if !pending.isEmpty {
                let existing = try await api.playlistTracks(playlist.id)
                var existingURIs = Set(existing.map(\.uri))
                let existingISRCs = Set(existing.compactMap(\.isrc))
                let existingKeys = Set(existing.map { SourceTrack.stableID(title: $0.name, artist: $0.artistLine) })

                let resolver = TrackResolver(search: api)
                var urisToAdd: [String] = []

                for (index, track) in pending.enumerated() {
                    try Task.checkCancellation()
                    phase = .matching(done: index, total: pending.count)

                    if (track.isrc.map(existingISRCs.contains) ?? false) || existingKeys.contains(track.id) {
                        alreadyPresent.append(track)
                        continue
                    }

                    switch try await resolver.resolve(track) {
                    case .matched(let best):
                        if existingURIs.contains(best.track.uri) {
                            alreadyPresent.append(track)
                        } else {
                            existingURIs.insert(best.track.uri)
                            urisToAdd.append(best.track.uri)
                            added.append(track)
                        }
                    case .needsReview(let alternatives):
                        newUnmatched.append(UnmatchedTrack(source: track, alternatives: alternatives,
                                                           reason: .lowConfidence, lastAttempt: Date()))
                    case .notFound:
                        newUnmatched.append(UnmatchedTrack(source: track, alternatives: [],
                                                           reason: .notFound, lastAttempt: Date()))
                    }
                }

                phase = .adding(count: urisToAdd.count)
                try await api.addTracks(uris: urisToAdd, to: playlist.id)
            }

            store.markHandled((added + alreadyPresent).map(\.id), playlistID: playlist.id)
            store.unmatched = store.unmatched + newUnmatched

            let report = SyncReport(date: Date(), scanned: all.count, added: added.count,
                                    alreadyInPlaylist: alreadyPresent.count,
                                    unmatched: newUnmatched.count, warnings: warnings)
            store.lastReport = report
            phase = .finished

            await notifications.postSyncSummary(report: report, newUnmatched: newUnmatched,
                                                playlistName: playlist.name, trigger: trigger)
            return report
        } catch is CancellationError {
            phase = .idle
            return nil
        } catch {
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Look for new alternatives for songs on the review list.
    func retryUnmatched() async {
        guard !phase.isRunning, store.selectedPlaylist != nil else { return }
        let items = store.unmatched
        let resolver = TrackResolver(search: api)
        var stillUnmatched: [UnmatchedTrack] = []
        var matched: [(SourceTrack, String)] = []
        do {
            for (index, item) in items.enumerated() {
                phase = .matching(done: index, total: items.count)
                switch try await resolver.resolve(item.source) {
                case .matched(let best):
                    matched.append((item.source, best.track.uri))
                case .needsReview(let alternatives):
                    stillUnmatched.append(UnmatchedTrack(source: item.source, alternatives: alternatives,
                                                         reason: .lowConfidence, lastAttempt: Date()))
                case .notFound:
                    stillUnmatched.append(UnmatchedTrack(source: item.source, alternatives: [],
                                                         reason: .notFound, lastAttempt: Date()))
                }
            }
            guard let playlist = store.selectedPlaylist else { return }
            phase = .adding(count: matched.count)
            try await api.addTracks(uris: matched.map { $0.1 }, to: playlist.id)
            store.unmatched = stillUnmatched
            store.markHandled(matched.map { $0.0.id }, playlistID: playlist.id)
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Add a suggested alternative (or a manual search result) for a song.
    func accept(_ track: SpotifyTrack, for item: UnmatchedTrack) async throws {
        guard let playlist = store.selectedPlaylist else { return }
        try await api.addTracks(uris: [track.uri], to: playlist.id)
        store.markHandled([item.id], playlistID: playlist.id)
    }

    /// Stop suggesting a song without adding anything.
    func dismiss(_ item: UnmatchedTrack) {
        guard let playlist = store.selectedPlaylist else { return }
        store.markHandled([item.id], playlistID: playlist.id)
    }

    private func collectSourceTracks(warnings: inout [String]) async -> [SourceTrack] {
        var tracks: [SourceTrack] = []
        let enabled = store.enabledSources

        if enabled.contains(.appleMusicShazamPlaylist) {
            do {
                tracks += try await AppleMusicShazamSource(playlistName: store.appleMusicPlaylistName).fetchTracks()
            } catch {
                warnings.append(error.localizedDescription)
            }
        }
        if enabled.contains(.shazamKitLibrary) {
            do {
                tracks += try await ShazamKitLibrarySource().fetchTracks()
            } catch {
                warnings.append("Shazam library: \(error.localizedDescription)")
            }
        }
        if enabled.contains(.csvImport) {
            tracks += store.importedCSVTracks
        }

        // Same song from several sources: keep the copy with the most detail.
        var byID: [String: SourceTrack] = [:]
        var order: [String] = []
        for track in tracks {
            if let existing = byID[track.id] {
                if existing.isrc == nil && track.isrc != nil { byID[track.id] = track }
            } else {
                byID[track.id] = track
                order.append(track.id)
            }
        }
        // Oldest Shazams first, so the playlist reads in the order songs were found.
        return order.compactMap { byID[$0] }.sorted {
            ($0.shazamedAt ?? .distantPast) < ($1.shazamedAt ?? .distantPast)
        }
    }
}
