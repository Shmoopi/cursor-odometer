#!/usr/bin/env bash
# Generates the Cursor Odometer app icon set from a single 1024×1024 source.
#
# Design: dark squircle (Big Sur-style, ~22% corner radius, 100 px inset on
# 1024 px canvas) with a centred bold "0" digit suggesting an odometer reel.
# Re-run after editing this script to refresh every PNG in the .appiconset.
#
# Requires: ImageMagick (`brew install imagemagick`) and sips (built into macOS).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
iconset="$repo_root/Sources/CursorOdometerApp/Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v magick >/dev/null 2>&1; then
  echo "error: ImageMagick (magick) not found. brew install imagemagick" >&2
  exit 1
fi

if [[ ! -d "$iconset" ]]; then
  echo "error: appiconset not found at $iconset" >&2
  exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
base="$scratch/icon-1024.png"

# Step 1 — squircle background on a transparent 1024×1024 canvas.
# Inset 100 px on each side leaves an 824 px squircle, corner radius 185
# (~22.5%, matching macOS Big Sur+ icon geometry).
magick -size 1024x1024 xc:none \
  -fill '#17171A' \
  -draw 'roundrectangle 100,100 924,924 185,185' \
  "$base"

# Step 2 — bold "0" digit. ImageMagick on macOS ships with an empty
# fontconfig cache, so resolve the font by absolute path. Prefer a true Bold
# .ttf (face 0 of Helvetica.ttc renders as Regular and looks thin at scale).
digit_font=''
for candidate in \
  '/System/Library/Fonts/Supplemental/Arial Bold.ttf' \
  '/System/Library/Fonts/Supplemental/Arial Black.ttf' \
  '/Library/Fonts/Arial Bold.ttf' \
  '/System/Library/Fonts/Helvetica.ttc'; do
  if [[ -f "$candidate" ]]; then
    digit_font="$candidate"
    break
  fi
done
: "${digit_font:?no usable bold sans-serif font available}"

# Render the digit on its own canvas at a large size, then trim the glyph's
# bounding box. Compositing the trimmed result onto the base centres it
# geometrically — no manual baseline-correction offsets needed.
digit_png="$scratch/digit.png"
magick -background none \
  -fill '#F5F5F7' \
  -font "$digit_font" \
  -pointsize 900 \
  label:'0' \
  -trim +repage \
  "$digit_png"

# Resize the digit so its longer edge is ~58% of the canvas (matches macOS
# Big Sur+ icon content density), preserving aspect ratio.
target_px=590
magick "$digit_png" \
  -resize "${target_px}x${target_px}" \
  "$digit_png"

magick "$base" "$digit_png" -gravity center -composite "$base"

# Step 3 — downsample to every Contents.json slot. sips preserves the alpha
# channel and produces results indistinguishable from Xcode's own export.
gen() {
  local px="$1" name="$2"
  sips -z "$px" "$px" "$base" --out "$iconset/$name" >/dev/null
}

gen 16   AppIcon-16.png
gen 32   AppIcon-16@2x.png
gen 32   AppIcon-32.png
gen 64   AppIcon-32@2x.png
gen 128  AppIcon-128.png
gen 256  AppIcon-128@2x.png
gen 256  AppIcon-256.png
gen 512  AppIcon-256@2x.png
gen 512  AppIcon-512.png
gen 1024 AppIcon-512@2x.png

echo "Generated 10 PNGs in $iconset (font: $digit_font)"
