import Foundation

// Raw Spotify Web API shapes. Fields are optional where Spotify may send
// null (local files, podcast episodes, removed tracks).

struct PagingDTO<Item: Decodable>: Decodable {
    let items: [Item]
    let next: String?
    let total: Int?
}

struct ImageDTO: Decodable {
    let url: URL
}

struct UserDTO: Decodable {
    let id: String
    let displayName: String?
}

struct CountRefDTO: Decodable {
    let total: Int?
}

struct PlaylistDTO: Decodable {
    let id: String
    let name: String
    let owner: UserDTO
    let images: [ImageDTO]?
    let collaborative: Bool?
    // Older responses call this "tracks", newer ones "items".
    let tracks: CountRefDTO?
    let items: CountRefDTO?

    var model: SpotifyPlaylist {
        SpotifyPlaylist(
            id: id,
            name: name,
            ownerID: owner.id,
            ownerName: owner.displayName ?? owner.id,
            imageURL: images?.first?.url,
            trackCount: items?.total ?? tracks?.total,
            collaborative: collaborative ?? false
        )
    }
}

struct ArtistDTO: Decodable {
    let name: String
}

struct AlbumDTO: Decodable {
    let name: String?
    let images: [ImageDTO]?
}

struct TrackDTO: Decodable {
    let id: String?
    let uri: String?
    let name: String?
    let durationMs: Int?
    let artists: [ArtistDTO]?
    let album: AlbumDTO?
    let externalIds: [String: String]?
    let externalUrls: [String: String]?
    let isLocal: Bool?
    let type: String?

    var model: SpotifyTrack? {
        guard let id, let uri, let name, isLocal != true, type == nil || type == "track" else { return nil }
        return SpotifyTrack(
            id: id,
            uri: uri,
            name: name,
            artists: artists?.map(\.name) ?? [],
            album: album?.name ?? "",
            durationMs: durationMs ?? 0,
            isrc: externalIds?["isrc"]?.uppercased(),
            imageURL: album?.images?.first?.url,
            externalURL: externalUrls?["spotify"].flatMap(URL.init(string:))
        )
    }
}

struct PlaylistItemDTO: Decodable {
    let track: TrackDTO?

    private enum CodingKeys: String, CodingKey { case track, item }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Be lenient: an episode or malformed entry just becomes nil.
        track = (try? c.decodeIfPresent(TrackDTO.self, forKey: .item))
            ?? (try? c.decodeIfPresent(TrackDTO.self, forKey: .track))
    }
}

struct SearchResponseDTO: Decodable {
    let tracks: PagingDTO<TrackDTO>
}

struct SnapshotDTO: Decodable {
    let snapshotId: String?
}

struct ErrorEnvelopeDTO: Decodable {
    struct Body: Decodable { let status: Int?; let message: String? }
    let error: Body
}
