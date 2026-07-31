# Solace + CareBridge Firebase setup

The two iOS targets use the same Firebase project. Each app signs in
anonymously, and the survivor creates a random pairing code that the caregiver
enters on the other device.

The real `GoogleService-Info.plist` files are intentionally excluded from Git.
After cloning, download fresh iOS configuration files from Firebase Console
and place them at:

- `Solace/GoogleService-Info.plist` for bundle ID `com.solaceid.app`
- `SolaceCare/GoogleService-Info.plist` for bundle ID `com.solace.care`

Do not paste Firebase or Azure credentials into Swift files or commit them.

Before testing the connection in Firebase Console:

1. Open **Authentication → Sign-in method** and enable **Anonymous**.
2. Create a **Cloud Firestore** database.
3. Deploy or paste the rules from `firestore.rules`.

If the Firebase CLI is installed, run this from the project folder:

```sh
firebase deploy --only firestore:rules
```

Then build and launch both targets:

```sh
xcodebuild -project Solace.xcodeproj -scheme Solace -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Solace.xcodeproj -scheme SolaceCare -destination 'platform=iOS Simulator,name=iPhone 17' build
```

On the survivor device, open **Settings → Connect CareBridge → Create pairing
code**. On the caregiver device, enter that code in the **Connect to Solace**
card. Check-ins, the caregiver feed, SSI summaries, approved care-plan steps,
and the curated daily five then sync through Firestore; the existing App Group
cache continues to make each app usable offline.

For local Azure voice testing, add `SOLACE_AZURE_SPEECH_KEY` to the Run scheme's
Environment Variables in Xcode. Azure voice is optional; the app falls back to
Apple's on-device voice when it is absent. Never ship that subscription key in
the app binary or commit it to the repository.

For physical-device signing, keep the `group.com.solace.shared` App Group
registered in the Apple Developer account if you want same-device App Group
fallback. Firebase sync itself does not depend on the App Group.
