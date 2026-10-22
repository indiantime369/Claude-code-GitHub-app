import Foundation
import UserNotifications

/// Local notifications summarizing each sync and pointing to the review list.
@MainActor
final class NotificationManager {
    static let reviewAction = "review-unmatched"

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func postSyncSummary(report: SyncReport, newUnmatched: [UnmatchedTrack],
                         playlistName: String, trigger: SyncEngine.Trigger) async {
        // Nothing new: stay quiet.
        if report.added == 0 && newUnmatched.isEmpty { return }

        let content = UNMutableNotificationContent()
        content.sound = .default

        if newUnmatched.isEmpty {
            content.title = "Added \(songs(report.added)) to \(playlistName)"
            content.body = "Your Shazam library is in sync."
        } else {
            content.title = report.added > 0
                ? "Added \(songs(report.added)). \(newUnmatched.count) need a look."
                : "\(songs(newUnmatched.count)) couldn't be matched"
            content.body = Self.summary(of: newUnmatched)
            content.userInfo = ["action": Self.reviewAction]
        }

        let request = UNNotificationRequest(identifier: "sync-\(report.date.timeIntervalSince1970)",
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// "Song – Artist: try “Alternative” by X" for the first few songs.
    static func summary(of items: [UnmatchedTrack], limit: Int = 3) -> String {
        var lines = items.prefix(limit).map { item -> String in
            let name = "\(item.source.title) \u{2013} \(item.source.artist)"
            if let best = item.alternatives.first {
                return "\(name): try \u{201C}\(best.track.name)\u{201D} by \(best.track.artistLine)"
            }
            return "\(name): not on Spotify"
        }
        if items.count > limit { lines.append("and \(items.count - limit) more. Tap to review.") }
        else { lines.append("Tap to review alternatives.") }
        return lines.joined(separator: "\n")
    }

    private func songs(_ n: Int) -> String { n == 1 ? "1 song" : "\(n) songs" }
}
