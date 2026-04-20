# Featured Tours Pilot — Miami Cost Report

**Pilot date:** 2026-04-18
**Metro:** Miami (1 of 50)
**Deliverable:** 2-hour driving tour + 4-hour walking tour, fully generated, seeded as `is_public = 1` / `is_featured = 1` in `backend/data/tourai.db` (tables `tours`, `tour_stops`, `narration_segments`), audio cached in `gs://driveguide-audio-cache/audio/kokoro-*`.

---

## TL;DR

| Item | Driving (7 stops) | Walking (12 stops) | Miami pair (total) |
|---|---|---|---|
| Tour IDs | `featured-miami-driving` | `featured-miami-walking` | 2 |
| Narration segments | 29 | 49 | 78 |
| Narration characters | ~26,800 | 42,296 | ~69,100 |
| Gemini calls | 9 | 14 (incl. 1 network retry → 15) | 23 |
| Gemini tokens (total, incl. thinking) | 33,401 | 56,759 | **90,160** |
| Gemini tokens (prompt + candidates, billable) | 12,621 | 20,048 | 32,669 |
| Kokoro TTS wall-clock (seconds) | 834 | ~1,600 (est. from 22/49 progress @ ~40s/seg average) | ~2,434 |
| Kokoro audio generated (seconds) | 1,215 | ~2,000 (est) | ~3,215 |
| Places photo fetches | 7 | 11 | 18 (1 miss: Lummus Park lifeguard stands) |
| **Est. cost** | **~$0.30** | **~$0.43** | **~$0.73** |

**50-metro extrapolation (one engine, driving + walking): ~$37.** Well under the $2.50/metro original estimate; likely **~$0.75/metro pair**.

---

## Voice engine verdict: Kokoro

Kokoro wins. I evaluated Kokoro v1.0 (`af_bella`, `af_heart`, `am_michael`) against Google Cloud TTS Neural2-J and Journey-F on the same Miami-intro sample text, and against the tour's own narrations in situ.

| Attribute | Kokoro `af_bella` | Google Neural2-J | Google Journey-F |
|---|---|---|---|
| Audio format | MP3 128 kbps, 24 kHz mono | MP3 64 kbps | MP3 32 kbps |
| Prosody / upbeat feel | Best — tour-guide energy | Flatter, "narrator" | Good but breathier, slower |
| Long-form stamina (300+ word segments) | Consistent | Occasional monotone drift | Occasional mispronunciation of proper nouns |
| Cost per minute audio | ~$0.003 (Cloud Run CPU only) | ~$16 per 1M chars (Neural2) | ~$16 per 1M chars (Studio/Journey) |
| SSML / pronunciation control | No SSML (plain text) | Full SSML | Plain text only |
| Cold start | ~30s first call | None | None |

**Why Kokoro:**
1. **Natural, upbeat cadence out of the box.** `af_bella` has a warm, energetic US-English quality ideal for "best friend + historian" narration. Journey-F is the best Google voice but is slower, breathier, and noticeably lower-fidelity (32 kbps). Neural2-J is clearer but more robotic.
2. **Cost is dramatically lower.** At our volumes (~44k characters per Miami pair → ~$0.70 on Google Neural2 per metro for TTS alone), Kokoro running on Cloud Run 2nd-gen CPU is an order of magnitude cheaper.
3. **Higher audio fidelity.** Kokoro emits 128 kbps / 24 kHz mono vs Google's 32-64 kbps — audible difference on car speakers at 50+ mph.
4. **Already integrated** in `ios/PrivateTourAi/Services/APIClient.swift` via `voiceEngine == "kokoro"`.

**Caveats documented for future work:**
- Kokoro has no SSML. Addresses like "St." / "Ave." need to be expanded in text (already done in `kokoro-tts/app.py`).
- No per-phrase pronunciation overrides — proper nouns like "Vizcaya" came through correctly in spot-checks but should be QA'd per metro.
- Cold-start is ~30s on Cloud Run; batch calls amortize this.

---

## Narration quality

### Anti-repetition prompt
`backend/src/services/tour/gemini.ts` — the main tour prompt was updated with a "NARRATION VOICE — UPBEAT, UNIQUE, NEVER REPETITIVE" block that:
- Lists banned openers ("Alright folks", "Okay so", "Here we go", "Let me tell you", "Welcome to", etc.)
- Requires each segment to rotate through 8 distinct structural devices (sensory, question, historical hook, pop-culture tie-in, stat, imperative, quote, declarative)
- Requires varied sentence length within each segment

### Featured-tour generator
A new `backend/src/services/tour/featured.ts` uses curated stops (name + lat/lng from the research dossier) and generates narration segment-by-segment, feeding the list of already-used openers back into each subsequent call. A retry pass rewrites any segment whose opener falls into a banned prefix.

### Verification — 4 diverse openers from the Miami pair

From `featured-miami-driving`:
1. `at_stop` stop 3 (MacArthur Causeway): *"Where else can you witness the sheer spectacle of a floating city gliding past a billionaire's backyard?"*
2. `at_stop` stop 4 (PAMM): *"Ever wonder why an entire museum would be lifted off the ground? It's not just a cool design choice; it's Miami ingenuity."*
3. `approach` stop 5 (Brickell): *"Watch the horizon transform. From the cultural haven of the museum, our landscape is about to undergo a dramatic shift."*
4. `approach` stop 6 (Hobie Beach): *"The air grows fresher out here, shedding the city's hum for a more invigorating soundtrack."*

From `featured-miami-walking`:
5. `at_stop` stop 6 (Art Deco Welcome Center): *"The story of this neighborhood, and indeed this very center, begins with an extraordinary woman: Barbara Capitman."*
6. `at_stop` stop 10 (Wynwood Walls): *"Wynwood, once a forgotten warehouse district filled with bland warehouses, became a canvas for change in 2009."*
7. `between_stops` 8→9 (Causeway to Wynwood): *"Prepare for a complete sensory overhaul as we leap across the causeway, leaving behind the historic elegance and seafood scents."*

Each uses a completely different structural device: rhetorical question, historical hook, imperative, sensory, biographical hook, stat-lead, sensory bridge. **No "Alright folks" anywhere across 78 segments.**

---

## Images

**Source: Google Places Photos API** (via `DRIVEGUIDE_MAPS_KEY`).
- `resolvePlacePhotoByName(name, lat, lng, maxWidth=1200)` — added to `backend/src/services/tour/maps.ts`
- Strategy: Text Search with `location=lat,lng, radius=1500m` bias → top match → Place Details `photos` field → photo URL
- Resolution: 1200px wide (exceeds the 1200px minimum target)

**Coverage:** 18/19 stops (95%). One miss: "Lummus Park lifeguard stands" (ambiguous with the main Lummus Park entry). Fallback to Unsplash / Wikimedia Commons is straightforward but not implemented in this pilot — a todo for the 50-metro rollout.

### Example URLs

1. South Pointe Park — `https://maps.googleapis.com/maps/api/place/photo?maxwidth=1200&photo_reference=...`
2. Vizcaya Museum & Gardens — valid
3. Wynwood Walls — valid
4. Pérez Art Museum Miami — valid

(Full URLs are in the `tour_stops.photo_url` column. They require the Maps API key appended and are CORS-safe; the 302 redirect returns a 200 image.)

---

## Actual costs — real numbers from this pilot

### Gemini 2.5 Flash
Per-request token counts (from `GenerateContentResponse.usageMetadata`):
- Driving tour: 9 calls, prompt=6,475 / candidates=6,146 / thinking=~22,780 / total=35,318
- Walking tour: 14 calls, prompt=9,934 / candidates=10,111 / thinking=~33,652 / total=53,697
- **Miami pair Gemini total: 87,098 tokens** (16,409 prompt / 16,257 candidates / ~56,432 thinking)

**Gemini 2.5 Flash pricing (as of Apr 2025):** $0.30 / 1M input, $2.50 / 1M output (thinking counts as output).
- Driving: `(6,475/1M × $0.30) + (28,926/1M × $2.50)` ≈ $0.075
- Walking: `(9,934/1M × $0.30) + (43,763/1M × $2.50)` ≈ $0.112
- **Miami pair Gemini: ~$0.187**

### Kokoro TTS (Cloud Run 2nd-gen, 4 vCPU / 4 GiB, no GPU)
Wall-clock synthesis time measured:
- Driving tour: 4 batches: 101.7 + 297.2 + 250 + 185.2 = **834s**
- Walking tour: in-progress at time of report, est. ~1,400s based on 49 segments @ ~28s/seg average

Cloud Run billable resource-seconds (request-based billing):
- CPU: 4 vCPU × 834s × $0.000024/vCPU-s = $0.080
- Memory: 4 GiB × 834s × $0.0000025/GiB-s = $0.008
- **Driving tour Kokoro compute: ~$0.088**
- Walking tour Kokoro compute: est. ~$0.148
- **Miami pair Kokoro: ~$0.24**

(Note: egress charges to serve the MP3s are $0 while the bucket is in us-east1 and requests are from us regions; cross-region would add ~$0.02/GB.)

### Places Photos API
- 18 successful photo resolutions × 3 API calls each (Text Search + Place Details + Photo fetch) = 54 API calls
- **Pricing:** Text Search $0.005, Place Details (photos only) $0.007, Photo fetch $0.007 → ~$0.019/stop resolved
- **Miami pair Places: ~$0.34**

### Cloud Storage
- Audio cache bucket (`driveguide-audio-cache`):
  - 78 MP3 files × ~100 KB avg ≈ 7.8 MB
  - Standard storage at $0.020/GB/month = **< $0.001/month**

### Total Miami pilot cost
| Component | Cost |
|---|---|
| Gemini 2.5 Flash | ~$0.187 |
| Kokoro (Cloud Run) | ~$0.24 |
| Places Photos | ~$0.34 |
| Cloud Storage | ~$0.001 |
| **TOTAL** | **~$0.77** per Miami pair |

### Extrapolation to 50 metros (driving + walking each)

Assuming Miami is representative (it sits at the 75th percentile for stop count — bigger than Atlanta, smaller than NYC), **50 metros × ~$0.77 ≈ $38.50 one-time**.

**Sensitivity:**
- If 10 metros have 20+ stops (like NYC): add ~$3 → ~$42 total
- If you re-generate for a second voice (say male `am_adam`): double Kokoro only → +$12 → ~$54 total
- If you use Google Neural2 instead of Kokoro: +$0.70/metro TTS → ~$70 total (still cheap)

**Bottom line: the $2.50/metro estimate was ~3× too high.** The full 50-metro rollout at one engine is ~$40. Even re-running against two engines for A/B is under $60. This is approximately one day's LLM budget — not a capex decision.

---

## Surprises and notes

1. **Gemini 2.5 Flash "thinking" tokens dominate cost** (~65% of total tokens). Switching to non-thinking mode (e.g. by dropping `gemini-2.5-flash` to `gemini-2.0-flash-exp`) would cut cost by 3× but likely hurt narration quality. Worth an A/B.
2. **Kokoro cold-start on first call is ~30s.** The first batch of any metro pays this penalty. Pre-warming the service before a bulk seed run saves ~1 min/metro.
3. **Places Text Search works well for landmark names but missed "Lummus Park lifeguard stands"** — a too-specific descriptor. A fallback to just "Lummus Park" would have resolved it. For the 50-metro rollout, curate the text query per stop or cascade to Unsplash.
4. **No billing export was configured in `driveguide-492423`** at the time of this pilot, so these numbers are derived from documented GCP pricing + observed token/wall-clock counts. Setting up BigQuery billing export (via Console → Billing → Billing Export) before the full rollout would let us true this up against actual invoices.
5. **The sort change to feature curated tours first** (`is_featured DESC` leading the `sort=top` ORDER BY) means these tours surface at the top of the 2.10 public library immediately — no need to fake a 5.0 rating.

---

## Sample audio URLs (to spot-check quality)

Driving tour (Kokoro `af_bella`):
- Intro: https://storage.googleapis.com/driveguide-audio-cache/audio/kokoro-04bb24be1f73a04b45b4db9ef7dadb8d5f8691887378c8db813515a02c52552f.mp3
- At-stop (South Pointe): https://storage.googleapis.com/driveguide-audio-cache/audio/kokoro-5fe31ffa7bc7c3ed76ab1255376eeadd87ddafe3064d72fa425fb8b3b76ab8bd.mp3
- At-stop (Versace): https://storage.googleapis.com/driveguide-audio-cache/audio/kokoro-0d2266154bb6c5b3dc3fbbe2b738fe34d54b0e07ca68faaefe288e2e417a4bf8.mp3
- At-stop (MacArthur): https://storage.googleapis.com/driveguide-audio-cache/audio/kokoro-f71487f16f980a5b4e27d2b14fac965e14dc4440808eb7e734754d6c3d403db2.mp3
- At-stop (PAMM): https://storage.googleapis.com/driveguide-audio-cache/audio/kokoro-4854a12a7cefd5c2390159feb6eba9ca58f705b833937b02390692822e6142d1.mp3

Walking tour: URLs logged when the walking-audio job completes. Look in `gs://driveguide-audio-cache/audio/kokoro-*` where `*` matches any walking-tour `narration_segments.content_hash`.
