import SwiftUI

/// Songs that couldn't be synced, with suggested Spotify alternatives.
struct ReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(SyncEngine.self) private var engine

    @State private var searching: UnmatchedTrack?

    var body: some View {
        NavigationStack {
            Group {
                if store.unmatched.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle",
                                           description: Text("Songs that can't be matched on Spotify will show up here with suggested alternatives."))
                } else {
                    List {
                        Section {
                            ForEach(store.unmatched) { item in
                                UnmatchedRow(item: item, onSearch: { searching = item })
                                    .swipeActions {
                                        Button("Dismiss", role: .destructive) { engine.dismiss(item) }
                                    }
                            }
                        } footer: {
                            Text("Tap a suggestion to add it to \(store.selectedPlaylist?.name ?? "your playlist"). Swipe left to dismiss a song.")
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                if !store.unmatched.isEmpty {
                    Button {
                        Task { await engine.retryUnmatched() }
                    } label: {
                        if engine.phase.isRunning { ProgressView() } else { Text("Retry all") }
                    }
                    .disabled(engine.phase.isRunning)
                }
            }
            .sheet(item: $searching) { item in
                ManualSearchView(item: item)
            }
        }
    }
}

struct UnmatchedRow: View {
    let item: UnmatchedTrack
    let onSearch: () -> Void

    @Environment(SyncEngine.self) private var engine
    @State private var adding: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.source.title).font(.headline)
                Text(item.source.artist).font(.subheadline).foregroundStyle(.secondary)
                Text(item.reason == .notFound ? "Not found on Spotify" : "No exact match. Did you mean:")
                    .font(.caption).foregroundStyle(.orange)
            }

            ForEach(item.alternatives) { candidate in
                Button {
                    Task { await add(candidate.track) }
                } label: {
                    CandidateRow(candidate: candidate, isAdding: adding == candidate.id)
                }
                .buttonStyle(.borderless)
                .disabled(adding != nil)
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            Button("Search Spotify\u{2026}", systemImage: "magnifyingglass", action: onSearch)
                .font(.subheadline)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func add(_ track: SpotifyTrack) async {
        adding = track.id
        defer { adding = nil }
        do { try await engine.accept(track, for: item) } catch { self.error = error.localizedDescription }
    }
}

struct CandidateRow: View {
    let candidate: ScoredCandidate
    var isAdding = false

    var body: some View {
        HStack(spacing: 10) {
            Artwork(url: candidate.track.imageURL, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.track.name).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                Text("\(candidate.track.artistLine) \u{00B7} \(candidate.track.album)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isAdding {
                ProgressView()
            } else {
                Text("\(Int((candidate.score * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
            }
        }
        .contextMenu {
            if let url = candidate.track.externalURL {
                Link("Open in Spotify", destination: url)
            }
        }
    }
}

/// Free-text Spotify search for a song with no good suggestions.
struct ManualSearchView: View {
    let item: UnmatchedTrack

    @Environment(AppModel.self) private var model
    @Environment(SyncEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [ScoredCandidate] = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(results) { candidate in
                    Button {
                        Task { await add(candidate.track) }
                    } label: {
                        CandidateRow(candidate: candidate)
                    }
                    .disabled(busy)
                }
            }
            .overlay { if busy && results.isEmpty { ProgressView() } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle(item.source.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task {
                query = "\(TrackResolver.stripDecorations(item.source.title)) \(TrackResolver.primaryArtistDisplay(item.source.artist))"
                await search()
            }
        }
    }

    private func search() async {
        busy = true
        defer { busy = false }
        do {
            let tracks = try await model.api.searchTracks(query: query, limit: 10)
            let matcher = TrackMatcher()
            results = tracks.map { ScoredCandidate(track: $0, score: matcher.score(item.source, $0)) }
            error = tracks.isEmpty ? "No results." : nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func add(_ track: SpotifyTrack) async {
        busy = true
        defer { busy = false }
        do {
            try await engine.accept(track, for: item)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
