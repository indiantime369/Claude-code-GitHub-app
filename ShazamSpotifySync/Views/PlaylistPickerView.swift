import SwiftUI

struct PlaylistPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [SpotifyPlaylist] = []
    @State private var loading = true
    @State private var error: String?
    @State private var filter = ""
    @State private var showingCreate = false
    @State private var newName = "My Shazam Tracks"

    private var filtered: [SpotifyPlaylist] {
        filter.isEmpty ? playlists : playlists.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            ForEach(filtered) { playlist in
                Button {
                    store.selectedPlaylist = playlist
                    dismiss()
                } label: {
                    HStack {
                        PlaylistRow(playlist: playlist)
                        Spacer()
                        if playlist.id == store.selectedPlaylist?.id {
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .overlay { if loading && playlists.isEmpty { ProgressView() } }
        .searchable(text: $filter)
        .navigationTitle("Choose playlist")
        .toolbar {
            Button { showingCreate = true } label: { Label("New playlist", systemImage: "plus") }
        }
        .alert("New playlist", isPresented: $showingCreate) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await create() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            playlists = try await model.api.editablePlaylists()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let playlist = try await model.api.createPlaylist(named: name)
            store.selectedPlaylist = playlist
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
