import Foundation

/// Scores Spotify search results against a Shazam song and decides whether
/// one is a confident match or the song should go to the review list.
struct TrackMatcher {
    /// At or above this score, a candidate is added automatically.
    var autoAcceptThreshold = 0.85
    /// Candidates below this score are not worth suggesting.
    var alternativeThreshold = 0.35
    var maxAlternatives = 5

    func score(_ source: SourceTrack, _ candidate: SpotifyTrack) -> Double {
        if let a = source.isrc, let b = candidate.isrc, a.caseInsensitiveCompare(b) == .orderedSame {
            return 1
        }

        // Title: compare both the full title and the "core" title.
        let titleScore = max(
            StringSimilarity.similarity(TextNormalizer.normalize(source.title), TextNormalizer.normalize(candidate.name)),
            StringSimilarity.similarity(TextNormalizer.coreTitle(source.title), TextNormalizer.coreTitle(candidate.name))
        )

        // Artist: best overlap between any credited artist on each side.
        let sourceArtists = TextNormalizer.artistList(source.artist)
        let candidateArtists = candidate.artists.map(TextNormalizer.normalize)
        var artistScore = StringSimilarity.similarity(
            TextNormalizer.normalize(source.artist),
            TextNormalizer.normalize(candidate.artistLine)
        )
        for s in sourceArtists {
            for c in candidateArtists {
                artistScore = max(artistScore, StringSimilarity.similarity(s, c))
            }
        }

        var total = 0.55 * titleScore + 0.45 * artistScore

        // Penalize a live/remix/karaoke version the user didn't Shazam.
        let extraTags = TextNormalizer.versionTags(candidate.name)
            .subtracting(TextNormalizer.versionTags(source.title))
            .subtracting(["remastered", "remaster", "version", "edit"])
        if !extraTags.isEmpty { total -= 0.2 }

        if let sourceMs = source.durationMs, sourceMs > 0 {
            let diff = abs(sourceMs - candidate.durationMs)
            if diff <= 3_000 { total += 0.05 } else if diff > 30_000 { total -= 0.10 }
        }

        return min(1, max(0, total))
    }

    func evaluate(_ source: SourceTrack, candidates: [SpotifyTrack]) -> MatchOutcome {
        var seen = Set<String>()
        let ranked = candidates
            .filter { seen.insert($0.id).inserted }
            .map { ScoredCandidate(track: $0, score: score(source, $0)) }
            .sorted { $0.score > $1.score }

        if let best = ranked.first, best.score >= autoAcceptThreshold {
            return .matched(best)
        }
        let alternatives = Array(ranked.filter { $0.score >= alternativeThreshold }.prefix(maxAlternatives))
        return alternatives.isEmpty ? .notFound : .needsReview(alternatives)
    }
}
