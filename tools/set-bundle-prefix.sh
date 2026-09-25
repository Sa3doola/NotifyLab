#!/usr/bin/env bash
# Switch every ID in the repo to your own prefix, then regenerate the Xcode project.
#
#   ./tools/set-bundle-prefix.sh com.yourname
#
# Result:  com.yourname.notifylab (+ .service, .content)  and  group.com.yourname.notifylab
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:?usage: tools/set-bundle-prefix.sh com.yourname}"
OLD=$(sed -n 's/^ *BUNDLE_ID_PREFIX: *//p' project.yml)
OLD_RE="${OLD//./\\.}"

sed -i '' "s/BUNDLE_ID_PREFIX: ${OLD_RE}\$/BUNDLE_ID_PREFIX: ${NEW}/" project.yml

# Files that must spell the bundle ID out (they can't read build settings).
FILES=(payloads/*.apns tools/.env.example tools/NotifyLab.postman_collection.json)
[ -f tools/.env ] && FILES+=(tools/.env)
for file in "${FILES[@]}"; do
  sed -i '' "s/${OLD_RE}\.notifylab/${NEW}.notifylab/g" "$file"
done

xcodegen generate
echo "✓ ${NEW}.notifylab (+ .service, .content) · App Group group.${NEW}.notifylab"
echo "  Next: set DEVELOPMENT_TEAM in project.yml (or pick your team in Xcode), then build."
