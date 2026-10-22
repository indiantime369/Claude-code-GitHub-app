import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(SpotifyAuth.self) private var auth

    @State private var importing = false
    @State private var importMessage: String?
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    ForEach(TrackSource.allCases) { source in
                        Toggle(isOn: Binding(
                            get: { store.enabledSources.contains(source) },
                            set: { on in
                                if on { store.enabledSources.insert(source) } else { store.enabledSources.remove(source) }
                            }
                        )) {
                            Label(source.displayName, systemImage: source.systemImage)
                        }
                    }
                } header: {
                    Text("Shazam sources")
                } footer: {
                    Text("Apple doesn't let other apps read the Shazam app's library directly. The most complete source is the \u{201C}My Shazam Tracks\u{201D} playlist: in the Shazam app, open Settings and turn on Apple Music sync.")
                }

                Section("Apple Music playlist name") {
                    TextField("My Shazam Tracks", text: $store.appleMusicPlaylistName)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Import Shazam CSV\u{2026}", systemImage: "square.and.arrow.down") { importing = true }
                    if !store.importedCSVTracks.isEmpty {
                        LabeledContent("Imported songs", value: "\(store.importedCSVTracks.count)")
                        Button("Remove imported songs", role: .destructive) { store.importedCSVTracks = [] }
                    }
                    if let importMessage { Text(importMessage).font(.footnote) }
                } header: {
                    Text("CSV import")
                } footer: {
                    Text("Use a CSV with Title and Artist columns, such as a Shazam library export.")
                }

                Section {
                    Toggle("Sync in the background", isOn: Binding(
                        get: { store.autoSyncEnabled },
                        set: { store.autoSyncEnabled = $0; BackgroundSync.schedule(enabled: $0) }
                    ))
                } footer: {
                    Text("iOS picks the exact times, usually a few times a day. You'll get a notification when songs are added or need review.")
                }

                Section {
                    Button("Clear sync history", role: .destructive) { confirmReset = true }
                    if auth.isSignedIn {
                        Button("Disconnect Spotify", role: .destructive) { auth.signOut() }
                    }
                } footer: {
                    Text("Clearing history makes the next sync check every song again. Songs already in the playlist are never added twice.")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                handleImport(result)
            }
            .confirmationDialog("Clear sync history?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { store.resetHistory() }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            let tracks = try ShazamCSVImporter.parse(text)
            var byID = Dictionary(store.importedCSVTracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for track in tracks { byID[track.id] = track }
            store.importedCSVTracks = Array(byID.values)
            store.enabledSources.insert(.csvImport)
            importMessage = "Imported \(tracks.count) songs."
        } catch {
            importMessage = error.localizedDescription
        }
    }
}
