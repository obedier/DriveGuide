# App Store Connect metadata — wAIpoint 2.16

Drafts for each ASC field. All under their respective character limits.

## What's New in this Version (≤4,000 chars)

```
Location-aware driving tours are here.

• Start a tour from anywhere — when you're far from the first stop, wAIpoint now plays a dynamically generated "drive-to" narration and then seamlessly hands off to the pre-written tour narration the moment you arrive. A status banner shows live distance and ETA.

• Adaptive follow-ups — on long drives we space 2-3 mini bridges across the ride so you never sit in silence. Each one uses a different device: a fact, a sensory hook, a pop-culture tie.

• Accurate ETAs powered by Google Directions — real road-based time, not straight-line estimates.

• Featured tours — hand-curated showcase tours you can play for free. Miami's Golden Hour (2-hour drive) and Miami's Canvas (4-hour walk) are live now. More cities coming.

• Gold-standard visual treatment — featured tours carry a gold border + sparkle pill so you can tell them apart from user-shared tours.

• Instant playback for featured tours — pre-generated audio, no "Preparing your tour" delay.

• Make it your own — one tap clones any featured or community tour into your library so you can edit stops and narration for your personal version.

• Segment list during navigation — a new menu in the player shows every segment with progress indicators. Tap any to skip to it.

• Small UX fixes: community visibility toggle now sticks on first tap; community tours load reliably; Start/End toggles in Advanced search fit cleanly in portrait.
```

## Promotional Text (≤170 chars, can be updated between releases without review)

```
Location-aware audio tours that know when you're still on the road and when you've arrived. Featured tours of Miami are free. Make any tour your own.
```

## Subtitle (≤30 chars)

```
AI tours that know where you are
```

## Keywords (≤100 chars, comma-separated)

```
audio tour,city tour,travel,road trip,AI,driving,miami,walking tour,podcast,narration,gps
```
(99 chars)

## Description (≤4,000 chars)

```
wAIpoint is your private AI tour guide. Open the app, pick a city or featured tour, and drive or walk — the narration follows you.

FEATURED TOURS (free)
• Hand-curated showcase tours with professionally-written narration, premium voice, and photos of every stop.
• Miami's Golden Hour — a 2-hour driving tour across the causeways, Wynwood, and Vizcaya at golden hour.
• Miami's Canvas — a 4-hour walking tour through South Beach's Art Deco district and Wynwood's murals.
• Gold badge on every featured tour so you know you're getting the full experience.

LOCATION-AWARE NARRATION
• Start a tour from anywhere — we know the difference between "at your house" and "at the first stop."
• If you're still driving, wAIpoint plays a live introduction while you travel, then seamlessly switches to the pre-written tour the moment you arrive.
• Follow-up mini bridges keep long drives entertaining without ever repeating the same opening.

CUSTOM TOURS (subscription)
• Type any city, set a duration, pick themes (history, food, scenic, hidden gems, architecture…) and we'll generate a bespoke tour in minutes.
• Works by car, on foot, by bike, or even by boat.
• Save unlimited tours to your library and re-play any time.

MAKE ANY TOUR YOUR OWN
• Tap a featured or community tour, then "Make it your own" — we clone it into your library so you can edit stops, tweak narration, and re-share.

BUILT FOR THE DRIVE
• Accurate arrival detection via turn-by-turn navigation.
• Segment list with tap-to-skip.
• Offline download so tours play without a signal.
• Premium Google TTS voice — warm, natural, not robotic.
• Passenger Mode for the back seat.

SHARE WITH FRIENDS
• Every tour gets a shareable link. If your friends have the app, they open right in it; if not, they can preview on the web.
• Community tab surfaces the highest-rated public tours, sorted by Top / Recent / Trending.

Subscription unlocks unlimited custom tour generation, voice picker, offline downloads. Featured tours remain free forever.
```

## Support URL

`https://waipoint.o11r.com/support`

## Marketing URL (optional)

`https://waipoint.o11r.com`

## Privacy Policy URL

`https://waipoint.o11r.com/privacy`

## Categories

- Primary: Travel
- Secondary: Entertainment (alt: Navigation)

## Age Rating

4+ (no restricted content; user-generated tours are pre-moderated opt-in public — flag in Review Notes)

## Copyright

`© 2026 Helwan Holdings LLC`

## Review Notes (for Apple reviewer)

```
wAIpoint generates personalized audio tours via AI. For this review:
- Featured tours (Miami's Golden Hour, Miami's Canvas) are fully pre-generated and playable without any account — no login needed to verify this flow.
- Custom tour generation requires sign-in (Apple/Google/Email). Test account: wAIpoint-Review / ReviewerMagic2026! (email: reviewer@waipoint.app)
- The app uses Core Location to play narration at the right stop on the tour. Request is clearly scoped in the prompt.
- Premium subscription ($4.99/mo or $29.99/yr) via StoreKit 2. Verify in sandbox.
- Community tours are opt-in public and currently admin-moderated (manual review for V1).
- Location-aware "drive-to" narration uses Gemini + Google TTS backends; no user data beyond lat/lng is sent.
```

## Export Compliance

- Uses standard HTTPS (TLS) — no proprietary encryption.
- Eligible for the streamlined export compliance exemption.
- Answer: Yes, uses encryption. No, only standard / exempt.

## Attestation (after setting all above, before submit)

- Content Rights — "does your app contain... third-party content?" → Yes, we use public landmark data (non-exclusive).
- Advertising Identifier — No (we do not use IDFA).
- Kids category — No.
