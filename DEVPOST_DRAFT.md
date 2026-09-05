# Solace

## Inspiration

My clinical experience shaped Solace. I saw how stroke recovery continues long after someone leaves the hospital, while survivors may be managing low mood, fatigue, aphasia, motor changes, and the emotional weight of slow progress.

Post-stroke depression is both common and serious, affecting about one in three stroke survivors. It can interfere with recovery and is associated with worse long-term outcomes. Early screening, treatment, and psychosocial support may help prevent or reduce its impact, but many survivors and families still lack consistent, accessible resources after discharge.

Solace was inspired by one question: what if support began with one small, manageable action instead of another complicated form?

## What It Does

Solace is a pair of SwiftUI apps:

- **Solace** provides accessible daily check-ins, fatigue-aware activity suggestions, values-based behavioral activation, a guided Single-Session Intervention, safety resources, and a one-tap way to share a support request.
- **SolaceCare** helps care partners view updates, paste physical-therapy notes, create patient-ready steps, approve care-plan activities, and export care summaries.

The experience supports voice-only interaction, spoken-answer matching, read-aloud support, one-hand mirroring, visual-neglect anchoring, large touch targets, haptics, reduced-motion behavior, and an onboarding recap of the chosen accommodations.

Firebase Authentication and Cloud Firestore connect the two apps across devices when configured. A local cache keeps the core experience available offline, shows the last successful sync, and supports reconnecting without replacing a pairing code.

## How It Was Built

Solace was built solo in Swift and SwiftUI as one Xcode project with two application targets and shared data models.

The project uses:

- SwiftUI for both applications
- Firebase Authentication and Cloud Firestore
- Local persistence and App Group storage
- Network reachability monitoring and offline-first recovery
- Speech recognition and read-aloud voice support
- Azure Speech voice options
- On-device care-plan drafting with an offline fallback
- Local notifications

Care-plan suggestions require caregiver review and approval before appearing in the survivor’s daily plan. The survivor can also send a ready-to-share support request from the safety screen when reaching out is difficult.

## What I Learned

I learned that accessibility must shape the entire product from the beginning. Navigation, language, touch targets, voice support, pacing, and error handling all need to work for people with different recovery experiences.

I also learned that making an experience feel simple requires careful decisions. A one-minute check-in involves thoughtful choices about wording, feedback, visual hierarchy, and what happens when someone is tired, overwhelmed, offline, or unable to speak clearly.

## Challenges

The biggest challenge was supporting different recovery needs without making the app feel clinical or overwhelming. I addressed this through adjustable accessibility settings, fatigue-aware activity selection, values-based recommendations, gentle language, and multiple ways to complete the same interaction.

Another challenge was making care-plan drafting useful while keeping the care partner in control. The solution was to provide on-device suggestions, an offline fallback, explicit caregiver approval, and visible sync/recovery states before any step reaches the survivor.

Solace explores how behavioral science, thoughtful interaction design, and assistive technology can make recovery support feel more human.

## Post–August 7 Updates

The following work was added after August 7 and is the scope I am highlighting for the eligible update period:

- Added an in-app accessibility profile showing the active hand layout, text size, picture cues, voice settings, visual anchor, and system accessibility supports.
- Added native motion-safe navigation and made screen transitions, button feedback, onboarding transitions, and mood selection respect Reduce Motion.
- Added Firebase connection status, last-sync visibility, network reachability handling, and reconnect controls while preserving local use when offline.
- Added pending-change tracking and automatic retry when connectivity returns, so offline edits do not require the survivor to remember to sync them.
- Added an onboarding recap so survivors can review their selected accommodations before entering the app.
- Made the Safety screen’s support-request action functional with a ready-to-share message instead of a placeholder button.
- Added protection against duplicate activity completion from overlapping taps or voice callbacks.
- Added cancellation protection to the tap-along rehabilitation flow so leaving the screen cannot trigger a delayed completion unexpectedly.
- Added a user-controlled 30-second rest pause inside activity sessions for fatigue-aware pacing.
- Improved the browser demo’s accessible motion system and reduced-motion behavior.

## Next Steps

Future work will focus on expanding recovery support without adding pressure or complexity:

- Expand pending sync into a full queued outbox with per-change status and retry history.
- Add richer caregiver acknowledgements, such as “I saw this” and “I’ll check in,” without turning the app into a messaging inbox.
- Add a fuller recovery history with filters for mood, energy, activities, and care-plan steps.
- Continue testing with stroke survivors, care partners, and clinicians to validate language, pacing, and safety workflows.

Solace explores how behavioral science, thoughtful interaction design, and assistive technology can make recovery support feel more human.
