#!/bin/bash
# Fetches yt-dlp and ffmpeg binaries into ClipTalk/Resources/bin/.
# These are gitignored — every build (including fresh clones) needs to run this.
# Idempotent: skips downloads if files already exist with non-zero size.

set -euo pipefail
cd "$(dirname "$0")/.."
DEST="ClipTalk/Resources/bin"
mkdir -p "$DEST"

# yt-dlp — official universal macOS standalone binary
YTDLP="$DEST/yt-dlp"
if [ ! -s "$YTDLP" ]; then
  echo "→ Fetching yt-dlp…"
  curl -fsSL -o "$YTDLP" \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
  chmod +x "$YTDLP"
else
  echo "✓ yt-dlp already present"
fi

# ffmpeg — static x86_64 build from osxexperts.net (works on Apple Silicon via Rosetta)
FFMPEG="$DEST/ffmpeg"
if [ ! -s "$FFMPEG" ]; then
  echo "→ Fetching ffmpeg…"
  TMP=$(mktemp -d)
  trap "rm -rf $TMP" EXIT
  curl -fsSL -o "$TMP/ffmpeg.zip" "https://www.osxexperts.net/ffmpeg7intel.zip"
  unzip -q -o "$TMP/ffmpeg.zip" -d "$TMP"
  cp "$TMP/ffmpeg" "$FFMPEG"
  chmod +x "$FFMPEG"
else
  echo "✓ ffmpeg already present"
fi

echo
echo "Bundled binaries:"
ls -lh "$DEST"
