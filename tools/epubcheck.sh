#!/bin/bash
# Usage: tools/epubcheck.sh <file.epub>...
# Downloads the latest official epubcheck release into tools/epubcheck/ on first use.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
dir="$root/epubcheck"
jar="$dir/epubcheck.jar"

if [[ ! -f "$jar" ]]; then
    echo "epubcheck not found, downloading latest release..." >&2
    url="$(curl -fsSL https://api.github.com/repos/w3c/epubcheck/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed -E 's/.*"(https[^"]*)"/\1/')"
    [[ -n "$url" ]] || { echo "could not resolve epubcheck download URL" >&2; exit 1; }
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/epubcheck.zip" "$url"
    unzip -q "$tmp/epubcheck.zip" -d "$tmp/unpacked"
    mkdir -p "$dir"
    # The zip contains a single epubcheck-X.Y.Z/ folder with the jar and lib/.
    cp -R "$tmp"/unpacked/*/. "$dir/"
    mv "$dir"/epubcheck-*.jar "$jar" 2>/dev/null || true
    [[ -f "$jar" ]] || { echo "epubcheck.jar missing after unpack" >&2; exit 1; }
fi

exec java -jar "$jar" "$@"
