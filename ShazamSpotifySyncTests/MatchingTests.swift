import XCTest
@testable import ShazamSpotifySync

final class TextNormalizerTests: XCTestCase {
    func testNormalizeStripsAccentsAndPunctuation() {
        XCTAssertEqual(TextNormalizer.normalize("Beyoncé – Déjà Vu!"), "beyonce deja vu")
        XCTAssertEqual(TextNormalizer.normalize("Don't Stop"), "dont stop")
        XCTAssertEqual(TextNormalizer.normalize("Simon & Garfunkel"), "simon and garfunkel")
    }

    func testCoreTitleRemovesDecorations() {
        XCTAssertEqual(TextNormalizer.coreTitle("Here Comes the Sun (Remastered 2009)"), "here comes the sun")
        XCTAssertEqual(TextNormalizer.coreTitle("Blinding Lights - Radio Edit"), "blinding lights")
        XCTAssertEqual(TextNormalizer.coreTitle("Stay feat. Justin Bieber"), "stay")
        XCTAssertEqual(TextNormalizer.coreTitle("(I Can't Get No) Satisfaction"), "satisfaction")
    }

    func testArtistList() {
        XCTAssertEqual(TextNormalizer.artistList("Calvin Harris feat. Rihanna"), ["calvin harris", "rihanna"])
        XCTAssertEqual(TextNormalizer.artistList("Dua Lipa & DaBaby"), ["dua lipa", "dababy"])
        XCTAssertEqual(TextNormalizer.primaryArtist("Kygo, Selena Gomez"), "kygo")
    }

    func testStableIDIgnoresVersionNoise() {
        XCTAssertEqual(
            SourceTrack.stableID(title: "Levitating (feat. DaBaby)", artist: "Dua Lipa feat. DaBaby"),
            SourceTrack.stableID(title: "Levitating", artist: "Dua Lipa")
        )
    }
}

final class TrackMatcherTests: XCTestCase {
    private let matcher = TrackMatcher()

    private func spotify(_ name: String, _ artists: [String], isrc: String? = nil,
                         durationMs: Int = 200_000, id: String? = nil) -> SpotifyTrack {
        let trackID = id ?? UUID().uuidString
        return SpotifyTrack(id: trackID, uri: "spotify:track:\(trackID)", name: name, artists: artists,
                            album: "Album", durationMs: durationMs, isrc: isrc, imageURL: nil, externalURL: nil)
    }

    func testISRCMatchIsPerfect() {
        let source = SourceTrack(title: "Whatever", artist: "Someone", isrc: "usum71900764", source: .csvImport)
        XCTAssertEqual(matcher.score(source, spotify("Different", ["Other"], isrc: "USUM71900764")), 1)
    }

    func testRemasterSuffixStillMatches() {
        let source = SourceTrack(title: "Here Comes The Sun", artist: "The Beatles", source: .csvImport)
        let candidate = spotify("Here Comes The Sun - Remastered 2009", ["The Beatles"])
        guard case .matched = matcher.evaluate(source, candidates: [candidate]) else {
            return XCTFail("Expected a match")
        }
    }

    func testFeaturedArtistMatches() {
        let source = SourceTrack(title: "This Is What You Came For", artist: "Calvin Harris feat. Rihanna", source: .csvImport)
        let candidate = spotify("This Is What You Came For", ["Calvin Harris", "Rihanna"])
        XCTAssertGreaterThanOrEqual(matcher.score(source, candidate), matcher.autoAcceptThreshold)
    }

    func testPrefersOriginalOverKaraoke() {
        let source = SourceTrack(title: "Rolling in the Deep", artist: "Adele", source: .csvImport)
        let karaoke = spotify("Rolling in the Deep (Karaoke Version)", ["Adele"], id: "karaoke")
        let original = spotify("Rolling in the Deep", ["Adele"], id: "original")
        guard case .matched(let best) = matcher.evaluate(source, candidates: [karaoke, original]) else {
            return XCTFail("Expected a match")
        }
        XCTAssertEqual(best.track.id, "original")
    }

    func testCoverByOtherArtistNeedsReview() {
        let source = SourceTrack(title: "Hallelujah", artist: "Jeff Buckley", source: .csvImport)
        let cover = spotify("Hallelujah", ["Pentatonix"])
        guard case .needsReview(let alternatives) = matcher.evaluate(source, candidates: [cover]) else {
            return XCTFail("Expected review")
        }
        XCTAssertEqual(alternatives.count, 1)
    }

    func testUnrelatedResultsAreNotFound() {
        let source = SourceTrack(title: "Obscure Bootleg", artist: "Unknown DJ", source: .csvImport)
        let unrelated = spotify("Completely Different Song", ["Famous Band"])
        XCTAssertEqual(matcher.evaluate(source, candidates: [unrelated]), .notFound)
    }
}

final class CSVImportTests: XCTestCase {
    func testParsesShazamExportWithPreamble() throws {
        let csv = """
        Shazam Library\r
        Index,TagTime,Title,Artist,URL,TrackKey\r
        1,2024-05-01,"Song, With Comma",Artist A,https://www.shazam.com/track/1,1\r
        2,2024-05-02,"He said ""hi""",Artist B,https://www.shazam.com/track/2,2\r
        3,2024-05-03,,Missing Title,,3\r
        """
        let tracks = try ShazamCSVImporter.parse(csv)
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].title, "Song, With Comma")
        XCTAssertEqual(tracks[0].artist, "Artist A")
        XCTAssertNotNil(tracks[0].shazamedAt)
        XCTAssertEqual(tracks[1].title, "He said \"hi\"")
    }

    func testMissingColumnsThrows() {
        XCTAssertThrowsError(try ShazamCSVImporter.parse("a,b\n1,2"))
    }
}

@MainActor
final class TrackResolverTests: XCTestCase {
    final class FakeSearch: SpotifySearching {
        var results: [String: [SpotifyTrack]] = [:]
        var queries: [String] = []
        func searchTracks(query: String, limit: Int) async throws -> [SpotifyTrack] {
            queries.append(query)
            return results[query] ?? []
        }
    }

    private func track(_ id: String, _ name: String, _ artist: String, isrc: String? = nil) -> SpotifyTrack {
        SpotifyTrack(id: id, uri: "spotify:track:\(id)", name: name, artists: [artist], album: "",
                     durationMs: 180_000, isrc: isrc, imageURL: nil, externalURL: nil)
    }

    func testISRCSearchShortCircuits() async throws {
        let search = FakeSearch()
        search.results["isrc:GBAYE0601498"] = [track("1", "Song", "Band", isrc: "GBAYE0601498")]
        let source = SourceTrack(title: "Song", artist: "Band", isrc: "GBAYE0601498", source: .shazamKitLibrary)
        let outcome = try await TrackResolver(search: search).resolve(source)
        guard case .matched(let best) = outcome else { return XCTFail("Expected match") }
        XCTAssertEqual(best.track.id, "1")
        XCTAssertEqual(search.queries, ["isrc:GBAYE0601498"])
    }

    func testFallsBackToFreeText() async throws {
        let search = FakeSearch()
        search.results["Levitating Dua Lipa"] = [track("2", "Levitating (feat. DaBaby)", "Dua Lipa")]
        let source = SourceTrack(title: "Levitating", artist: "Dua Lipa feat. DaBaby", source: .csvImport)
        let outcome = try await TrackResolver(search: search).resolve(source)
        guard case .matched(let best) = outcome else { return XCTFail("Expected match, got \(outcome)") }
        XCTAssertEqual(best.track.id, "2")
        XCTAssertEqual(search.queries, ["track:\"Levitating\" artist:\"Dua Lipa\"", "Levitating Dua Lipa"])
    }
}

final class TitleEdgeCaseTests: XCTestCase {
    func testWithInTitleIsKept() {
        XCTAssertEqual(TextNormalizer.coreTitle("Stay With Me"), "stay with me")
    }

    func testKaraokeAloneIsNotAutoAccepted() {
        let source = SourceTrack(title: "Rolling in the Deep", artist: "Adele", source: .csvImport)
        let karaoke = SpotifyTrack(id: "k", uri: "spotify:track:k", name: "Rolling in the Deep (Karaoke Version)",
                                   artists: ["Adele"], album: "", durationMs: 0, isrc: nil, imageURL: nil, externalURL: nil)
        guard case .needsReview = TrackMatcher().evaluate(source, candidates: [karaoke]) else {
            return XCTFail("Karaoke should need review")
        }
    }
}
