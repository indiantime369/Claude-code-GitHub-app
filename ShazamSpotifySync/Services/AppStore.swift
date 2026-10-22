import Foundation

/// App state saved between launches (a JSON file in Application Support).
@MainActor
@Observable
final class AppStore {
    struct Snapshot: Codable {
        var selectedPlaylist: SpotifyPlaylist?
        var enabledSources: Set<TrackSource> = [.appleMusicShazamPlaylist, .shazamKitLibrary, .csvImport]
        var appleMusicPlaylistName = "My Shazam Tracks"
        var importedCSVTracks: [SourceTrack] = []
        /// Song IDs already handled (added, already present, or dismissed), per playlist.
        var handledIDs: [String: Set<String>] = [:]
        var unmatched: [UnmatchedTrack] = []
        var lastReport: SyncReport?
        var autoSyncEnabled = true
    }

    private(set) var snapshot: Snapshot
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let url = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShazSync", isDirectory: true)
            .appendingPathComponent("state.json")
        self.fileURL = url
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        } else {
            snapshot = Snapshot()
        }
    }

    // MARK: Accessors

    var selectedPlaylist: SpotifyPlaylist? {
        get { snapshot.selectedPlaylist }
        set {
            // Unresolved songs belong to the old playlist; start fresh.
            if newValue?.id != snapshot.selectedPlaylist?.id { snapshot.unmatched = [] }
            snapshot.selectedPlaylist = newValue
            save()
        }
    }

    var enabledSources: Set<TrackSource> {
        get { snapshot.enabledSources }
        set { snapshot.enabledSources = newValue; save() }
    }

    var appleMusicPlaylistName: String {
        get { snapshot.appleMusicPlaylistName }
        set { snapshot.appleMusicPlaylistName = newValue; save() }
    }

    var importedCSVTracks: [SourceTrack] {
        get { snapshot.importedCSVTracks }
        set { snapshot.importedCSVTracks = newValue; save() }
    }

    var unmatched: [UnmatchedTrack] {
        get { snapshot.unmatched }
        set { snapshot.unmatched = newValue; save() }
    }

    var lastReport: SyncReport? {
        get { snapshot.lastReport }
        set { snapshot.lastReport = newValue; save() }
    }

    var autoSyncEnabled: Bool {
        get { snapshot.autoSyncEnabled }
        set { snapshot.autoSyncEnabled = newValue; save() }
    }

    func handledIDs(for playlistID: String) -> Set<String> {
        snapshot.handledIDs[playlistID] ?? []
    }

    func markHandled(_ ids: some Sequence<String>, playlistID: String) {
        snapshot.handledIDs[playlistID, default: []].formUnion(ids)
        let set = snapshot.handledIDs[playlistID] ?? []
        snapshot.unmatched.removeAll { set.contains($0.id) }
        save()
    }

    func resetHistory() {
        snapshot.handledIDs = [:]
        snapshot.unmatched = []
        snapshot.lastReport = nil
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("ShazSync: failed to save state: \(error)")
        }
    }
}
