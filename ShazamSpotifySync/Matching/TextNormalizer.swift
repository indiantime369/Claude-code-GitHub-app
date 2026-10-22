import Foundation

/// Cleans up song titles and artist names so they can be compared.
enum TextNormalizer {
    /// Lowercase, strip accents and punctuation, collapse whitespace.
    static func normalize(_ text: String) -> String {
        var s = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        s = s.lowercased()
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        s = s.replacingOccurrences(of: "'", with: "")
        s = s.replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Title without "(Remastered 2011)", "- Radio Edit", "feat. X" and similar.
    static func coreTitle(_ title: String) -> String {
        var s = title
        s = s.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+[-\u{2013}\u{2014}]\\s+.*$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+(feat\\.?|ft\\.?|featuring)\\s+.*$", with: "",
                                   options: [.regularExpression, .caseInsensitive])
        let core = normalize(s)
        return core.isEmpty ? normalize(title) : core
    }

    /// All artists named in a credit like "A feat. B & C".
    static func artistList(_ artist: String) -> [String] {
        let pattern = "\\s*(,|&|;|/|\\+|\\bfeat\\.?|\\bft\\.?|\\bfeaturing\\b|\\bwith\\b|\\bx\\b|\\bvs\\.?)\\s*"
        return artist
            .replacingOccurrences(of: pattern, with: "|", options: [.regularExpression, .caseInsensitive])
            .split(separator: "|")
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func primaryArtist(_ artist: String) -> String {
        artistList(artist).first ?? normalize(artist)
    }

    private static let versionKeywords: Set<String> = [
        "live", "remix", "mix", "karaoke", "instrumental", "cover", "acoustic",
        "remastered", "remaster", "demo", "edit", "version", "tribute", "originally",
        "sped", "slowed", "reverb", "nightcore", "acapella", "unplugged", "orchestral",
    ]

    /// Version words ("live", "remix", "karaoke", ...) found in a title.
    static func versionTags(_ title: String) -> Set<String> {
        Set(normalize(title).split(separator: " ").map(String.init)).intersection(versionKeywords)
    }

    /// Text safe to put inside quotes in a Spotify search query.
    static func queryText(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
