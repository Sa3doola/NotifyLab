# NotifyLab

The demo app for the series **"iOS Notifications, End to End."**
One SwiftUI app with five tabs, each a real product scenario, and two notification extensions.

| Tab | Scenario | Shows |
|---|---|---|
| **Status** | Settings inspector | Permission, provisional, every `UNNotificationSettings` value, Low Power Mode, Background App Refresh, a shared event log |
| **Habits** | Habit tracker | Local notifications, Done / Snooze / Note actions, the 64-pending limit (rolling window), interruption levels |
| **Orders** | E-commerce | APNs + FCM tokens, order updates by push, deep links, Service Extension image, Content Extension card, a driver message as a communication notification (sender photo + Reply) |
| **Sync** | Silent update | `content-available` background pushes |
| **Calls** | Calling app | PushKit VoIP token, CallKit incoming call |

Targets: `NotifyLab` (iOS 17+, Swift 6), `NotifyLabService` (Notification Service Extension), `NotifyLabContent` (Notification Content Extension). They share data through the App Group `group.<prefix>.notifylab`. Every ID comes from one setting, `BUNDLE_ID_PREFIX` in `project.yml`.

## Run it in 2 minutes (no Apple account needed)

```bash
open NotifyLab.xcodeproj        # run the NotifyLab scheme on any iOS 17+ Simulator
```

Then send a push to the Simulator without any server:

```bash
xcrun simctl push booted payloads/order-shipped.apns
```

Or drag any `.apns` file from `payloads/` onto the Simulator window.

> The project is generated from `project.yml`. After editing it, run `xcodegen generate`.

## Make it yours (real pushes)

1. **IDs.** One command switches every ID (bundle IDs, App Group, payloads, tool configs) and regenerates the project:
   ```bash
   ./tools/set-bundle-prefix.sh com.yourname
   ```
   Then set `DEVELOPMENT_TEAM` in `project.yml` to your Team ID and run `xcodegen generate`. (Picking your team in Xcode also works, until the next `xcodegen generate` resets it.)
2. **APNs key.** Go to developer.apple.com ▸ Keys ▸ **+** ▸ Apple Push Notifications service. Download the `.p8` (you can only do this once) into `secrets/`.
3. **Env file.** `cp tools/.env.example tools/.env` and fill in `TEAM_ID`, `KEY_ID`, `KEY_PATH`, `BUNDLE_ID`, and `DEVICE_TOKEN` (copy it from the Orders tab).
4. **Check the key** (no device needed): `node tools/check-key.mjs` should print `400 BadDeviceToken ✓ key accepted` for sandbox and production. `403 InvalidProviderToken` means `KEY_ID`, `TEAM_ID` or `KEY_PATH` is wrong.
5. **Send:**

```bash
./tools/apns.sh payloads/order-shipped.apns              # alert → Service Extension adds the image
./tools/apns.sh payloads/driver-message.apns             # communication notification: driver's photo + Reply
./tools/apns.sh payloads/marketing-passive.apns marketing # passive, priority 5
./tools/apns.sh payloads/silent-sync.apns background      # silent push → Sync tab
./tools/apns.sh payloads/voip-call.json voip              # PushKit → CallKit call screen (device)
```

The Simulator gets a **real sandbox token** (Xcode 14+ on Apple silicon or T2 Macs), so `apns.sh` works there too.

Shell variables override `tools/.env`, so you can change one thing per send:

```bash
COLLAPSE_ID=order-1042 ./tools/apns.sh payloads/order-out-for-delivery.apns   # replaces the last order update
EXPIRATION=0 ./tools/apns.sh payloads/order-shipped.apns                      # try once, don't store
```

### FCM (optional)

1. `project.yml` already links **FirebaseMessaging**. Download `GoogleService-Info.plist` from Firebase ▸ Project settings ▸ Your apps, put it in `secrets/`, and build again (a build step copies it into the app). Without it, the app still builds and FCM stays off.
2. Upload your `.p8` in Firebase ▸ Project settings ▸ Cloud Messaging ▸ Apple app configuration.
3. Put the service-account JSON in `secrets/` and set `FCM_SERVICE_ACCOUNT` and `FCM_TOKEN` in `tools/.env`, then:

```bash
node tools/fcm.mjs payloads/order-shipped.apns
```

`FirebaseBridge.swift` switches FCM on when the plist is in the app, and logs a message to the Status tab when it isn't.

### Your own token server (optional)

```bash
node tools/registry-server.mjs      # POST /devices, GET /devices, POST /send
```

In the app, go to Orders ▸ "Your server" and enter `http://localhost:8080` (Simulator) or your Mac's IP (device).
`POST /send {"file":"payloads/order-shipped.apns"}` sends to every stored device. Before sending it prunes devices that haven't checked in for 60 days; after, it deletes tokens APNs answers with `410` (unless the device re-uploaded the token after APNs' timestamp).

### Postman

Import `tools/NotifyLab.postman_collection.json`. Set **Settings ▸ HTTP version ▸ HTTP/2**, because APNs refuses HTTP/1.1. Paste the output of `node tools/jwt.mjs` into the `jwt` variable.

## What works where

| Scenario | `simctl push` / drag & drop | Real sandbox push to Simulator | iPhone |
|---|---|---|---|
| Local habit reminders + actions | n/a (scheduled in-app) | n/a | ✅ |
| Alert push, deep link | ✅ | ✅ | ✅ |
| Content Extension (long-press card, Call driver) | ✅ | ✅ | ✅ |
| Service Extension (image) | ❌ doesn't run | ⚠️ runs and attaches, but the Simulator can't draw the thumbnail | ✅ |
| Communication notification (sender photo, Reply) | ❌ doesn't run (needs the Service Extension) | not tested | ✅ |
| Silent push | ❌ rejected: "no user visible content" | ⚠️ APNs accepts (200), app not woken | ✅ |
| VoIP (PushKit) | ❌ | ⚠️ token + delivery work, the app reports the call, but CallKit ends it at once (no call screen) | ✅ |
| Critical alerts | ❌ | ❌ | needs Apple's entitlement |

Also worth knowing: the Simulator's APNs token was 80 bytes (160 hex), the iPhone's 32 bytes (64 hex). Never assume a length.

Verified with Xcode 27, the iOS 27 Simulator and an iPhone on iOS 27.

## Repo map

```
NotifyLab/App/                 AppDelegate (token callbacks, silent push), AppModel
NotifyLab/Notifications/       Permission, HabitScheduler, Categories, Router, PushTokenStore,
                               FirebaseBridge, VoIPService, OrderStore (+ SyncStore)
NotifyLab/Features/            The five tabs
NotifyLabService/              Notification Service Extension
NotifyLabContent/              Notification Content Extension (SwiftUI card)
Shared/                        Identifiers + App Group store, compiled into all three targets
payloads/                      .apns files
tools/                         apns.sh, check-key.mjs, jwt.mjs, fcm.mjs, registry-server.mjs, Postman collection
articles/                      The tutorial drafts, figures and screenshots
```

## License

The code is under the [MIT License](LICENSE). The articles, figures, tables and screenshots in `articles/` are under [CC BY 4.0](articles/LICENSE.md): share and adapt them freely, with credit.
