# wAIpoint 2.7 → 2.11 Feature Roadmap

Five features sequenced by dependency and risk. Each ships as its own TestFlight/App Store release so we get real-user feedback before the next lands.

---

## Sequencing rationale

```
2.7  UX quick wins           (lowest risk, fastest feedback)
2.8  Offline tour download   (foundational: tour+audio serialization)
2.9  Share link + Passenger  (builds on 2.8's serialization)
2.10 Community tour library  (backend + browse UX)
2.11 Route-aware narration   (deepest refactor — save for last)
```

The research initiative for **pre-generated featured tours** runs in parallel and lands into whichever release is ready first — likely slots into 2.8 or 2.9 alongside offline mode.

---

## 2.7 — UX quick wins

**Scope.**
1. **Continue your last tour** chip on Home — if a tour was generated in the last 24h, surface a "Continue: Miami Art Deco" button at the top of Home. State is already persisted; this is a UI surfacer.
2. **Preview audio snippet** on `PreviewCard` — a 5-second sample of the narrator's voice so users commit with their ears. Generate on-demand from segment 0's first 1-2 sentences via existing `generateSegmentAudio`.
3. **Tap-to-change** on verified-address line at `HomeView.swift:283` — currently silently truncates with `.lineLimit(1)`. Add a chevron + tap gesture that focuses the search field and clears the location.

**Tests.**
- Unit: Home VM exposes `lastTour` based on persisted timestamp; button visibility test.
- Unit: PreviewCard shows play button when preview audio is available.
- UI: tapping verified-address resets the state as expected.

**Risk.** Low. All three are localized HomeView changes, no backend.

**ETA.** 1 day coding + 0.5 day test + ship.

---

## 2.8 — Offline tour download

**Scope.**
1. **New `OfflineTourStore`** (actor) that serializes `Tour` JSON + all segment audio Data into a single directory per tour under `.documentsDirectory/offline-tours/<tourId>/`.
2. **UI:** "Download for offline" button on `TourDetailView`. Progress bar while audio prefetches. Downloaded badge when complete.
3. **Playback:** `AudioPlayerService.downloadSegment` checks `OfflineTourStore` before hitting network. Existing disk cache path is the natural seam.
4. **"Downloaded Tours" list** in a new screen accessible from Home (or reuse existing profile menu).
5. **Eviction:** LRU policy capped at ~500MB or user-configurable in settings.

**Tests.**
- Unit: round-trip serialize/deserialize a Tour through `OfflineTourStore`.
- Unit: `AudioPlayerService` reads from offline store when present, falls back to cache/network.
- Integration: airplane-mode scenario — after download, playback works with network disabled (manual QA on device).

**Risk.** Medium. Storage policy decisions (size cap, eviction) need a product call. Backend change minimal (maybe a `completed_tours` endpoint if we want cloud sync of the offline list).

**ETA.** 3-4 days coding + 1 day test + ship.

---

## 2.9 — Share link + Passenger Mode

**Scope.**
1. **Universal Links** (`waipoint.app/tour/<shareId>`) wired into `AppDelegate`/`SceneDelegate` and `Info.plist` `associated-domains`.
2. **`GET /v1/tours/shared/:shareId`** is already in the backend (used by `APIClient.getSharedTour`). Confirm it returns a minimal tour shape sharers can publish without auth.
3. **Share sheet** on `TourDetailView` produces a tour link + preview image.
4. **`PassengerView`** — new screen reachable from a shared link OR toggled from `TourDetailView`:
   - Full-screen, bigger type, no map
   - Manual previous/next/play controls (no GPS triggering)
   - Progress bar across segments
   - Option to enter fullscreen text-read mode for accessibility
5. **Offline integration:** shared tours that were previously downloaded open instantly.

**Tests.**
- Unit: URL parsing for `/tour/<id>` and `/passenger/<id>` routes.
- Unit: `PassengerViewModel` advances/reverses through segments without GPS events.
- UI: share sheet + deep-link round-trip.

**Risk.** Medium. Universal Links need an `apple-app-site-association` file on the domain (one-time infra). Passenger mode is a new UI surface — needs design polish pass.

**ETA.** 3-4 days.

---

## 2.10 — Community tour library

**Scope.**
1. **Backend:** `GET /v1/tours/public` with filters (`metro`, `sort=top|recent|trending`, `limit`). Returns tour summaries + rating stats. New DB index on `is_public` + `avg_rating`.
2. **Public/private flag** per tour — tour creator opts in via a toggle on `TourDetailView`.
3. **Browse UI:** new "Explore" tab (or Home section). Shows top-rated tours per metro with rating, stops count, duration, thumbnail.
4. **Try-it flow:** tapping a public tour goes to `PreviewDetailView` → can be generated/cloned into the user's library, or played directly via PassengerView if audio is available.

**Tests.**
- Backend: TDD the `/tours/public` endpoint with test fixtures.
- Unit: `ExploreViewModel` paginates and filters correctly.
- UI: rating display, try-it flow reaches PreviewDetailView.

**Risk.** Medium-high. Moderation — public tours mean we're now a UGC surface. Need a "report tour" flow and a back-end flag-for-review queue before this ships to production. Ratings abuse (fake 5-stars) is a risk but can be deferred.

**ETA.** 4-5 days + moderation tooling.

---

## 2.11 — Route-aware narration

**Scope.**
1. **New `RouteAwarePlaybackCoordinator`** sitting between `FerrostarNavigationService` and `TourPlaybackService`:
   - Subscribes to Ferrostar's step stream (next instruction, distance remaining).
   - When a step completes near a stop's trigger point, play that stop's segment.
   - When a step is about to fire a turn, optionally duck narration audio briefly and play the turn cue.
2. **Narration adaptation:** enrich the Gemini prompt with the route context — "narrate as if directing a driver who will turn left onto Flagler in 300ft." Optional for v1; can ship the coordinator first with the existing narration.
3. **Audio ducking:** AVAudioSession mix with turn-by-turn voice so the user hears both without talking over each other.
4. **Fallback:** if Ferrostar is not active (manual play from TourDetailView), coordinator is a passthrough.

**Tests.**
- Unit: Coordinator fakes Ferrostar step events + verifies the correct segment is played.
- Unit: Ducking logic — when turn cue fires, narration volume dips and recovers.
- Integration: Ferrostar + real playback in simulator with a canned route (the existing `FerrostarIntegrationTests` is the seed).

**Risk.** High. Deep coupling across three services (Navigation, Ferrostar, Playback). Audio session management is iOS's most-fragile surface. Worth saving for last so the platform beneath is stable.

**ETA.** 5-7 days + a week of QA.

---

## Cross-cutting

- **Every release** includes a version bump in `project.yml`, a `TestFlight/en-US/WhatToTest.en-US.txt` update, and the CLI upload flow documented in the ASC upload memory.
- **Test coverage** stays above 80% for services; view tests stay above 60%.
- **Each release** gets at least 48h in TestFlight with internal testers before promoting to App Store review.
