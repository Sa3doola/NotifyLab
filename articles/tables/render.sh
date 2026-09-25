#!/bin/sh
# Medium can't show tables, so every table in the articles is an image made from the
# .html file next to it. Edit the .html, then re-render:
#
#   ./render.sh               all tables
#   ./render.sh p0-kinds      one table
#
# Needs Google Chrome. Output: <name>.png at 2x, 960 px wide (1920 px image).
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH=${WIDTH:-960}

for file in ${1:-*}.html; do
  [ -f "$file" ] || continue
  name="${file%.html}"
  # Pass 1: let the page measure its own height, at the same 2x scale as the screenshot
  # (text wraps slightly differently at 1x, which cut off the bottom of tall tables).
  height=$("$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=$WIDTH,600 \
    --virtual-time-budget=2000 --dump-dom "file://$PWD/$file" 2>/dev/null \
    | sed -n 's/.*data-height="\([0-9]*\)".*/\1/p' | head -1)
  # Pass 2: screenshot at exactly that size.
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=$WIDTH,$height --screenshot="$PWD/$name.png" "file://$PWD/$file" >/dev/null 2>&1
  echo "$name.png  (${WIDTH}x${height} @2x)"
done
