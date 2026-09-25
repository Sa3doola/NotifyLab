#!/usr/bin/env bash
# Send a push straight to APNs with curl, the way your server would.
#
#   ./tools/apns.sh payloads/order-shipped.apns              # alert, priority 10
#   ./tools/apns.sh payloads/marketing-passive.apns marketing # alert, priority 5
#   ./tools/apns.sh payloads/silent-sync.apns background      # content-available, priority 5
#   ./tools/apns.sh payloads/voip-call.json voip              # PushKit, topic <bundle>.voip
#
# Reads TEAM_ID, KEY_ID, KEY_PATH, BUNDLE_ID, DEVICE_TOKEN, VOIP_TOKEN, APNS_ENV from tools/.env.
# Variables set in the shell win, so you can override one per send:
#
#   COLLAPSE_ID=order-1042 ./tools/apns.sh payloads/order-out-for-delivery.apns
#   EXPIRATION=0 ./tools/apns.sh payloads/order-shipped.apns     # try once, don't store
set -euo pipefail
cd "$(dirname "$0")/.."

PAYLOAD_FILE="${1:?usage: tools/apns.sh <payload file> [alert|marketing|background|voip]}"
TYPE="${2:-alert}"

# Load tools/.env without overwriting variables that are already set (same rule as the Node tools).
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*([A-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
  key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
  value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
  [ -n "${!key+set}" ] || export "$key=$value"
done < tools/.env
: "${BUNDLE_ID:?set BUNDLE_ID in tools/.env}"
APNS_ENV="${APNS_ENV:-sandbox}"
HOST=$([ "$APNS_ENV" = "production" ] && echo "api.push.apple.com" || echo "api.sandbox.push.apple.com")

JWT=$(node tools/jwt.mjs)
TOKEN="$DEVICE_TOKEN"
TOPIC="$BUNDLE_ID"
PUSH_TYPE="alert"
PRIORITY="10"
EXTRA=()

case "$TYPE" in
  marketing)  PRIORITY="5" ;;
  background) PUSH_TYPE="background"; PRIORITY="5" ;;
  voip)       PUSH_TYPE="voip"; TOPIC="$BUNDLE_ID.voip"; TOKEN="${VOIP_TOKEN:?set VOIP_TOKEN}"; EXTRA=(-H "apns-expiration: 0") ;;
esac
[ -n "${COLLAPSE_ID:-}" ] && EXTRA+=(-H "apns-collapse-id: $COLLAPSE_ID")
[ -n "${EXPIRATION:-}" ] && EXTRA+=(-H "apns-expiration: $EXPIRATION")

# Remove the Simulator-only key; it would be delivered and count toward the 4 KB limit.
BODY=$(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));delete p["Simulator Target Bundle"];process.stdout.write(JSON.stringify(p))' "$PAYLOAD_FILE")

# The 4 KB limit counts bytes, and ${#BODY} counts characters ("–" is 3 bytes).
BYTES=$(printf %s "$BODY" | wc -c | tr -d ' ')
echo "→ $HOST  type=$PUSH_TYPE  priority=$PRIORITY  topic=$TOPIC  bytes=$BYTES"
curl --http2 --silent --show-error --include \
  -H "authorization: bearer $JWT" \
  -H "apns-topic: $TOPIC" \
  -H "apns-push-type: $PUSH_TYPE" \
  -H "apns-priority: $PRIORITY" \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  --data "$BODY" \
  "https://$HOST/3/device/$TOKEN"
echo
# HTTP/2 200 + apns-id = accepted. Sandbox also returns apns-unique-id: paste it into the
# Push Notifications Console → Delivery Log to see what happened on the device.
