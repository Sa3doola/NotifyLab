# iOS Notifications, End to End — Appendix: Cheat Sheet and Release Checklist

*One page to bookmark: every limit, payload key, header and error code from the series, the commands that test them, a plain-words glossary, and the checklist to run before you ship.*

---

This page collects everything from Parts 0 to 7 that you'll want to look up again. Where Apple's documentation and my own tests disagreed, it says so. The rule I followed throughout: follow the docs, and know what the servers actually do.

> Everything this page refers to is in the NotifyLab repo.

---

## Limits

![Table of limits. Payload for alert and background pushes: 4 KB, 4,096 bytes, past it 413 PayloadTooLarge; the sandbox took up to 5,120 bytes in my tests, don't rely on it. VoIP payload: 5 KB, 5,120 bytes. apns-collapse-id: 64 bytes, past it 400 InvalidCollapseId. apns-expiration: 30 days at most. Kept while the phone is offline: one notification per app, usually the newest. Pending local notifications: 64 per app; iOS keeps the soonest 64 and silently drops the rest. Repeating time-interval trigger: at least 60 seconds, or the app crashes creating it. Service Extension: about 30 seconds, then serviceExtensionTimeWillExpire. Silent push: about 30 seconds to run, 2 to 3 per hour at most. Attachments: image 10 MB, audio 5 MB, video 50 MB. Provider JWT: reuse for 20 to 60 minutes. The .p8 key never expires; a .p12 certificate lasts 1 year. APNs keys per team: 2 team-scoped per environment, 200 topic-specific. FCM token: 270 days without contact on Android, no timer on iOS.](tables/pA-limits.png)
*Every number the series relies on. The payload row is the only place my tests and Apple's docs disagreed.*

## The payload

![Table of payload keys. Inside aps: alert with title, subtitle and body, the text the user sees (Part 4). sound, default or a sound file in the app (Part 4). badge, the number on the app icon, 0 removes it (Part 1). category, picks the buttons and the Content Extension (Parts 1 and 5). thread-id, groups notifications (Part 4). mutable-content 1, lets the Service Extension change it (Part 5). content-available 1, wakes the app in the background, and for a silent push it's the only key in aps (Part 4). interruption-level, passive, active, time-sensitive or critical (Parts 1 and 7). relevance-score, 0 to 1, the sort order in the Scheduled Summary (Parts 4 and 7). Your own keys go outside aps, like orderId, sender and conversationId (Parts 4 and 5). Simulator Target Bundle is only for the Simulator, when you drag a file onto it or use simctl push; remove it before sending (Part 7).](tables/pA-payload-keys.png)
*What goes in a payload. Apple reads `aps`; everything outside it is yours.*

## The headers

![Table of APNs headers and the value for each kind of push. apns-push-type: alert for order updates and marketing, background for a silent sync. apns-priority: 10 now, 5 when it suits the battery, 1 never wakes the device; 10 for order updates, 5 for marketing, 5 for silent syncs, where Apple's docs call 10 an error. apns-topic: the bundle ID, plus .voip for VoIP. apns-expiration: keep trying until this UNIX time, at most 30 days; 0 means try once. apns-collapse-id: a newer push with the same ID replaces the older one, at most 64 bytes. apns-id: your UUID for the request, optional.](tables/p4-headers.png)
*The six request headers (Part 4). VoIP pushes use `voip`, topic `<bundle ID>.voip`, priority 10 and expiration 0 (Part 6).*

The response brings two more: **`apns-id`** (yours, or one APNs made up), and in the sandbox only **`apns-unique-id`**, which you paste into the Delivery Log (Part 7).

## Errors

![Table of error responses and what to do. APNs: 400 BadDeviceToken, a token from the other environment, check sandbox versus production and don't delete it. 400 DeviceTokenNotForTopic, the token belongs to another topic such as a VoIP token without .voip, fix the topic or push type. 400 TopicDisallowed, the key can't push to that bundle ID. 400 MissingDeviceToken, the token variable is empty. 400 InvalidCollapseId, longer than 64 bytes. 400 InvalidPushType, unknown push type. 403 InvalidProviderToken, the JWT doesn't match a key, run check-key. 403 ExpiredProviderToken, the JWT is over an hour old. 410 Unregistered or ExpiredToken, the token is dead, delete it unless it was re-uploaded after the timestamp. 413 PayloadTooLarge, send IDs. 429 TooManyProviderTokenUpdates, cache the JWT. 429 TooManyRequests, too many pushes to one device, slow down. 500 and 503, retry with backoff. FCM HTTP v1: 400 INVALID_ARGUMENT, a bad token or payload, check the payload first. 401 THIRD_PARTY_AUTH_ERROR, the APNs key in Firebase is missing or wrong. 403 SENDER_ID_MISMATCH, another Firebase project. 404 UNREGISTERED, delete the token. 429 QUOTA_EXCEEDED, back off. 500 and 503, retry with backoff.](tables/pA-errors.png)
*Every error the series met. The reasons in **bold** are ones I triggered myself while writing it; the rest come from Apple's and Firebase's documentation.*

The rule of thumb for your server: **retry** `429`, `500` and `503` with backoff; **delete the token** on `410` and FCM's `404`; **fix the request** for everything else. Never delete a token on `400 BadDeviceToken`. It usually means the wrong environment, not a dead token.

## What works where

![Table of testing tools. Dragging an .apns file onto the Simulator or simctl push: no Service Extension, silent pushes refused, no VoIP. A real sandbox push to the Simulator: the Service Extension runs without thumbnails, silent pushes get 200 but don't wake the app, VoIP is delivered but the call ends at once. A real push to an iPhone: everything works. curl, Postman, the Push Notifications Console and Firebase's test message behave like the device they target. The Delivery Log shows whether APNs delivered it; log stream and Console.app show whether the phone received it.](tables/p7-test-tools.png)
*Test layout on the Simulator, and everything else on a device (Part 7).*

## The commands

Everything runs from the `NotifyLab/` folder. Variables set in the shell override `tools/.env`.

```bash
node tools/check-key.mjs                                   # is my key right? no device needed
./tools/apns.sh payloads/order-shipped.apns                # alert, priority 10
COLLAPSE_ID=order-1042 ./tools/apns.sh payloads/order-out-for-delivery.apns
EXPIRATION=0 ./tools/apns.sh payloads/order-shipped.apns   # try once, don't store
./tools/apns.sh payloads/marketing-passive.apns marketing  # passive, priority 5
./tools/apns.sh payloads/silent-sync.apns background       # silent, priority 5
./tools/apns.sh payloads/driver-message.apns               # communication notification
./tools/apns.sh payloads/voip-call.json voip               # PushKit → CallKit, on a device
node tools/fcm.mjs payloads/order-shipped.apns             # the same, through FCM HTTP v1
node tools/jwt.mjs                                         # a JWT for Postman, valid for an hour
node tools/registry-server.mjs                             # the demo token server, port 8080
xcrun simctl push booted payloads/order-shipped.apns       # Simulator only: no key, no server
./tools/set-bundle-prefix.sh com.yourname                  # switch every ID to yours
```

---

## Release checklist

Run through this before the first release, and again whenever you change signing, keys or your push server. The part in brackets explains each item.

**In the app**

- The **exported** build says `aps-environment` → `production`. Check it with `codesign` on the `.app` inside the `.ipa`. (Part 2)
- The App ID has every capability you use: Push Notifications, Time Sensitive, Communication Notifications, and App Groups for the app **and** both extensions. (Part 2)
- The extensions' minimum iOS version isn't newer than the app's. (Part 5)
- The notification delegate is set, and categories are registered, before `didFinishLaunching` returns. (Part 1)
- `willPresent` returns what the app should show when it's open. (Part 1)
- Permission is asked next to the feature, not at launch. A denial leads to a deep link to Settings, not another prompt. (Part 1)
- Local reminders stay under 64 pending, with a rolling window. (Part 1)
- `registerForRemoteNotifications()` runs on every launch. Tokens are uploaded when they change, plus a weekly check-in. (Part 3)
- The app syncs on launch, and doesn't rely on silent pushes alone. (Part 4)
- The Service Extension always calls its content handler, and falls back in `serviceExtensionTimeWillExpire()`. (Part 5)
- Every VoIP push reports a call to CallKit, first. CallKit is off for users in mainland China, with a fallback. (Part 6)
- Images, silent pushes and calls were tested on a real device, in both a Debug and a TestFlight build. (Part 7)

**On your server**

- The `.p8` lives in a secret manager. There's one key per environment, and a plan to rotate: new key first, then revoke the old one. (Part 2)
- The JWT is cached and reused for 20 to 60 minutes. (Part 2)
- Requests use HTTP/2 over reused connections. The trust store includes *USERTrust RSA Certification Authority*. (Parts 2, 4)
- Every token is stored with its environment, and sent to the matching APNs host. (Parts 2, 3)
- Dead tokens are deleted on `410` and FCM's `404`, and silent devices are pruned. (Part 3)
- One row per device, not per user. Logging out detaches the device from the user. (Part 3)
- Order-style updates use collapse IDs. Anything that goes stale has an expiration. (Part 4)
- Priority 10 only for what the user needs now; 5 for marketing and silent pushes. (Part 4)
- Payloads stay under 4 KB and carry IDs, not personal data. (Part 4)
- Marketing pushes need their own in-app opt-in, and an in-app opt-out, checked before every send (App Review Guideline 4.5.4). (Part 4)
- Every send logs its `apns-id`, status and environment. Opens are counted by the app. (Part 7)

**If you use Firebase**

- The `.p8` is uploaded to both the development and production slots. (Part 3)
- `GoogleService-Info.plist` comes from the right Firebase project. (Part 3)
- If swizzling is off, the app passes the APNs token to `Messaging.messaging().apnsToken`. (Part 3)
- The server uses FCM HTTP v1. The legacy API is gone. (Part 4)

---

## Glossary

- **APNs**: Apple Push Notification service, the servers that deliver every remote push to Apple devices.
- **Device token**: the address of one app, on one device, in one environment. No fixed length. (Part 3)
- **FCM token**: Firebase's address for the same app, built from the APNs token. (Part 3)
- **VoIP token**: a separate address for calls, from PushKit. (Part 6)
- **Sandbox / production**: APNs's two environments. Debug builds use sandbox; TestFlight and the App Store use production. (Part 2)
- **Topic**: the bundle ID a push is for, sent as `apns-topic`. (Part 2)
- **Capability**: a feature you switch on for a target in Xcode, like Push Notifications. (Part 2)
- **Entitlement**: the signed permission a capability becomes, like `aps-environment`. (Part 2)
- **Provisioning profile**: Apple's file that says which entitlements your signed app may use. (Part 2)
- **`.p8` key**: the file your server uses to prove it's allowed to send pushes for your team. (Part 2)
- **JWT**: the short, signed token your server makes from the `.p8` and sends with each request. (Part 2)
- **Category**: a named set of buttons for a notification. (Part 1)
- **Interruption level**: how loud a notification is allowed to be: passive, active, time-sensitive or critical. (Parts 1, 7)
- **Thread ID**: groups notifications together. **Collapse ID**: replaces an older one with a newer one. (Part 4)
- **Silent push**: a push with nothing to show that wakes the app in the background. (Part 4)
- **Service Extension**: your code that changes a notification before it's shown. (Part 5)
- **Content Extension**: your UI shown when the user long-presses a notification. (Part 5)
- **Communication notification**: a notification shown as a message from a person, with their photo. (Part 5)
- **PushKit / CallKit**: the frameworks that receive VoIP pushes and show the system call screen. (Part 6)
- **Focus / Scheduled Summary**: the user's filters for who may interrupt them, and when. (Part 7)
- **Delivery Log**: Apple's web tool that shows whether a sandbox push reached the device. (Part 7)

---

That's the series. If a notification still doesn't arrive, start at the top of Part 7's seven checks and go down until one fails. It's almost always one of them.

**Back to the start: Part 0, Which notification do you need?**
