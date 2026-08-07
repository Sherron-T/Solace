# Solace browser demo

This is a lightweight, shareable showcase of the Solace and CareBridge experience. It is designed for judges who need to understand the product without installing an iOS build.

## What the demo shows

- A survivor check-in based on mood and energy
- Behavioral activation through a guided single-session intervention
- Voice-only mode, AI answer matching, Azure voice support, visual neglect anchoring, and one-hand mirroring
- Safety support with clear next actions
- CareBridge's clinical-note-to-patient-step workflow
- Approval, sync-back to Solace, and care-summary export

The demo uses local browser state so it works without an account or API key. Firebase sync remains implemented in the native SwiftUI apps and is described in the main project README.

## Run locally

From the project folder:

```bash
python3 -m http.server 8765 --directory demo
```

Then open [http://localhost:8765](http://localhost:8765).

## Long-term use

The `demo/` folder is static and can be hosted by GitHub Pages, Netlify, Cloudflare Pages, or any standard web host. It does not depend on the iOS simulator, TestFlight, Firebase credentials, or a third-party emulator.
