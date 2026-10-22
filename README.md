# ShazSync: Shazam → Spotify for iPhone

An iPhone app (SwiftUI, iOS 17+) that copies the songs in your Shazam library into a Spotify playlist you choose. Songs it can't match with confidence go on a **Review** list with suggested Spotify alternatives, and you get a notification about them.

## What it does

- **Connects to Spotify** with secure sign-in (OAuth with PKCE, no client secret in the app). Tokens are stored in the Keychain.
- **Lets you pick a playlist** you own (or a collaborative one), or create a new one.
- **Reads your Shazam songs** from three sources (see [Where Shazam songs come from](#where-shazam-songs-come-from)).
- **Finds each song on Spotify**: exact ISRC lookup first, then title + artist search, then free-text search. Each result gets a 0–100% confidence score that ignores noise like "(Remastered 2011)", "- Radio Edit" and "feat. X", and penalizes live, karaoke and remix versions you didn't Shazam.
  - **85% or higher**: added automatically.
  - **35–85%**: goes to the Review list with up to 5 suggestions.
  - **Nothing usable**: goes to the Review list as "Not found on Spotify", with a manual search button.
- **Never adds duplicates**: it checks what's already in the playlist and remembers what it has synced.
- **Notifies you** after each sync, for example: *"Added 12 songs. 2 need a look. Hallelujah – Jeff Buckley: try “Hallelujah” by Pentatonix…"*. Tapping it opens the Review tab.
- **Syncs in the background** a few times a day (iOS decides when).
- **Identify button**: recognizes a song playing nearby with ShazamKit and saves it to your Shazam library, so it syncs next time.

## Where Shazam songs come from

Apple doesn't let third-party apps read the Shazam app's library directly (ShazamKit only exposes songs an app saved itself). ShazSync uses every route that is available:

| Source | How it works | Setup |
|---|---|---|
| **Apple Music "My Shazam Tracks"** (recommended) | The Shazam app can copy every song you Shazam into an Apple Music playlist. ShazSync reads it with MusicKit. | Shazam app → Settings → turn on **Apple Music** sync. Needs an Apple Music subscription. |
| **Songs identified in ShazSync** | Songs you identify with the Identify button. | None. |
| **CSV import** | Any CSV with `Title` and `Artist` columns, such as a Shazam library export. | Settings → Import Shazam CSV. |

Songs that appear in more than one source are synced once.

## Setup

You need a Mac with Xcode 16 or later and an Apple developer account (a free one works for running on your own iPhone).

1. **Create a Spotify app** at <https://developer.spotify.com/dashboard>.
   - Add the redirect URI `shazamspotifysync://callback`.
   - Choose **Web API**.
   - Copy the **Client ID**.
   - While the Spotify app is in development mode, only Spotify accounts you add under *User Management* can sign in.
2. **Add your client ID**:
   ```sh
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   # edit Config/Secrets.xcconfig and paste your client ID
   ```
3. **Generate the Xcode project** (the project file is generated from `project.yml`):
   ```sh
   brew install xcodegen
   xcodegen generate
   open ShazamSpotifySync.xcodeproj
   ```
4. **Set signing**: in Xcode, select the `ShazamSpotifySync` target → *Signing & Capabilities*, pick your team, and change the bundle ID from `com.example.shazamspotifysync` to one of your own.
5. **Enable App Services**: in the Apple developer portal, open your App ID and turn on **MusicKit** and **ShazamKit** under *App Services*.
6. Run it on your iPhone. Connect Spotify, choose a playlist, then tap **Sync now**.

## Project layout

```
ShazamSpotifySync/
  App/        App entry, app delegate (notifications, background tasks), shared AppModel
  Models/     SourceTrack, SpotifyTrack, UnmatchedTrack, SyncReport
  Matching/   Text normalization, similarity scoring, Spotify search strategy
  Sources/    Apple Music playlist, ShazamKit library + recognizer, CSV import
  Spotify/    PKCE sign-in, Web API client
  Sync/       SyncEngine: collect → match → add → report
  Services/   Saved state, Keychain, notifications, background refresh
  Views/      Sync, Review (unmatched + alternatives), playlist picker, settings
ShazamSpotifySyncTests/   Unit tests for matching, CSV parsing and search fallback
```

## Tests

```sh
./scripts/ci-test.sh   # generates the project and runs the tests on a simulator
```

The same script runs on GitHub Actions (`.github/workflows/ios.yml`) on every push.

## Notes

- Spotify is moving playlist endpoints from `/playlists/{id}/tracks` to `/playlists/{id}/items`. The client tries the new one first and falls back to the old one automatically.
- Background sync uses `BGAppRefreshTask`. iOS runs it based on how often you open the app, so it may not run every day.
