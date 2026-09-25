# secrets/

Put private files here. Everything in this folder except this README is git-ignored.

| File | Where it comes from | Used by |
|---|---|---|
| `AuthKey_<KEYID>.p8` | developer.apple.com ▸ Keys ▸ APNs key (download once) | `tools/apns.sh`, `tools/registry-server.mjs`, Firebase upload |
| `GoogleService-Info.plist` | Firebase ▸ Project settings ▸ Your apps ▸ iOS | the app (Part 3) |
| `firebase-service-account.json` | Firebase ▸ Project settings ▸ Service accounts | `tools/fcm.mjs` |

Never paste the contents of these files into chats, issues, or screenshots.
