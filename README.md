# Solace

Solace is an accessibility-first iOS companion for people recovering from a
stroke. It turns a one-minute check-in into a small, manageable next step, while
CareBridge gives a care partner a clear view of progress and an easy way to
shape the daily plan.

Built in SwiftUI as two coordinated apps:

- **Solace** — the survivor-facing check-in, activity, safety, and recovery app.
- **SolaceCare** — the care-partner app for check-in history, care-plan steps,
  pairing, and shareable updates.

## Product tour

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/solace-home.png" alt="Solace home screen" width="250"><br><sub>Solace home</sub></td>
    <td align="center"><img src="docs/screenshots/solace-check-in.png" alt="Solace mood check-in" width="250"><br><sub>Low-friction check-in</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/solace-ssi.png" alt="One Small Plan single-session support" width="250"><br><sub>One Small Plan</sub></td>
    <td align="center"><img src="docs/screenshots/carebridge.png" alt="CareBridge care-plan builder" width="250"><br><sub>CareBridge note-to-steps</sub></td>
  </tr>
</table>

## Highlights

- **A calm daily loop:** mood and energy check-ins require no typing, then
  activities are ordered around the person’s values and available energy.
- **Behavioral activation:** small, values-based actions turn a check-in into
  momentum, with a short after-activity reflection to show what helped.
- **One Small Plan:** a guided single-session intervention helps the survivor
  name a hope, choose two realistic actions, plan around an obstacle, and share
  the finished plan with consent.
- **CareBridge:** paste a physical-therapy or clinical note, draft plain-language
  patient steps on device, review and approve them, then arrange the daily five.
  Approved steps can be exported as a care summary or shareable update.
- **Accessibility throughout:** voice-only interaction, answer matching for
  spoken responses, natural read-aloud voice support, one-hand mirroring,
  visual-neglect anchoring, large targets, simple language, haptics, and
  reduced-motion support.
- **Connected when available:** Firebase sync connects the two apps across
  devices, while a local cache keeps the core workflow available offline.

## How the apps connect

```text
Solace ── pairing code ── Firebase Auth + Firestore ── SolaceCare
  │                                                   │
  └──── local cache / App Group fallback ────────────┘
```

The survivor creates a pairing code in **Settings → Connect CareBridge**. The
care partner enters that code in **SolaceCare**. Check-ins, approved care-plan
steps, the daily activity list, and shared summaries sync through Firestore.
Each app also maintains a local cache so a temporary network outage does not
interrupt the experience.

## Run locally

Requirements:

- Xcode 26 or later
- iOS 17 or later
- A Firebase project with Anonymous Authentication and Cloud Firestore enabled

1. Open `Solace.xcodeproj` in Xcode.
2. Download fresh Firebase configuration files for the two bundle IDs and add
   them to the matching target:
   - `Solace/GoogleService-Info.plist` — `com.solaceid.app`
   - `SolaceCare/GoogleService-Info.plist` — `com.solace.care`
3. Deploy the rules in [`firestore.rules`](firestore.rules), then run the
   `Solace` and `SolaceCare` schemes.
4. For same-device fallback, register the
   `group.com.solace.shared` App Group in the Apple Developer account.

Firebase setup details are in [`FIREBASE_SETUP.md`](FIREBASE_SETUP.md).

Optional Azure voice testing is configured only through the Xcode Run scheme:
set `SOLACE_AZURE_SPEECH_KEY` as an environment variable. If it is absent,
Solace uses Apple's on-device voice. The subscription key is never stored in
the source tree.

To build both targets from the command line:

```sh
xcodebuild -resolvePackageDependencies -project Solace.xcodeproj
xcodebuild -project Solace.xcodeproj -scheme Solace -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Solace.xcodeproj -scheme SolaceCare -destination 'generic/platform=iOS Simulator' build
```

## Deployment model

For a real release, the maintainer connects the app to their own Firebase
project before creating the signed archive:

1. Register `com.solaceid.app` and `com.solace.care` as iOS apps in Firebase.
2. Download the two matching configuration files and add them to the Xcode
   targets locally or through a protected build pipeline.
3. Deploy `firestore.rules` to the Firebase project.
4. Archive and sign the apps for TestFlight, the App Store, or managed device
   distribution.

The finished app includes the Firebase configuration it needs. People who
install the deployed app do not add Firebase files or configure a project;
they simply pair Solace and SolaceCare with the in-app pairing code. The public
source repository omits the configuration files so each maintainer can use
their own Firebase project safely.

## Project structure

| Directory or file | Purpose |
| --- | --- |
| `Solace/` | Survivor-facing SwiftUI app |
| `SolaceCare/` | Care-partner SwiftUI app |
| `Shared/` | Shared models, local persistence, pairing, and Firebase sync |
| `SolaceTests/` | Unit tests for app and care-plan behavior |
| `firestore.rules` | Firestore access rules for paired devices |
| `FIREBASE_SETUP.md` | Firebase configuration and device-pairing notes |
