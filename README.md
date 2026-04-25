# ClipTalk

A small Mac app for studying English from YouTube clips. Highlight transcript text, press <kbd>⌥Z</kbd>, and the matching audio + transcript get saved to your local library.

→ **[studybanana.com](https://studybanana.com)** — download, screenshots, more

## Status

v0.1.0. Built and used daily by the author. Free and MIT-licensed.

## Building from source

Requirements: Xcode 15+, macOS 13+.

```sh
./scripts/fetch-binaries.sh   # downloads bundled yt-dlp + ffmpeg
xcodegen                       # generates ClipTalk.xcodeproj
open ClipTalk.xcodeproj        # then ⌘R in Xcode
```

## Releasing

`scripts/release.sh` does the full pipeline: signed Release archive, hardened runtime, embedded-binary signing, notarization, stapling, DMG packaging.

```sh
VERSION=0.1.0 ./scripts/release.sh
```

Output lands at `release/ClipTalk.dmg`.

Requires a Developer ID Application certificate in your Keychain plus an App Store Connect API key configured in the script.

## License

MIT. See `LICENSE`.
