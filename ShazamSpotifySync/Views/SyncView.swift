import SwiftUI

struct SyncView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppStore.self) private var store
    @Environment(SpotifyAuth.self) private var auth
    @Environment(SyncEngine.self) private var engine
    @Environment(ShazamRecognizer.self) private var recognizer

    @State private var signInError: String?

    var body: some View {
        NavigationStack {
            List {
                spotifySection
                playlistSection
                syncSection
                if let report = store.lastReport { reportSection(report) }
                identifySection
            }
            .navigationTitle("ShazSync")
            .refreshable { await runSync() }
            .alert("Spotify", isPresented: Binding(get: { signInError != nil }, set: { if !$0 { signInError = nil } }),
                   presenting: signInError) { _ in
                Button("OK") { signInError = nil }
            } message: { Text($0) }
        }
    }

    private var spotifySection: some View {
        Section("Spotify account") {
            if auth.isSignedIn {
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button {
                    Task {
                        do { try await auth.signIn() } catch SpotifyError.authCancelled {
                        } catch { signInError = error.localizedDescription }
                    }
                } label: {
                    Label("Connect Spotify", systemImage: "person.crop.circle.badge.plus")
                }
                if !SpotifyConfig.isConfigured {
                    Text("Set SPOTIFY_CLIENT_ID in Config/Secrets.xcconfig, then rebuild.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    private var playlistSection: some View {
        Section("Sync to playlist") {
            NavigationLink {
                PlaylistPickerView()
            } label: {
                if let playlist = store.selectedPlaylist {
                    PlaylistRow(playlist: playlist)
                } else {
                    Text("Choose a playlist").foregroundStyle(.secondary)
                }
            }
            .disabled(!auth.isSignedIn)
        }
    }

    private var syncSection: some View {
        Section {
            Button {
                Task { await runSync() }
            } label: {
                HStack {
                    Spacer()
                    if engine.phase.isRunning { ProgressView().padding(.trailing, 6) }
                    Text(engine.phase.isRunning ? "Syncing\u{2026}" : "Sync now").bold()
                    Spacer()
                }
            }
            .disabled(engine.phase.isRunning || !auth.isSignedIn || store.selectedPlaylist == nil)

            switch engine.phase {
            case .collecting:
                Text("Reading your Shazam library\u{2026}").foregroundStyle(.secondary)
            case .matching(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1))) {
                    Text("Finding songs on Spotify: \(done) of \(total)")
                }
            case .adding(let count):
                Text("Adding \(count) songs\u{2026}").foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .idle, .finished:
                EmptyView()
            }
        } footer: {
            Text("Sources: " + TrackSource.allCases.filter(store.enabledSources.contains).map(\.displayName).joined(separator: ", "))
        }
    }

    private func reportSection(_ report: SyncReport) -> some View {
        Section("Last sync \u{2013} \(report.date.formatted(.relative(presentation: .named)))") {
            LabeledContent("Songs in Shazam library", value: "\(report.scanned)")
            LabeledContent("Added to playlist", value: "\(report.added)")
            LabeledContent("Already in playlist", value: "\(report.alreadyInPlaylist)")
            if store.unmatched.isEmpty {
                LabeledContent("Couldn't match", value: "0")
            } else {
                Button {
                    model.selectedTab = .review
                } label: {
                    LabeledContent("Need review", value: "\(store.unmatched.count)")
                }
            }
            ForEach(report.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private var identifySection: some View {
        Section {
            Button {
                Task { await recognizer.identify() }
            } label: {
                Label(recognizer.state == .listening ? "Listening\u{2026}" : "Identify a song", systemImage: "shazam.logo")
            }
            .disabled(recognizer.state == .listening)

            switch recognizer.state {
            case .matched(let title, let artist):
                Text("Saved \u{201C}\(title)\u{201D} by \(artist). It will sync next time.")
            case .noMatch:
                Text("No match. Try again closer to the music.").foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            case .idle, .listening:
                EmptyView()
            }
        } footer: {
            Text("Songs identified here are saved to your Shazam library and synced automatically.")
        }
    }

    private func runSync() async {
        await model.notifications.requestAuthorization()
        await engine.sync()
    }
}

struct PlaylistRow: View {
    let playlist: SpotifyPlaylist

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: playlist.imageURL, size: 44)
            VStack(alignment: .leading) {
                Text(playlist.name)
                if let count = playlist.trackCount {
                    Text("\(count) songs").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Artwork: View {
    let url: URL?
    var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.secondary.opacity(0.15))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
