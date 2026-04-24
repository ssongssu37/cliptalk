# Next session kickoff

Paste this into a fresh Claude chat to pick up where we left off:

---

I'm continuing work on **ClipTalk.app** — the native SwiftUI Mac port at `/Users/mac/Desktop/ClipTalk-Mac/`.

Before we start, please read:

- `/Users/mac/.claude/memory/cliptalk.md` — current state, architecture, and decisions already made
- `git log --oneline` in the project dir — commit `0212438` is the "Initial commit" with Phases 1–5 complete

**We finished Phases 1–5** (sidebar shell, Study view with player + scrubber, New clip view with Download + Clip by Text, OpenAI auto-explain via Keychain).

**Phase 6 is next — distribution prep.** Rough plan in priority order:

1. **Bundle binaries**
   - Ship `yt-dlp` and `ffmpeg` as sidecar binaries in `Contents/Resources/`
   - For `yt-dlp`: since it breaks whenever YouTube changes, plan to copy bundled version into `~/Library/Application Support/ClipTalk/bin/` on first launch, then silently run `yt-dlp -U` daily to keep it current. App prefers Application Support version when present.
   - Update `ProcessRunner.locate(...)` and `ClipExtractor` / `DownloadService` to use the bundled copy instead of Homebrew.

2. **Code-signing**
   - Sunghun has Apple Developer Program membership (uses it for iOS apps). Same cert works for Mac.
   - Find team ID, set it in `project.yml` (currently empty)
   - Decide: Developer ID Application cert (for outside-App-Store distribution) — confirm which signing identity to use
   - Enable Hardened Runtime (already on)

3. **Notarization**
   - `xcrun notarytool submit` + `xcrun stapler staple` pipeline
   - Script this so releases are one command

4. **Sparkle auto-update**
   - Add Sparkle via Swift Package Manager
   - Host the appcast XML feed and the signed DMG somewhere (GitHub Releases is fine to start)
   - Wire into `ClipTalkApp.swift`

5. **App icon**
   - Need a real 1024×1024 source image; generate all required sizes
   - Drop into `Assets.xcassets/AppIcon.appiconset/`

6. **Download website**
   - Simple page with download button, install instructions
   - Probably GitHub Pages or a static Vercel site

**One important architectural choice to confirm before building**: the `yt-dlp` self-update mechanism. My plan above is "copy bundled to App Support on first launch, then `yt-dlp -U` daily." Alternative is "just auto-update the full app more often via Sparkle." I'd recommend the first approach because yt-dlp updates are weekly and full-app updates shouldn't be.

Please read the memory file, confirm you understand the state, then propose Phase 6.1 — the bundled binaries step — and let's start building.

---
