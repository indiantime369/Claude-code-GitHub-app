import Foundation

/// Reads a Shazam library CSV export (for example from shazam.com/myshazam).
/// The format has changed over time, so columns are found by header name.
enum ShazamCSVImporter {
    enum ImportError: LocalizedError {
        case noHeader
        var errorDescription: String? {
            "Couldn't find \u{201C}Title\u{201D} and \u{201C}Artist\u{201D} columns in this file."
        }
    }

    static func parse(_ text: String) throws -> [SourceTrack] {
        let rows = CSVParser.rows(text)
        guard let headerIndex = rows.firstIndex(where: { row in
            let names = row.map(normalizedHeader)
            return names.contains("title") && names.contains("artist")
        }) else { throw ImportError.noHeader }

        let header = rows[headerIndex].map(normalizedHeader)
        func column(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }

        let titleCol = column("title")!
        let artistCol = column("artist")!
        let isrcCol = column("isrc")
        let albumCol = column("album")
        let dateCol = column("tagtime", "date", "datetime", "timestamp")

        let isoDate = ISO8601DateFormatter()
        let fallbackDate = DateFormatter()
        fallbackDate.locale = Locale(identifier: "en_US_POSIX")
        fallbackDate.dateFormat = "yyyy-MM-dd"

        return rows[(headerIndex + 1)...].compactMap { row in
            func value(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let v = row[index].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            guard let title = value(titleCol), let artist = value(artistCol) else { return nil }
            let date = value(dateCol).flatMap { isoDate.date(from: $0) ?? fallbackDate.date(from: String($0.prefix(10))) }
            return SourceTrack(title: title, artist: artist, album: value(albumCol), isrc: value(isrcCol),
                               shazamedAt: date, source: .csvImport)
        }
    }

    private static func normalizedHeader(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter }
    }
}

/// Minimal RFC 4180 CSV reader (quoted fields, escaped quotes, CRLF).
enum CSVParser {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let c = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": endField()
                case "\n", "\r\n", "\r": endRow()
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        // Strip a UTF-8 byte order mark from the first cell.
        if var first = rows.first, let cell = first.first, cell.hasPrefix("\u{FEFF}") {
            first[0] = String(cell.dropFirst())
            rows[0] = first
        }
        return rows
    }
}
