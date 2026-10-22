import Foundation

enum StringSimilarity {
    /// 0...1 similarity of two already-normalized strings.
    /// Takes the best of edit-distance ratio and word overlap, so both typos
    /// and reordered words ("Beatles, The" vs "The Beatles") score well.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return a.isEmpty ? 0 : 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        return max(levenshteinRatio(a, b), tokenJaccard(a, b))
    }

    static func levenshteinRatio(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        let longest = max(x.count, y.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(x, y)) / Double(longest)
    }

    static func levenshtein(_ x: [Character], _ y: [Character]) -> Int {
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }

    static func tokenJaccard(_ a: String, _ b: String) -> Double {
        let ta = Set(a.split(separator: " ")), tb = Set(b.split(separator: " "))
        let union = ta.union(tb).count
        guard union > 0 else { return 0 }
        return Double(ta.intersection(tb).count) / Double(union)
    }
}
