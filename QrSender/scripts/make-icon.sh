#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns (macOS) and ReceiverAppIcon-1024.png (iOS) from scripts/make-icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Resources
swift scripts/make-icon.swift Resources/AppIcon-1024.png

SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/AppIcon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$(dirname "$SET")"
echo "Wrote Resources/AppIcon.icns"

swift scripts/make-icon.swift Resources/ReceiverAppIcon-1024.png --ios
echo "Wrote Resources/ReceiverAppIcon-1024.png (iOS, drop into Assets.xcassets/AppIcon)"
