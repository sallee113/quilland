#!/bin/zsh
# Makes Resources/AppIcon.icns from the author's drawing Resources/AppIcon.svg (run it when the drawing changes; the .icns is kept in the project).
# Two drawings are made from it: the full one for 128 pixels and up, and one without the lettering for the small sizes.
set -e
cd "$(dirname "$0")"
python3 make-icon-svgs.py
TMP=$(mktemp -d)
swift make-icon.swift Resources/AppIcon-full.svg "$TMP/full.png"
swift make-icon.swift Resources/AppIcon-small.svg "$TMP/small.png"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
make() { # size, source
  sips -z $1 $1 "$2" --out "$3" >/dev/null
}
for size in 16 32 128 256 512; do
  double=$((size*2))
  if [ $size -ge 128 ]; then one="$TMP/full.png"; else one="$TMP/small.png"; fi
  if [ $double -ge 128 ]; then two="$TMP/full.png"; else two="$TMP/small.png"; fi
  make $size "$one" "$SET/icon_${size}x${size}.png"
  make $double "$two" "$SET/icon_${size}x${size}@2x.png"
done
# 64 pixels (32 at 2x) is still small: the drawing without the lettering.
make 64 "$TMP/small.png" "$SET/icon_32x32@2x.png"
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/full.png" Resources/AppIcon-1024.png
cp "$TMP/small.png" Resources/AppIcon-small-1024.png
# A contact sheet of the sizes, to look at.
swift make-icon.swift Resources/AppIcon-full.svg "$TMP/x.png" >/dev/null
echo "made Resources/AppIcon.icns"
