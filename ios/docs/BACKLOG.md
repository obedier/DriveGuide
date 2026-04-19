# wAIpoint — Post-2.x Backlog

Ideas parked for the release **after** the 2.7 → 2.11 feature bundle (UX wins, offline, share/passenger, community, route-aware narration). These are higher-effort, higher-reward bets that deserve focused execution rather than getting stuffed into the current release train.

---

## 1. Voice personas + multilingual generation

**What.** Replace the generic narrator with 3-4 distinct persona prompts driving the TTS: "Gary the history buff," "Kim the architecture nerd," "Carlos the Miami local." Each persona gets its own writing style in the Gemini prompt, not just a different TTS voice. Add Spanish / French / Mandarin generation for international tourists.

**Why.** Premium tour-guide apps live or die on *voice*. Right now every tour sounds the same; real brands like Rick Steves sell on the personality of the narrator. Multilingual is table-stakes for the tourist segment (our core user) and opens up non-English app-store markets.

**Sizing.** Medium. Mostly backend prompt engineering + a voice-persona selector UI on HomeView. Google TTS already supports all four languages.

**Risks.** Quality control — a bad persona is worse than a generic one. Need internal tasting sessions before ship.

---

## 5. Photo moments + post-trip "wrapped" recap

**What.** At each stop, prompt the user (optional) to take a photo. After the tour, generate a shareable "Your Miami Tour" recap card — photos + stop names + a highlight stat ("You covered 12 miles, saw 8 stops, heard 23 minutes of narration"). Shareable image optimized for Instagram Stories / TikTok.

**Why.** Organic growth. Every shared recap card is a billboard for the app. Spotify Wrapped and Strava year-in-review are the blueprint — recap mechanics drive 10-100x the social footprint of the underlying product.

**Sizing.** Medium. Photo capture + storage per stop is easy; the recap image composition (SwiftUI → PDF/PNG → share sheet) is the real work. Needs a designer pass for the share card.

**Risks.** Photos are memory-heavy — need a storage policy (keep locally, upload optional).

---

## 8. Monetization rethink — trip passes

**What.** In addition to the current subscription, add "Trip Pass" — $4.99 for 7 days unlimited in one metro area. Non-overlapping with the monthly/annual sub; geofenced to the purchased metro.

**Why.** Tourists don't subscribe. They want a one-shot purchase for a 3-day Vegas trip. The current sub converts locals and repeat travelers but bounces tourists — the exact segment most willing to pay premium for a guided experience. Trip Pass pairs naturally with the #3 offline download feature.

**Sizing.** Medium. New StoreKit product, geofence logic in `SubscriptionService`, paywall copy. RevenueCat already supports non-subscription products.

**Risks.** Cannibalization of the annual sub. A/B test on install funnels before rolling wide.

---

## 9. CarPlay + Apple Watch

**What.**
- CarPlay: minimal audio-player scene with play/pause/skip + current segment title + ETA to next stop.
- Apple Watch complication + simple app: shows "Next stop: 1.2mi — [stop name]" and a play/pause control.

**Why.** CarPlay is table-stakes for any app that claims "driving tour." Current absence is a common 1-3 star review reason on similar apps. Watch complication is cheap review-bait and genuinely useful for passengers + walking tours.

**Sizing.** Large. CarPlay needs a separate `CPTemplateApplicationScene`, Apple review (CarPlay entitlement), and a restricted UI vocabulary. Watch is medium — WatchConnectivity to pipe state from phone.

**Risks.** CarPlay entitlement approval is gated by Apple and can take weeks. Start the entitlement request early.

---

## Process notes

- Each backlog item gets its own `/orchestrate feature` pass when prioritized.
- Re-evaluate priority after the 2.7-2.11 bundle ships and we see App Store review trends + subscription conversion data.
- **Pre-generated featured tours** (the separate research initiative already in flight) is its own track — not in the backlog because research lands first, then we decide shape.
