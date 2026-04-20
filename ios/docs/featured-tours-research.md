# wAIpoint Featured Tours — Research Dossier + Benchmark Framework

> **Companions:** [tour-scoring-spec.md](./tour-scoring-spec.md) defines the scoring engine. [gold-standard-tours.md](./gold-standard-tours.md) is the 10-tour calibration set.

## 0. Strategic frame

**wAIpoint's core product is personalized adaptive tour generation from user input.** Featured tours are **not** the product. They're four things, in decreasing order of importance:

1. **Calibration exemplars** for the scoring engine — the quality bar every AI-generated tour is measured against.
2. **Training signal** — structured gold examples that tune weights, intents, and stop attributes.
3. **Free conversion hooks** — the public-facing standard of quality users experience before they pay.
4. **Showcase** — a visible answer to "is the tour AI any good?"

**One schema, one scoring model, two populations.** Curated "featured" tours and custom on-the-fly tours use the same stop schema (see §1), the same dimension set, and the same scoring formulas (see [tour-scoring-spec.md](./tour-scoring-spec.md)). Curated tours are just very high-scoring exemplars. This keeps the quality bar portable and lets the generator learn from the curated set.

**Free vs paid.**

- **Free.** A small curated set of benchmark tours in major cities. Users experience them without a subscription. This is the product's *public standard of quality*, not a freebie.
- **Paid.** Custom tours generated from user input — constraints, preferences, time budget, intent, dynamic conditions (weather, traffic, closures). This is the real product.

**What this doc must do.** Help the system *explain* quality in structured terms — not just display a 4.9-star rating. Every stop has attributes the generator can reason over. Every tour has a score breakdown the UI can verbalize. The goal is that the app can say "this version is less famous but better matches your request for hidden gems" — and mean it literally.

---

## 1. Stop-selection methodology (structured)

We optimize for the "you have to do this one thing" tier — iconic, photogenic, story-rich, geographically logical. The editorial intuition is unchanged. What's new is making that intuition *machine-readable*.

### 1.1 Stop attribute schema

Every stop in every tour — curated or custom — carries this structured attribute block. Full TypeScript interface lives in [tour-scoring-spec.md §6](./tour-scoring-spec.md#6-persisted-json-schema).

| Attribute | Values | Notes |
|---|---|---|
| `stop_type` | `icon` · `viewpoint` · `neighborhood` · `museum` · `food` · `park` · `scenic_drive` · `waterfront` · `other` | Drives variety_balance scoring |
| `iconicity_score` | 0-10 | Global recognizability |
| `scenic_payoff_score` | 0-10 | Visual "wow" delivered per visit |
| `story_significance_score` | 0-10 | Density of narratable meaning |
| `tourist_popularity_score` | 0-10 | Crowd + visitor-volume indicator |
| `local_authenticity_score` | 0-10 | Whether locals actually go here |
| `dwell_time_minutes_estimate` | integer | Realistic time needed |
| `access_friction` | `low` · `medium` · `high` | Getting there |
| `parking_friction` | `low` · `medium` · `high` · `not_applicable` | Car-tour relevant |
| `walking_burden` | `none` · `light` · `moderate` · `heavy` | Walking-tour relevant |
| `family_friendliness` | 0-10 | Kid appeal and safety |
| `weather_sensitivity` | `none` · `moderate` · `high` | Outdoor exposure |
| `best_time_of_day` | `morning` · `midday` · `afternoon` · `golden_hour` · `night` · `any` | Drives time_of_day_fit |
| `day_night_suitability` | `day_only` · `both` · `night_only` | Gates time-based intents |
| `reservation_risk` | `none` · `low` · `high` | Timed entry hazards |
| `crowding_risk` | `low` · `medium` · `high` | Experience-quality factor |
| `accessibility_notes` | text | Wheelchair / mobility |
| `photo_value` | 0-10 | Photographic payoff |
| `wow_per_minute` | 0-10 | Emotional payoff / dwell time |
| `cluster_id` | string | Groups geographically adjacent stops |
| `adjacent_compatible_stops` | string[] | Stop ids that route naturally together |

### 1.2 Signature moments — the city-level abstraction

Every city has a fixed set of **signature moments** — named peaks we want every tour to be able to draw from. These are the atoms tours are built from, and the vocabulary the generator uses when explaining tradeoffs.

Standard signature-moment slots per city:

- **Best skyline reveal** — the moment a new arrival first "sees" the city
- **Best sunset stop** — highest-payoff golden-hour position
- **Best short wow stop** — highest wow_per_minute, under 10 min dwell
- **Best scenic drive segment** — highest-scoring continuous stretch of road
- **Best coffee/food pause** — the perfect mid-tour dwell
- **Best local texture moment** — the neighborhood ground-truth for this city
- **Best ending point** — narrative-flow-maximizing finale
- **Best worth-the-detour** — the "add this if you have 20 extra minutes" stop

The top-10 city entries (§3) include the full signature-moments table. The remaining 40 cities (§4) get a condensed version as part of the structured header.

### 1.3 Evidence tags (retained from v0)

Used in the attraction tables below as quick provenance:

- `TA` — TripAdvisor "Things to Do" top-ranked
- `GM` — Google Maps top-rated / high-review-volume
- `LP` — Lonely Planet featured
- `Fodor` — Fodor's / Condé Nast Traveler "best of"
- `NYT36` — NYT "36 Hours in …" series
- `Reddit` — r/travel or r/<city> consensus
- `Social` — high Instagram/TikTok hashtag volume
- `Viator` — top-selling Viator / GetYourGuide inclusion (revealed-preference)

---

## 2. Source strategy — six source families

Current sources are strong for **discovery** but insufficient for **rigorous scoring**. The big missing layer is operational realism + graph-based route logic. Going forward, sources are organized into six families with explicit jobs.

### 2.1 Popularity / mainstream demand
**Sources:** TripAdvisor, Google Maps, Viator, GetYourGuide, Airbnb Experiences bookings.
**Job:** Tell us what users *actually* visit and book. Surface floor for iconicity_score and tourist_popularity_score. Revealed-preference is the strongest popularity signal.
**Known weakness:** Biased toward first-time tourists; underrepresents local favorites and hidden gems.

### 2.2 Editorial / taste / curation
**Sources:** NYT "36 Hours in …", Lonely Planet, Fodor's, Condé Nast Traveler, Afar, The Guardian Travel.
**Job:** Tell us what discerning travelers *should* experience. Ceiling for story_significance_score; primary input for narrative_flow design.
**Known weakness:** Slow to update; sometimes over-corrects against mainstream (tries too hard to be "authentic").

### 2.3 Local texture / friction / sentiment
**Sources:** Reddit (r/travel, r/<city>, city-specific subs), recent review text on Google/TripAdvisor, local blogs, Substack city newsletters.
**Job:** Tell us what *current* ground truth is. Primary input for local_authenticity_score, crowding_risk, and real friction (opening-hour quirks, scam risks, line lengths).
**Known weakness:** Unstructured; requires careful text extraction to be useful.

### 2.4 Visual / scenic / social proof
**Sources:** Instagram hashtag counts, TikTok place-tag volume, Flickr geotag density, Unsplash city presence.
**Job:** Photo_value, scenic_payoff_score. Where do people actually take and share photos?
**Known weakness:** Overweights novelty/trending spots; tracks the selfie aesthetic more than the scenic aesthetic.

### 2.5 Operational realism — the currently under-developed layer
**Sources:** Google Maps Routes / Distance Matrix API, Places API, official venue sites (hours, closures, ticketing), parking APIs, transit APIs, weather APIs.
**Job:** This is the *missing* layer. It turns a list of attractions into a realistic, schedulable tour. Without it, tours that look great on paper fail in reality.

Specific needs:

- Real driving ETAs with traffic-band (morning/midday/evening) — feeds `time_realism` and `geographic_coherence`.
- Walking distances on real networks, not straight-line — feeds `walking_burden` and `time_realism`.
- Timed-entry requirements (Colosseum, Sagrada Família, Vatican, Sistine) — feeds `reservation_risk`.
- Seasonal closures (Vizcaya hours vary; Japanese gardens close in winter) — feeds `weather_sensitivity` and `access_friction`.
- Accessibility data (step counts, ramp availability) — feeds `accessibility`.
- Parking availability near stops — feeds `parking_friction`.

**Action item.** Operational-realism sources need to be integrated *before* the scoring engine can score custom tours credibly. Curated tours can be hand-scored; generated tours cannot.

### 2.6 Internal annotations — the most important source over time
**Sources:** Our own curator edits, user-tour completion data, favorite/skip rates, in-app feedback, ratings from completed tours.
**Job:** Once enough usage accumulates, our own structured judgments become the highest-quality signal — because they are stored in the exact shape the scoring engine uses.

Internal annotations override external signals when they conflict. A stop may score iconicity 8 from external data but be locally known to be "tourist-trap disappointing" — our curators should be able to mark it, and the scoring engine should respect that mark.

---

## 3. Per-city structure

Each city entry has four subsections:

- **A. City summary** — 1-2 sentence blurb + city touring strengths + best-fit use cases (e.g. *strongest for driving + sunset + architecture; weak for family*).
- **B. Gold-standard stop graph** — the top benchmark stops with structured attributes, cluster IDs, signature-moments table, route-compatibility notes.
- **C. Benchmark tours** — carefully selected gold-standard tours for calibration. Each tagged with target user type and intent tags.
- **D. Scoring metadata** — the tour-level score breakdowns per [tour-scoring-spec.md](./tour-scoring-spec.md).

### Status legend

- ✅ **Full (v2)** = full new schema — stop graph + signature moments + benchmark tours + scoring metadata
- 🔹 **Header + legacy** = structured header (summary + signature moments + clusters) above existing v1 attraction data and tour prose
- ⬜ **Placeholder** = name only, not yet researched

**Depth at this writing:**

- Top 10 cities (NYC, LA, SF, Chicago, Miami, London, Paris, Rome, Barcelona, Tokyo) → ✅ Full (v2)
- Remaining 40 cities → 🔹 Header + legacy

---

## 4. Scoring-to-generation feedback (city-doc-relevant summary)

The per-city data in this doc is not just reference — it feeds the generation pipeline. Full spec in [tour-scoring-spec.md §8](./tour-scoring-spec.md#8-scoring-to-generation-feedback-loop). Summary:

1. **Candidate generation.** For a user request, generate N candidate tours per city from this stop graph.
2. **Reranking.** Score against Layer A + user intent. Pick the highest-scoring candidate that passes the absolute-quality gate.
3. **Constraint balancing.** Maximize one dimension subject to a floor on another ("maximize scenic_payoff subject to duration_realism ≥ 8").
4. **Tradeoff explanation.** Every shown tour carries human-readable explanations derived from the score breakdown — "this version gives up the Vatican to create a stronger Trastevere finish."
5. **Iterative refinement.** When the top candidate is borderline, run one refinement pass (swap a stop, reorder, shift time), re-score, keep if improved.
6. **Feedback loop.** Compare user completion / skip / favorite rates against benchmark expectations; retune weights quarterly.

---

## 5. Free-hook strategy

The curated tours below are the product's **public standard of quality**. Several ship as free benchmark tours in major cities. Proposed merchandising slots:

- "Best First Tour in Miami" → Causeway Miami (Tour 10 in [gold-standard-tours.md](./gold-standard-tours.md))
- "2-Hour Scenic SF Drive" → Golden Hour Bay Loop (Tour 3)
- "Romantic Sunset LA Drive" → Mulholland to the Pacific (Tour 1)
- "Classic NYC Intro Walk" → Manhattan Classics (Tour 6)
- "Best Family Tour in Chicago" or DC → National Mall for Kids (Tour 8)
- "Rome in an Afternoon" → Centro Storico Classics (Tour 2)
- "Paris After Dark" → Right Bank After Dark (Tour 7)
- "Tokyo Like a Local" → Shimokitazawa Drift (Tour 9)

Free tours are positioned as *"this is what wAIpoint tours feel like"* — not as a teaser. The paid product is tour *generation from your input*, not access to more curated tours.

---

# PART 2 — CITY DOSSIERS

---

# UNITED STATES

---

## 1. New York City ✅ (v2)

### A. City summary

The most filmed, photographed, and mythologized city on earth — Manhattan's skyline, Central Park, Times Square, and the Statue of Liberty form a five-borough film set where almost every block carries pop-culture weight.

- **Strongest for:** first-time walking, architecture, food-heavy, photo-heavy, romantic evening.
- **Weak for:** scenic driving (Manhattan traffic), pure-sunset experiences (limited west-view access from the core).
- **Unique strength:** density of canonical stops per mile — walking tours deliver extraordinary variety in 3 mi.

### B. Gold-standard stop graph

**Top 15 attractions (evidence and coordinates):**

| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Statue of Liberty + Ellis Island | New York Harbor | 40.6892 | -74.0445 | Global symbol of America; the immigrant arrival story | TA, GM, LP, Viator, Social |
| 2 | Central Park (Bethesda Terrace + Bow Bridge) | Manhattan | 40.7739 | -73.9712 | 843-acre urban Eden, Bethesda Terrace is NY's most filmed spot | TA, GM, NYT36, Social |
| 3 | Times Square | Midtown | 40.7580 | -73.9855 | Neon-saturated crossroads of the world; bucket-list once | TA, GM, Viator |
| 4 | Empire State Building | Midtown | 40.7484 | -73.9857 | Art-deco icon; the skyline view NY pioneered | TA, GM, LP, Social |
| 5 | Top of the Rock / 30 Rock | Midtown | 40.7587 | -73.9787 | Best view because it *includes* the Empire State | TA, GM, NYT36 |
| 6 | Brooklyn Bridge (DUMBO side) | Brooklyn/Manhattan | 40.7061 | -73.9969 | Iconic 1883 cable walk; Manhattan skyline framed | TA, GM, Social, NYT36 |
| 7 | 9/11 Memorial & One World Observatory | Financial District | 40.7115 | -74.0134 | Emotionally essential; reflecting pools + tallest US tower | TA, GM, LP |
| 8 | The High Line | Chelsea/Meatpacking | 40.7480 | -74.0048 | Reclaimed elevated rail turned linear park; a modern icon | TA, GM, NYT36, Social |
| 9 | Metropolitan Museum of Art | Upper East Side | 40.7794 | -73.9632 | One of the world's great encyclopedic museums; 'Met steps' fame | TA, GM, LP |
| 10 | Washington Square Park + Greenwich Village | Greenwich Village | 40.7308 | -73.9973 | NYU arch, street performers, the bohemian NY of legend | TA, NYT36, Social |
| 11 | Rockefeller Center + Saks / St. Patrick's | Midtown | 40.7587 | -73.9787 | Ice rink in winter, Christmas tree, Today Show plaza | TA, GM, Social |
| 12 | SoHo / Little Italy / Chinatown loop | Downtown Manhattan | 40.7233 | -74.0021 | Cast-iron SoHo + Canal St energy; best eating blocks in NYC | TA, Reddit, NYT36 |
| 13 | Grand Central Terminal | Midtown | 40.7527 | -73.9772 | Beaux-arts cathedral of transit; whispering gallery | TA, GM, LP |
| 14 | DUMBO / Brooklyn Bridge Park | Brooklyn | 40.7033 | -73.9881 | Washington St bridge framing = most Instagrammed NY view | GM, Social, NYT36 |
| 15 | Flatiron Building + Madison Square Park | Flatiron | 40.7411 | -73.9897 | Architecture icon; Shake Shack's original flagship | TA, Social |

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | walking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Grand Central | icon | 9 | 8 | 10 | 20 | light | any | nyc_midtown |
| Times Square | icon | 10 | 6 | 7 | 15 | light | any | nyc_midtown |
| The High Line | park | 9 | 9 | 8 | 45 | moderate | afternoon | nyc_chelsea |
| Washington Sq Park | neighborhood | 8 | 7 | 8 | 20 | light | any | nyc_village |
| SoHo cast-iron | neighborhood | 8 | 8 | 8 | 25 | light | any | nyc_downtown |
| Brooklyn Bridge walkway | icon | 10 | 10 | 9 | 30 | moderate | golden_hour | nyc_bridge |
| Statue of Liberty | icon | 10 | 9 | 10 | 120 | light | any | nyc_harbor |
| Top of the Rock | viewpoint | 9 | 10 | 7 | 60 | light | golden_hour | nyc_midtown |
| Central Park (Bethesda) | park | 9 | 9 | 9 | 45 | moderate | afternoon | nyc_cp |
| DUMBO / Jane's Carousel | viewpoint | 9 | 10 | 7 | 30 | moderate | golden_hour | nyc_bridge |
| 9/11 Memorial | icon | 9 | 7 | 10 | 45 | light | morning | nyc_downtown |
| Met Museum | museum | 9 | 7 | 10 | 120 | light | any | nyc_uptown |

**Clusters:** `nyc_midtown` · `nyc_chelsea` · `nyc_village` · `nyc_downtown` · `nyc_bridge` · `nyc_harbor` · `nyc_cp` · `nyc_uptown`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Brooklyn Bridge pedestrian walkway midpoint |
| Best sunset stop | DUMBO / Brooklyn Bridge Park (Main St) |
| Best short wow | Grand Central main concourse |
| Best scenic drive segment | West Side Highway northbound at dusk |
| Best coffee/food pause | Chelsea Market (Los Tacos No. 1) |
| Best local texture | SoHo → Little Italy → Chinatown walking corridor |
| Best ending point | Brooklyn Bridge midpoint at golden hour |
| Best worth-the-detour | Top of the Rock at blue hour |

### C. Benchmark tours

#### Tour NYC-1 — "Manhattan Classics" (4h walking) [GOLD]

See full benchmark with per-stop attributes and score breakdown in [gold-standard-tours.md — Tour 6](./gold-standard-tours.md#tour-6--manhattan-classics). Target user: first-time NYC visitor. Intent tags: `first_time_highlights`, `photo_heavy`, `architecture`. **`tour_absolute` = 92.0 · first_time fit = 96**.

#### Tour NYC-2 — "Manhattan in Motion" (2h driving)

*Traffic-aware route avoiding midtown gridlock; emphasizes skyline vantages from the West Side Highway and bridges. Best 8-11am Sunday, or evening after 7pm.*

Intent: `scenic_sunset` (evening variant) · `minimal_walking` · `efficient_short`.

1. **Brooklyn Bridge Park / Pier 1** (40.7003, -73.9967) — start with the canonical skyline photo.
2. Cross **Brooklyn Bridge** into Manhattan (~1 mi).
3. **FDR Drive South** past South Street Seaport → **Battery Park** (40.7033, -74.0170) quick pull-up for Statue of Liberty view (~2 mi).
4. **One World Trade / 9/11 Memorial** drive-by on West St (~1 mi).
5. **West Side Highway northbound** — continuous Hudson views past Chelsea Piers, The Vessel (40.7537, -74.0022) (~3 mi).
6. **Riverside Drive** up to **Grant's Tomb / Riverside Church** (40.8136, -73.9629) (~4 mi, scenic Hudson corridor).
7. Cross through Central Park via **86th St Transverse** → **Fifth Avenue southbound** past the Met, the Frick, Central Park East (~3 mi).
8. End at **Columbus Circle / Central Park South** (40.7680, -73.9819) — Time Warner Center, horse carriages, classic NY finale.

### D. Scoring metadata

**NYC-1 (Manhattan Classics):** `tour_absolute = 92.0` · iconic 9.5 · geographic 9.5 · time_realism 8.0 · narrative 9.5 · scenic 9.0 · variety 9.5 · usability 8.5. Primary intent `first_time_highlights` = 96. **Final (hybrid) = 93.6**. Full breakdown in [gold-standard-tours.md — Tour 6](./gold-standard-tours.md#tour-6--manhattan-classics).

**NYC-2 (Manhattan in Motion):** `tour_absolute ≈ 82` · iconic 8.5 · geographic 9.0 · time_realism 7.0 (NYC traffic risk) · narrative 8.0 · scenic 9.0 · variety 7.5 · usability 7.0. Primary intent `scenic_sunset` = 84 (evening only). **Final (pure_curation) = 82**.

---

#### Tour NYC-3 — "Midtown to the Village" (4h walking, alternate)

*Dense iconic core, ~3.5 miles total, south-running so sun is behind you. Food pauses built in. Note: the gold tour (NYC-1) is this route's stronger sibling — this alternate emphasizes food and village texture over bridge finale.*

Intent: `food_heavy`, `local_flavor`, `first_time_highlights` (soft).

1. **Grand Central Terminal** (40.7527, -73.9772) — start inside the main concourse.
2. **Bryant Park + NY Public Library lions** (40.7536, -73.9832).
3. **Times Square** (40.7580, -73.9855) — cross and keep moving.
4. **The High Line** southern entry at Gansevoort St (40.7398, -74.0084), walk through Chelsea Market.
5. ☕ **Chelsea Market** (40.7424, -74.0061) — food hall pause.
6. **Washington Square Park** (40.7308, -73.9973) — arch and fountain.
7. **SoHo cast-iron district** (Prince & Greene Sts, 40.7244, -73.9985).
8. **Lombardi's / Prince Street Pizza pause** (40.7223, -73.9946).
9. **Little Italy → Chinatown** via Mulberry and Mott Sts (40.7157, -73.9970).
10. **Brooklyn Bridge pedestrian walkway** entrance (40.7126, -73.9993).

**NYC-3 score:** `tour_absolute ≈ 88` · iconic 8.5 · geographic 9.5 · time_realism 8.0 · narrative 8.5 · scenic 8.0 · variety 9.5 · usability 8.5. Primary intent `food_heavy` = 88. **Final (hybrid, food_heavy) = 88**.

---

## 2. Los Angeles ✅ (v2)

### A. City summary

A 500-sq-mile movie set where every neighborhood has a cinematic identity — from Venice Beach's boardwalk chaos to the Hollywood Sign, Griffith Observatory, and the Pacific-facing cliffs of Malibu. LA is the defining car city, which makes it tailor-made for the driving tour.

- **Strongest for:** iconic driving, scenic sunset, architecture (mid-century + contemporary), first-time highlights.
- **Weak for:** walking (low density; requires clusters + rideshare between them), food-heavy tours in a compact area.
- **Unique strength:** the hills-to-ocean descent is a single-session emotional arc you can't get in any other US city.

### B. Gold-standard stop graph

| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Griffith Observatory | Los Feliz | 34.1184 | -118.3004 | Best skyline + Hollywood Sign view in the city; La La Land finale | TA, GM, NYT36, Social |
| 2 | Hollywood Sign (Lake Hollywood Park) | Hollywood Hills | 34.1342 | -118.3215 | Most recognized sign in the world | TA, GM, Social |
| 3 | Santa Monica Pier | Santa Monica | 34.0086 | -118.4977 | End of Route 66; Ferris wheel over the Pacific | TA, GM, Viator |
| 4 | Venice Beach Boardwalk | Venice | 33.9850 | -118.4695 | Skate plaza, Muscle Beach, street carnival | TA, Social, Reddit |
| 5 | Getty Center | Brentwood | 34.0780 | -118.4741 | Richard Meier architecture + free art + views of the basin | TA, GM, LP, NYT36 |
| 6 | Walk of Fame / TCL Chinese Theatre | Hollywood Blvd | 34.1022 | -118.3413 | Handprints, stars, neon-lit Hollywood kitsch | TA, GM, Viator |
| 7 | Runyon Canyon | Hollywood Hills | 34.1107 | -118.3487 | The LA celeb hike; skyline + sign in one view | Reddit, Social |
| 8 | Rodeo Drive / Beverly Hills | Beverly Hills | 34.0696 | -118.4050 | Palm-lined luxury strip; photo-op certainty | TA, Social |
| 9 | The Broad + Walt Disney Concert Hall | Downtown | 34.0545 | -118.2505 | Free contemporary art + Gehry titanium swoops | TA, GM, NYT36 |
| 10 | Malibu — El Matador + PCH | Malibu | 34.0376 | -118.8761 | Sea-stack beach; Pacific Coast Highway scenic drive | Social, Fodor |
| 11 | Grand Central Market | Downtown | 34.0505 | -118.2489 | 1917 food hall, Eggslut + McConnell's — DTLA's eating hub | TA, NYT36, Social |
| 12 | LACMA — Urban Light | Miracle Mile | 34.0636 | -118.3592 | 202 restored streetlamps = top LA photo | TA, Social |
| 13 | Echo Park Lake + Silver Lake | East side | 34.0777 | -118.2600 | Swan boats, skyline, LA's 'indie' east | NYT36, Reddit, Social |
| 14 | Dodger Stadium | Elysian Park | 34.0739 | -118.2400 | Oldest MLB park west of Mississippi; sunset game = bucket list | TA, GM |
| 15 | Universal Studios / Hollywood Bowl | Universal City | 34.1381 | -118.3534 | Tour + summer concert venue; optional but iconic | TA, GM |

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | parking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Griffith Observatory | viewpoint | 9 | 10 | 8 | 25 | medium | afternoon | la_hills |
| Mulholland overlook | viewpoint | 7 | 9 | 6 | 10 | medium | afternoon | la_hills |
| Sunset Strip drive-by | neighborhood | 8 | 6 | 9 | 10 | medium | afternoon | la_central |
| Rodeo Drive / Beverly Hills | neighborhood | 8 | 6 | 6 | 10 | low | any | la_central |
| Santa Monica Pier | icon | 9 | 9 | 7 | 20 | high | golden_hour | la_coast |
| Venice Boardwalk | neighborhood | 8 | 7 | 7 | 20 | medium | golden_hour | la_coast |
| Getty Center | museum | 9 | 9 | 9 | 120 | low | any | la_westside |
| El Matador Beach | viewpoint | 7 | 10 | 4 | 20 | medium | golden_hour | la_malibu |
| The Broad + Disney Hall | icon | 8 | 9 | 9 | 60 | medium | any | la_dtla |
| Grand Central Market | food | 7 | 6 | 8 | 45 | medium | midday | la_dtla |

**Clusters:** `la_hills` · `la_central` · `la_coast` · `la_westside` · `la_malibu` · `la_dtla`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Griffith Observatory west lawn |
| Best sunset stop | Santa Monica Pier at ferris-wheel light-up |
| Best short wow | Urban Light at LACMA |
| Best scenic drive segment | Sunset Blvd from Hollywood to Pacific Palisades |
| Best coffee/food pause | Grand Central Market (Eggslut) |
| Best local texture | Echo Park Lake at weekend afternoon |
| Best ending point | Santa Monica Pier or Venice Boardwalk |
| Best worth-the-detour | Getty Center tram ride + terrace |

### C. Benchmark tours

#### Tour LA-1 — "Mulholland to the Pacific" (2h driving) [GOLD]

See full benchmark with per-stop attributes and score breakdown in [gold-standard-tours.md — Tour 1](./gold-standard-tours.md#tour-1--mulholland-to-the-pacific). Target user: first-time LA visitor wanting the canonical hills-to-ocean drive. Intent tags: `first_time_highlights`, `scenic_sunset`, `minimal_walking` (soft). **`tour_absolute` = 90.0 · scenic_sunset fit = 93**.

Route summary:

### 2-Hour Driving Tour — "Mulholland to the Pacific"
*The defining LA drive: hills → Sunset → beach. Best 2-5pm so you hit Santa Monica at golden hour.*

1. **Griffith Observatory** (34.1184, -118.3004) — start at the skyline view.
2. **Mulholland Drive scenic overlooks** (34.1342, -118.3750) — ~15 min westbound ridge drive (~6 mi).
3. Descend **Laurel Canyon Blvd** → **Sunset Strip** (34.0900, -118.3854) past Whisky a Go Go, Chateau Marmont (~4 mi).
4. **Beverly Hills — Rodeo Drive loop** (34.0696, -118.4050) (~2 mi).
5. **Sunset Blvd west** through Bel Air curves to the ocean at **Pacific Palisades** (~6 mi).
6. **PCH northbound** to **El Matador Beach** (34.0376, -118.8761) optional pull-off (~10 mi).
7. **PCH southbound** back to **Santa Monica Pier** (34.0086, -118.4977) for sunset (~15 mi).
8. End at **Venice Boardwalk** (33.9850, -118.4695) (~2 mi).

#### Tour LA-2 — "Hollywood + Griffith Sunset" (4h, two-cluster walk + rideshare)

*LA is hard to walk end-to-end; this is a two-cluster walk requiring a short drive or rideshare between. If strictly walking: pick the Hollywood cluster only and extend with Melrose.*

Intent: `first_time_highlights`, `scenic_sunset`, `photo_heavy`.

**Cluster A — Hollywood Core (2 hrs):**
1. **TCL Chinese Theatre / Walk of Fame** (34.1022, -118.3413).
2. **Dolby Theatre / Hollywood & Highland** (34.1019, -118.3387).
3. **El Capitan Theatre** (34.1018, -118.3396).
4. **Musso & Frank Grill** (34.1015, -118.3327) — oldest Hollywood restaurant.
5. **Amoeba Music / Hollywood Blvd east** (34.0967, -118.3263).
6. **Sunset Blvd + Cinerama Dome** drive-by (34.0971, -118.3278).

*Rideshare 10 min to Griffith Park.*

**Cluster B — Griffith Sunset (2 hrs):**
7. **Griffith Observatory** (34.1184, -118.3004) — arrive 1 hr before sunset.
8. **Mount Hollywood Trail** short loop (0.5 mi) behind observatory for Sign view.
9. Sunset on the observatory west terrace.
10. Descend to **Los Feliz / Vermont Ave** (34.1044, -118.2916) for dinner.

### D. Scoring metadata

**LA-1 (Mulholland to the Pacific):** `tour_absolute = 90.0` · iconic 9.0 · geographic 9.5 · time_realism 8.5 · narrative 9.5 · scenic 9.0 · variety 8.5 · usability 8.0. Primary intent `scenic_sunset` = 93. **Final (hybrid) = 91.2**. Full breakdown in [gold-standard-tours.md — Tour 1](./gold-standard-tours.md#tour-1--mulholland-to-the-pacific).

**LA-2 (Hollywood + Griffith Sunset):** `tour_absolute ≈ 81` · iconic 8.5 · geographic 7.0 (two-cluster friction) · time_realism 7.5 · narrative 9.0 · scenic 8.5 · variety 7.5 · usability 7.0. Primary intent `scenic_sunset` = 89. **Final (hybrid) = 84.2**.

---

## 3. San Francisco ✅ (v2)

### A. City summary

Seven-square-mile peninsula of hills, fog, Victorians, and the single most photographed bridge on earth — SF is the densest "wow per block" city in the US and works beautifully for both driving and walking.

- **Strongest for:** scenic sunset, photo-heavy, iconic driving, romantic, architecture.
- **Weak for:** minimal-walking tours (the hills are the point; avoidance kills the experience).
- **Unique strength:** the Golden Gate Bridge has two canonical hero angles (Battery Spencer north; Baker Beach south) — routes that include both compress a whole day's payoff into 2 hours.

### B. Gold-standard stop graph

| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Golden Gate Bridge (Battery Spencer) | Marin Headlands | 37.8326 | -122.4836 | The canonical GGB shot is from the north, not the south | TA, GM, Social, NYT36 |
| 2 | Alcatraz Island | SF Bay | 37.8270 | -122.4230 | Former federal penitentiary; tour sells out weeks ahead | TA, GM, LP, Viator |
| 3 | Lombard Street (the crooked part) | Russian Hill | 37.8021 | -122.4187 | Eight hairpins in one block; camera catnip | TA, GM, Social |
| 4 | Fisherman's Wharf / Pier 39 | Waterfront | 37.8087 | -122.4098 | Sea lions, clam chowder, ferry hub — touristy but canonical | TA, GM, Viator |
| 5 | Painted Ladies / Alamo Square | Alamo Square | 37.7762 | -122.4328 | Full House skyline-Victorian lineup | TA, GM, Social |
| 6 | Cable Car — Powell-Hyde line | Nob Hill to Wharf | 37.8010 | -122.4177 | Only moving National Historic Landmark | TA, GM, Viator |
| 7 | Coit Tower / Telegraph Hill | Telegraph Hill | 37.8024 | -122.4058 | 360° bay view; Depression-era murals inside | TA, LP |
| 8 | Ferry Building + Embarcadero | Financial District | 37.7955 | -122.3937 | Saturday market = best food in SF in one stop | NYT36, Reddit, Social |
| 9 | Crissy Field + Marshall Beach | Presidio | 37.8032 | -122.4659 | Flat waterfront path under the bridge | GM, Reddit, Social |
| 10 | Mission District (Mission Dolores + murals) | Mission | 37.7599 | -122.4148 | Balmy Alley & Clarion Alley street art; oldest building in SF | NYT36, LP, Social |
| 11 | Haight-Ashbury | Haight | 37.7699 | -122.4469 | 1967 Summer of Love; still the best Victorian-block walk | TA, LP |
| 12 | Twin Peaks | Twin Peaks | 37.7544 | -122.4477 | 922-ft summit; unobstructed east-facing skyline view | GM, Reddit, Social |
| 13 | Chinatown (Grant Ave + Ross Alley) | Chinatown | 37.7941 | -122.4078 | Oldest Chinatown in N. America; dragon gate at Bush & Grant | TA, LP |
| 14 | Golden Gate Park (Japanese Tea Garden, de Young) | Richmond | 37.7694 | -122.4862 | 1,017 acres, larger than Central Park | TA, LP |
| 15 | Baker Beach | Presidio | 37.7933 | -122.4836 | Beach-level GGB view from the south side | Social, Reddit |

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | parking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Ferry Building | waterfront | 8 | 7 | 8 | 30 | medium | morning | sf_east |
| Coit Tower | viewpoint | 8 | 9 | 8 | 25 | medium | afternoon | sf_east |
| Lombard Street (crooked) | icon | 9 | 7 | 7 | 5 | medium | any | sf_central |
| GGB — northbound crossing | icon | 10 | 10 | 9 | 5 | low | golden_hour | sf_bridge |
| Battery Spencer | viewpoint | 10 | 10 | 8 | 20 | medium | golden_hour | sf_marin |
| Baker Beach | viewpoint | 9 | 10 | 7 | 20 | medium | golden_hour | sf_presidio |
| Alamo Sq Painted Ladies | neighborhood | 8 | 7 | 7 | 15 | medium | afternoon | sf_central |
| Twin Peaks summit | viewpoint | 8 | 10 | 6 | 20 | medium | golden_hour | sf_twinpeaks |
| Mission Dolores + murals | neighborhood | 7 | 8 | 9 | 30 | medium | any | sf_mission |
| Chinatown Grant/Ross Alley | neighborhood | 8 | 7 | 9 | 25 | high | any | sf_chinatown |

**Clusters:** `sf_east` · `sf_central` · `sf_bridge` · `sf_marin` · `sf_presidio` · `sf_twinpeaks` · `sf_mission` · `sf_chinatown`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Treasure Island pullover on Bay Bridge east approach |
| Best sunset stop | Battery Spencer (primary) or Baker Beach (alternate) |
| Best short wow | Lombard Street crooked section |
| Best scenic drive segment | Presidio's Lincoln Blvd north from GGB toll plaza |
| Best coffee/food pause | Ferry Building (Acme Bread + Blue Bottle) |
| Best local texture | Mission District murals (Balmy + Clarion Alleys) |
| Best ending point | Baker Beach at golden hour |
| Best worth-the-detour | Filbert Steps climb to Coit Tower |

### C. Benchmark tours

#### Tour SF-1 — "Golden Hour Bay Loop" (2h driving) [GOLD]

See full benchmark with per-stop attributes and score breakdown in [gold-standard-tours.md — Tour 3](./gold-standard-tours.md#tour-3--golden-hour-bay-loop). Target user: visitor or local on a date or with a camera. Intent tags: `scenic_sunset`, `romantic`, `photo_heavy`. **`tour_absolute` = 90.0 · scenic_sunset fit = 97**.

Route summary: Ferry Building → Coit Tower drive-up → Lombard → GGB north → Battery Spencer → GGB south → Baker Beach.

#### Tour SF-2 — "Two Bridges and the Headlands" (2h driving)

*Classic SF skyline drive; time it for 3-5pm to catch afternoon light on the bridge from Battery Spencer.*

Intent: `first_time_highlights`, `scenic_sunset`, `photo_heavy`.

### 2-Hour Driving Tour — "Two Bridges and the Headlands"
*Classic SF skyline drive; time it for 3-5pm to catch afternoon light on the bridge from Battery Spencer.*

1. **Ferry Building** (37.7955, -122.3937) — start on Embarcadero.
2. North on Embarcadero past **Coit Tower** (~1.5 mi) → Fisherman's Wharf.
3. Up **Hyde Street hill** past **Lombard Street** top (37.8021, -122.4187) (~1 mi).
4. West on Broadway → **Presidio** via Lombard/Richardson Ave (~3 mi).
5. **Golden Gate Bridge** northbound crossing (37.8199, -122.4783) (~1.5 mi).
6. **Battery Spencer** viewpoint (37.8326, -122.4836) — the hero photo (~1 mi).
7. Return southbound across GGB → **Presidio's Lincoln Blvd** scenic stretch to **Baker Beach** (37.7933, -122.4836) (~3 mi).
8. East on **Lake St / Geary** → **Alamo Square Painted Ladies** (37.7762, -122.4328) (~3.5 mi).
9. End at **Twin Peaks summit** (37.7544, -122.4477) (~2.5 mi, optional if time).

#### Tour SF-3 — "Embarcadero to North Beach" (4h walking)

*SF's most walkable arc; ~3 mi, mostly flat except Telegraph Hill climb.*

Intent: `first_time_highlights`, `food_heavy`, `local_flavor`.

1. **Ferry Building** (37.7955, -122.3937) — coffee + pastry at Blue Bottle / Acme Bread.
2. Walk the Embarcadero north past piers (~1 mi).
3. **Pier 7** (37.7973, -122.3966) — skyline pier photo.
4. **Levi's Plaza / Filbert Steps** (37.8025, -122.4025) — climb the garden stairs.
5. **Coit Tower** summit (37.8024, -122.4058).
6. Descend to **Washington Square Park + Saints Peter and Paul Church** (37.8006, -122.4101).
7. **North Beach pause** — Tony's Pizza Napoletana or Liguria Bakery focaccia (37.8003, -122.4099).
8. Down Columbus Ave → **City Lights Bookstore + Vesuvio** (37.7975, -122.4065).
9. **Chinatown via Jackson & Grant** → **Ross Alley** fortune cookie factory (37.7954, -122.4065).
10. **Dragon Gate** at Grant & Bush (37.7905, -122.4057).
11. Uphill three blocks to **Powell-Hyde cable car turntable** at Union Square (37.7856, -122.4082) — ride one stop for the photo.
12. End at **Ghirardelli Square / Hyde Street Pier** (37.8064, -122.4222).

### D. Scoring metadata

**SF-1 (Golden Hour Bay Loop):** `tour_absolute = 90.0` · iconic 9.5 · geographic 9.0 · time_realism 8.5 · narrative 9.5 · scenic 10 · variety 8.0 · usability 7.5. Primary intent `scenic_sunset` = 97. **Final (hybrid) = 92.8**. Full breakdown in [gold-standard-tours.md — Tour 3](./gold-standard-tours.md#tour-3--golden-hour-bay-loop).

**SF-2 (Two Bridges and the Headlands):** `tour_absolute ≈ 87` · iconic 9.0 · geographic 8.5 · time_realism 8.0 · narrative 8.5 · scenic 9.5 · variety 8.0 · usability 8.0. Primary intent `first_time_highlights` = 90. **Final (hybrid) = 88.2**.

**SF-3 (Embarcadero to North Beach):** `tour_absolute ≈ 88` · iconic 8.5 · geographic 9.5 · time_realism 8.5 · narrative 8.5 · scenic 8.5 · variety 9.5 · usability 8.5. Primary intent `food_heavy` = 87. **Final (hybrid) = 87.6**.

---

## 4. Chicago ✅ (v2)

### A. City summary

The architectural capital of America — Chicago invented the skyscraper and still flexes harder than anywhere else for river-level architecture, lakefront beaches, and a deep-dish food scene that's worth the drive.

- **Strongest for:** architecture, first-time highlights, family, food-heavy (deep dish + Pilsen).
- **Weak for:** pure-scenic driving in winter (lake wind); sunset-focused (east-facing city means dawn is the better light).
- **Unique strength:** the river cruise is the single highest-rated tourist experience in America — structure architecture tours around it.

### B. Gold-standard stop graph

| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Cloud Gate ("The Bean") / Millennium Park | The Loop | 41.8827 | -87.6233 | Anish Kapoor's mirrored bean = most photographed thing in IL | TA, GM, Social, NYT36 |
| 2 | Chicago Architecture River Cruise | Chicago River | 41.8885 | -87.6235 | Universally rated the #1 thing to do in the city | TA, Viator, LP |
| 3 | Willis Tower Skydeck | West Loop | 41.8789 | -87.6359 | 103rd-floor glass Ledge cubes | TA, GM, Social |
| 4 | 360 Chicago (John Hancock) | Magnificent Mile | 41.8989 | -87.6229 | TILT glass platform + bar view of lake | TA, GM |
| 5 | Navy Pier | Streeterville | 41.8916 | -87.6079 | Ferris wheel, summer fireworks on the lake | TA, GM |
| 6 | Art Institute of Chicago | The Loop | 41.8796 | -87.6237 | One of top 5 encyclopedic museums in US; Nighthawks + Grant Wood | TA, GM, LP |
| 7 | Wrigley Field | Wrigleyville | 41.9484 | -87.6553 | Ivy-walled 1914 ballpark; the pilgrimage MLB stop | TA, GM |
| 8 | Lincoln Park Zoo + Conservatory | Lincoln Park | 41.9217 | -87.6336 | Free zoo since 1868; Victorian glasshouse next door | TA, GM |
| 9 | The Riverwalk | Chicago River | 41.8880 | -87.6289 | Below-street-level promenade under the bridges | NYT36, Social |
| 10 | Buckingham Fountain / Grant Park | Grant Park | 41.8758 | -87.6189 | Married with Children opening credits; lake-facing rococo fountain | TA, GM |
| 11 | Adler Planetarium + Museum Campus | Museum Campus | 41.8663 | -87.6069 | Best skyline photo in Chicago is from Adler's lakefront | GM, Social, Reddit |
| 12 | Magnificent Mile (N Michigan Ave) | Near North | 41.8950 | -87.6244 | Shopping spine; the Tribune Tower + Wrigley Building here | TA, GM |
| 13 | Lincoln Park's North Ave Beach | Lincoln Park | 41.9117 | -87.6274 | Chicago has beaches; skyline-framed volleyball courts | Social, Reddit |
| 14 | Pilsen murals + 18th St | Pilsen | 41.8574 | -87.6582 | Mexican-American district; some of the best street art in US | NYT36, Social |
| 15 | Chicago Theatre marquee + State St | The Loop | 41.8854 | -87.6278 | 1921 icon; the CHICAGO sign = postcard | TA, Social |

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | parking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Cloud Gate (The Bean) | icon | 10 | 9 | 7 | 15 | medium | midday | chi_loop |
| Art Institute | museum | 8 | 7 | 9 | 90 | medium | any | chi_loop |
| Pritzker Pavilion | icon | 8 | 8 | 9 | 15 | low | any | chi_loop |
| Riverwalk | waterfront | 8 | 9 | 9 | 30 | low | any | chi_river |
| Architecture River Cruise | scenic_drive | 10 | 10 | 10 | 90 | low | afternoon | chi_river |
| Tribune Tower + Wrigley Bldg | icon | 9 | 8 | 10 | 10 | low | any | chi_river |
| Willis Tower Skydeck | viewpoint | 9 | 9 | 8 | 45 | medium | afternoon | chi_loop |
| Navy Pier (Ferris wheel lit) | viewpoint | 8 | 8 | 6 | 30 | medium | night | chi_north |
| Adler Planetarium lakefront | viewpoint | 7 | 10 | 7 | 20 | low | afternoon | chi_museum |
| Wrigley Field | icon | 9 | 7 | 9 | 30 | medium | any | chi_wrigley |
| Pilsen murals + 18th St | neighborhood | 6 | 8 | 9 | 30 | low | any | chi_pilsen |

**Clusters:** `chi_loop` · `chi_river` · `chi_north` · `chi_museum` · `chi_wrigley` · `chi_pilsen`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Adler Planetarium lakefront (east-to-west Loop panorama) |
| Best sunset stop | North Ave Beach with Hancock backdrop |
| Best short wow | Cloud Gate at midday |
| Best scenic drive segment | Lake Shore Dr southbound through Oak St Beach curve |
| Best coffee/food pause | Lou Malnati's or Gino's East (deep dish) |
| Best local texture | Pilsen murals + 18th St taquerias |
| Best ending point | Navy Pier at dusk (Ferris wheel lit) |
| Best worth-the-detour | Chicago Architecture Foundation River Cruise |

### C. Benchmark tours

#### Tour CHI-1 — "River Architecture + Loop" (3h hybrid) [GOLD]

See full benchmark with per-stop attributes and score breakdown in [gold-standard-tours.md — Tour 4](./gold-standard-tours.md#tour-4--river-architecture--loop). Target user: architecture-curious visitor. Intent tags: `architecture`, `architecture_modern`, `first_time_highlights`. **`tour_absolute` = 91.0 · architecture fit = 97**.

#### Tour CHI-2 — "Lake Shore Loop" (2h driving)

*Chicago's signature drive is Lake Shore Dr with the skyline on one side and Lake Michigan on the other. Best at sunset eastbound from the north.*

Intent: `scenic_sunset`, `first_time_highlights`, `minimal_walking`.

1. **Adler Planetarium** (41.8663, -87.6069) — start with skyline photo.
2. **Lake Shore Drive northbound** past Grant Park, Navy Pier visible (~3 mi).
3. **Oak Street Beach curve** (41.9023, -87.6232) — skyline-into-lake bend (~1 mi).
4. Continue LSD to **North Ave Beach** (41.9117, -87.6274) — pullover (~1 mi).
5. Exit at Fullerton → **Lincoln Park Zoo drive-by** (41.9217, -87.6336) (~1.5 mi).
6. South on Clark St → **Wrigley Field** (41.9484, -87.6553) (~2.5 mi).
7. South via Lake Shore Dr back to **Buckingham Fountain** (41.8758, -87.6189) (~6 mi).
8. End at **Michigan Ave Bridge** with Wrigley Building lit (41.8886, -87.6244) (~1 mi).

#### Tour CHI-3 — "The Loop + River + Mile" (4h walking)

*~2.8 mi flat loop. Do on Saturday when Riverwalk is lively. Functions as the walking parallel to CHI-1 (gold).*

Intent: `first_time_highlights`, `architecture`, `food_heavy` (soft).

1. **Art Institute (lion statues)** (41.8796, -87.6237) — skip inside unless extra time.
2. **Millennium Park / The Bean** (41.8827, -87.6233).
3. **Pritzker Pavilion + Lurie Garden** (41.8818, -87.6220).
4. **Riverwalk eastbound from Michigan Ave Bridge** (41.8886, -87.6244) — descend the stairs.
5. **City Winery / Riverwalk cafés** mid-walk pause.
6. **DuSable Bridge + Tribune Tower / Wrigley Building** above (41.8886, -87.6244).
7. Up Michigan Ave = **Magnificent Mile walk** (~0.8 mi).
8. **Water Tower + 360 Chicago base** (41.8975, -87.6241).
9. **Lou Malnati's or Gino's East pause** for a deep-dish slice (41.8920, -87.6260).
10. **Navy Pier** (41.8916, -87.6079) — optional east detour for Ferris wheel + skyline from the lake side.
11. Back via **Lake Shore East → Maggie Daley Park** (41.8858, -87.6194).
12. End at **Cloud Gate at dusk for the lights-on photo**.

### D. Scoring metadata

**CHI-1 (River Architecture + Loop):** `tour_absolute = 91.0` · iconic 9.5 · geographic 9.5 · time_realism 8.0 · narrative 9.5 · scenic 9.5 · variety 8.5 · usability 8.0. Primary intent `architecture` = 97. **Final (hybrid) = 93.4**. Full breakdown in [gold-standard-tours.md — Tour 4](./gold-standard-tours.md#tour-4--river-architecture--loop).

**CHI-2 (Lake Shore Loop):** `tour_absolute ≈ 85` · iconic 8.5 · geographic 9.5 · time_realism 8.5 · narrative 8.5 · scenic 8.5 · variety 7.5 · usability 8.5. Primary intent `scenic_sunset` = 83. **Final (hybrid) = 84.2**.

**CHI-3 (Loop + River + Mile walking):** `tour_absolute ≈ 87` · iconic 9.0 · geographic 9.0 · time_realism 8.0 · narrative 8.5 · scenic 8.5 · variety 9.0 · usability 8.5. Primary intent `first_time_highlights` = 91. **Final (hybrid) = 88.6**.

---

## 5. Miami ✅ (v2)

### A. City summary

Art Deco pastels, Cuban-American flavor, and the country's most theatrical beach — Miami runs on a neon Latin rhythm from Ocean Drive through Wynwood's murals to Little Havana's domino parks.

- **Strongest for:** 2h efficient drives, scenic sunset, photo-heavy, local flavor (Little Havana, Wynwood).
- **Weak for:** walking tours over 3h (heat + humidity + sprawl); architecture outside South Beach + Coral Gables.
- **Unique strength:** the causeways are the attraction — Miami's bay crossings stack scenic payoff in a way no other US city can match.

### B. Gold-standard stop graph

#### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | South Beach + Ocean Drive Art Deco | South Beach | 25.7825 | -80.1340 | 800 deco buildings; the lifeguard huts = Miami postcard | TA, GM, Social |
| 2 | Wynwood Walls | Wynwood | 25.8010 | -80.1990 | Outdoor street-art museum; Instagram capital of FL | TA, NYT36, Social |
| 3 | Little Havana (Calle Ocho + Domino Park) | Little Havana | 25.7659 | -80.2196 | Cuban coffee ventanitas, cigars, live son music | TA, LP, NYT36 |
| 4 | Vizcaya Museum & Gardens | Coconut Grove | 25.7443 | -80.2109 | 1916 Italianate estate on Biscayne Bay | TA, GM, Social |
| 5 | Pérez Art Museum (PAMM) | Downtown | 25.7858 | -80.1867 | Herzog & de Meuron stilted building on the bay | TA, GM, NYT36 |
| 6 | Bayside Marketplace + Bayfront Park | Downtown | 25.7781 | -80.1864 | Boat launch for sunset cruises | TA, GM |
| 7 | Miami Beach Boardwalk (Lummus Park) | South Beach | 25.7823 | -80.1310 | Palm-lined beach walk; the iconic lifeguard stands | TA, Social |
| 8 | Lincoln Road Mall | South Beach | 25.7907 | -80.1394 | Pedestrian shopping/dining strip | TA, GM |
| 9 | Freedom Tower | Downtown | 25.7797 | -80.1898 | "Ellis Island of the South" Cuban refugee landmark | LP |
| 10 | Fairchild Tropical Botanic Garden | Coral Gables | 25.6763 | -80.2725 | 83 acres of palms; Dale Chihuly installs recur | TA, NYT36 |
| 11 | Venetian Pool | Coral Gables | 25.7476 | -80.2735 | 1924 coral-rock swimming lagoon; most beautiful public pool in US | TA, Social |
| 12 | Biltmore Hotel | Coral Gables | 25.7236 | -80.2769 | 1926 Mediterranean-revival; Al Capone's speakeasy | TA, LP |
| 13 | Miami Design District | Design District | 25.8128 | -80.1914 | Luxury boutiques + sculpture (Buckminster Fuller dome) | NYT36 |
| 14 | Key Biscayne + Bill Baggs State Park | Key Biscayne | 25.6667 | -80.1566 | Cape Florida lighthouse + palm-rimmed beach | TA, Reddit |
| 15 | Coconut Grove waterfront | Coconut Grove | 25.7271 | -80.2378 | Sailing village feel; CocoWalk & Peacock Park | TA |

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | parking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| South Pointe Park pier | waterfront | 7 | 9 | 7 | 15 | medium | afternoon | miami_sobe |
| Ocean Drive Deco strip | scenic_drive | 9 | 8 | 9 | 10 | high | afternoon | miami_sobe |
| MacArthur Causeway | scenic_drive | 8 | 9 | 7 | 10 | not_applicable | afternoon | miami_bay |
| PAMM skyline drive-by | viewpoint | 7 | 8 | 7 | 10 | medium | afternoon | miami_downtown |
| Rickenbacker pullover | viewpoint | 6 | 10 | 5 | 15 | low | golden_hour | miami_key |
| Vizcaya exterior | icon | 8 | 9 | 9 | 20 | medium | golden_hour | miami_grove |
| Wynwood Walls | neighborhood | 8 | 9 | 8 | 60 | medium | afternoon | miami_wynwood |
| Little Havana (Calle Ocho) | neighborhood | 8 | 7 | 10 | 60 | medium | afternoon | miami_havana |
| Lincoln Road Mall | neighborhood | 6 | 6 | 6 | 30 | medium | any | miami_sobe |
| Biltmore Hotel | icon | 6 | 8 | 9 | 30 | low | any | miami_gables |

**Clusters:** `miami_sobe` · `miami_bay` · `miami_downtown` · `miami_key` · `miami_grove` · `miami_wynwood` · `miami_havana` · `miami_gables`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Rickenbacker Causeway pullover at dusk |
| Best sunset stop | Vizcaya exterior at golden hour |
| Best short wow | Ocean Drive Deco lifeguard huts |
| Best scenic drive segment | MacArthur Causeway westbound |
| Best coffee/food pause | Versailles or Café Versailles (Little Havana) |
| Best local texture | Domino Park + Calle Ocho |
| Best ending point | Vizcaya gardens against Biscayne Bay |
| Best worth-the-detour | Wynwood Walls (40-min ticket entry) |

### C. Benchmark tours

#### Tour MIA-1 — "Causeway Miami" (2h driving) [GOLD]

See full benchmark with per-stop attributes and score breakdown in [gold-standard-tours.md — Tour 10](./gold-standard-tours.md#tour-10--causeway-miami). Target user: visitor with one evening and a rental car. Intent tags: `efficient_short`, `first_time_highlights`, `scenic_sunset`. **`tour_absolute` = 89.0 · efficient_short fit = 95**.

#### Tour MIA-2 — "Causeway to Coconut Grove" (2h driving, alternate)

*Miami's hero drive crosses the bay three times; best at golden hour Miami Beach → Coconut Grove.*

Intent: `scenic_sunset`, `first_time_highlights`, `efficient_short`.

### 2-Hour Driving Tour — "Causeway to Coconut Grove"
*Miami's hero drive crosses the bay three times; best at golden hour Miami Beach → Coconut Grove.*

1. **South Pointe Park** (25.7684, -80.1340) — start at the southern tip of Miami Beach.
2. North on **Ocean Drive → Collins Ave** past deco hotels (~2 mi) to **Versace Mansion** (25.7816, -80.1318).
3. West on **5th St** → **MacArthur Causeway** (I-395) (~3 mi) — Cruise ships + Star Island views.
4. Exit to **Downtown → PAMM drive-by** (25.7858, -80.1867) (~1.5 mi).
5. South on **Biscayne Blvd → Brickell Ave** past skyline (~2 mi).
6. **Rickenbacker Causeway** toward Key Biscayne — pull off at **Hobie Beach** (25.7412, -80.1702) for downtown skyline view (~3 mi).
7. Return & take **S Miami Ave → Coconut Grove** (~4 mi).
8. End at **Vizcaya Museum & Gardens exterior** (25.7443, -80.2109) — golden hour.

#### Tour MIA-3 — "South Beach Deco + Wynwood" (4h walking, two-cluster)

*Requires one short rideshare between clusters. Strongest in cooler season — heat gates walkability 6+ months/yr.*

Intent: `first_time_highlights`, `photo_heavy`, `local_flavor`.

**Cluster A — South Beach (2.5 hrs, ~1.5 mi flat):**
1. **South Pointe Park Pier** (25.7684, -80.1340).
2. Ocean Drive north past **Clevelander, Colony, Leslie Hotels** (25.7812, -80.1326).
3. **Versace Mansion / Casa Casuarina** (25.7816, -80.1318).
4. **News Café or Front Porch** coffee pause.
5. **Lummus Park lifeguard stand photos** (25.7825, -80.1315).
6. **Art Deco Welcome Center** (25.7803, -80.1307) — free gallery.
7. Cross to **Lincoln Road** pedestrian mall (25.7907, -80.1394).
8. **Joe's Stone Crab takeaway window** (25.7685, -80.1376).

*5-min rideshare to Wynwood.*

**Cluster B — Wynwood (1.5 hrs):**
9. **Wynwood Walls** ticket entry (25.8009, -80.1990).
10. **NW 2nd Ave mural strip** (25.8015, -80.1994) — outside the paid walls.
11. **Panther Coffee flagship** (25.8017, -80.1991).
12. End at **Wynwood Marketplace** (25.8006, -80.1987).

### D. Scoring metadata

**MIA-1 (Causeway Miami):** `tour_absolute = 89.0` · iconic 8.0 · geographic 9.0 · time_realism 9.5 · narrative 9.0 · scenic 9.5 · variety 8.5 · usability 8.5. Primary intent `efficient_short` = 95. **Final (hybrid) = 91.4**. Full breakdown in [gold-standard-tours.md — Tour 10](./gold-standard-tours.md#tour-10--causeway-miami).

**MIA-2 (Causeway to Coconut Grove):** `tour_absolute ≈ 86` · iconic 8.0 · geographic 9.0 · time_realism 8.5 · narrative 8.5 · scenic 9.0 · variety 8.0 · usability 8.5. Primary intent `scenic_sunset` = 90. **Final (hybrid) = 87.6**.

**MIA-3 (SoBe + Wynwood walking):** `tour_absolute ≈ 81` · iconic 8.5 · geographic 7.0 (rideshare gap) · time_realism 7.5 · narrative 8.0 · scenic 8.5 · variety 8.5 · usability 7.0 (heat risk). Primary intent `first_time_highlights` = 85. **Final (hybrid) = 82.6**.

---

## 6. Washington DC 🔹

**Summary:** A purpose-built monumental city — the National Mall concentrates more free world-class museums and national symbols per square mile than anywhere else on earth. **Strong for:** family, first-time highlights, architecture, walking flat-and-free. **Weak for:** sunset drives, local flavor.
**Signature moments:** skyline reveal — Memorial Bridge dawn crossing · short wow — Lincoln Memorial steps · food pause — Mitsitam Native Foods Café · local texture — Eastern Market on Saturday · ending — Jefferson Memorial at dusk · worth the detour — Air & Space Museum.
**Clusters:** `dc_mall_west` · `dc_mall_central` · `dc_mall_east` · `dc_georgetown` · `dc_arlington` · `dc_wharf`.
**Gold tour:** National Mall for Kids ([Tour 8](./gold-standard-tours.md#tour-8--national-mall-for-kids)) — `tour_absolute = 89`, kid_friendly fit = 96.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Lincoln Memorial | National Mall | 38.8893 | -77.0502 | Marble civic temple; MLK "I Have a Dream" spot | TA, GM, LP |
| 2 | Washington Monument | National Mall | 38.8895 | -77.0353 | 555-ft obelisk centerpoint of Mall | TA, GM |
| 3 | US Capitol | Capitol Hill | 38.8899 | -77.0091 | Working seat of Congress; dome icon | TA, GM |
| 4 | White House (Ellipse / Lafayette Sq) | Downtown | 38.8977 | -77.0365 | Bucket-list photo from Lafayette Sq or Ellipse | TA, GM |
| 5 | Smithsonian Air & Space Museum | National Mall | 38.8882 | -77.0199 | Most-visited museum in US; Wright Flyer, Apollo 11 | TA, GM, LP |
| 6 | National Gallery of Art | National Mall | 38.8913 | -77.0200 | West Wing Rothko, East Wing I.M. Pei | TA, LP |
| 7 | Jefferson Memorial + Tidal Basin | Tidal Basin | 38.8814 | -77.0365 | Cherry blossoms March-April = peak DC photo | TA, Social |
| 8 | MLK Memorial | Tidal Basin | 38.8862 | -77.0437 | 30-ft granite figure "Stone of Hope" | TA, LP |
| 9 | Vietnam Veterans Memorial | National Mall | 38.8911 | -77.0475 | Maya Lin's black granite wall | TA, LP |
| 10 | US Holocaust Memorial Museum | National Mall | 38.8868 | -77.0325 | Most emotionally intense museum in DC | TA, LP |
| 11 | Georgetown + C&O Canal | Georgetown | 38.9050 | -77.0628 | Cobblestone, Federal row houses, M St shops | NYT36, TA |
| 12 | National Museum of African American History & Culture | National Mall | 38.8910 | -77.0329 | David Adjaye's bronze-lattice architecture | TA, NYT36 |
| 13 | Arlington National Cemetery + Iwo Jima | Arlington VA | 38.8783 | -77.0687 | Changing of the Guard at Tomb of Unknowns | TA, GM, LP |
| 14 | Library of Congress (Jefferson Building) | Capitol Hill | 38.8887 | -77.0047 | Beaux-arts Great Hall; free tours | TA, Reddit |
| 15 | The Wharf / SW Waterfront | SW Waterfront | 38.8788 | -77.0226 | Newer river promenade, food hall, live music | NYT36 |

### 2-Hour Driving Tour — "Monumental Loop"
*DC driving is tricky midday — aim for 6-8am or after 7pm for light + easy parking. Tidal Basin in spring for cherry blossoms is mandatory.*

1. **Lincoln Memorial circle** (38.8893, -77.0502) — start with dawn light.
2. **Memorial Bridge → Arlington National Cemetery / Iwo Jima** (38.8905, -77.0694) (~1.5 mi).
3. Return via **Ohio Dr / Tidal Basin loop** past **Jefferson Memorial** (38.8814, -77.0365) (~3 mi).
4. **East Potomac Park Hains Point** (38.8519, -77.0228) — skyline and river view (~3 mi).
5. North to **SW Waterfront / The Wharf** (38.8788, -77.0226) (~2 mi).
6. East on **Independence Ave** → Capitol (38.8899, -77.0091) (~2 mi).
7. North on 1st St → **Union Station** (38.8975, -77.0064) (~0.8 mi).
8. West on **Constitution Ave** past Mall museums → **White House north Ellipse** (38.8977, -77.0365) (~2.5 mi).
9. End back at **Lincoln Memorial** for lit-up finale (~1.5 mi).

### 4-Hour Walking Tour — "The Mall, end to end"
*~3.5 mi flat; bring water. This is the DC pilgrimage.*

1. **Lincoln Memorial** steps (38.8893, -77.0502).
2. **Korean War Veterans Memorial** (38.8877, -77.0475).
3. **Vietnam Veterans Memorial** wall (38.8911, -77.0475).
4. **Reflecting Pool walk east** (38.8895, -77.0445).
5. **WWII Memorial** (38.8895, -77.0404).
6. **Washington Monument** base (38.8895, -77.0353).
7. ☕ Food truck row on Constitution Ave.
8. **National Museum of African American History** exterior (38.8910, -77.0329).
9. **Smithsonian National Museum of American History** (38.8913, -77.0300) — 30 min browse.
10. **National Gallery of Art West Building** (38.8913, -77.0200) — 45 min browse.
11. **Air & Space Museum** (38.8882, -77.0199) — 30 min, Wright Flyer + Apollo 11.
12. **US Capitol west lawn** (38.8899, -77.0091) — final photo.

---

## 7. Boston 🔹

**Summary:** The birthplace of American independence — Boston packs Colonial landmarks, Ivy-league campuses, and Italian North End food into a walkable peninsula where the Freedom Trail's red-brick line does the navigation for you. **Strong for:** walking, first-time highlights, architecture_historic, food-heavy. **Weak for:** scenic drives (compact peninsula), sunset views.
**Signature moments:** skyline reveal — Charles River Esplanade from Cambridge · short wow — Acorn Street · food pause — Mike's vs Modern Pastry cannoli on Hanover · local texture — North End Sunday · ending — Bunker Hill Monument at golden hour · worth the detour — Isabella Stewart Gardner Museum.
**Clusters:** `bos_common` · `bos_northend` · `bos_charlestown` · `bos_backbay` · `bos_cambridge` · `bos_seaport`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Freedom Trail (2.5mi red-brick line) | Downtown-North End | 42.3581 | -71.0595 | 16 Revolutionary War sites on one painted line | TA, GM, LP, Viator |
| 2 | Faneuil Hall / Quincy Market | Downtown | 42.3600 | -71.0568 | 1742 marketplace; still the social crossroads | TA, GM |
| 3 | Boston Common + Public Garden | Beacon Hill | 42.3551 | -71.0656 | Oldest public park in US (1634); swan boats | TA, GM |
| 4 | Fenway Park | Fenway | 42.3467 | -71.0972 | Oldest MLB park (1912); Green Monster | TA, GM |
| 5 | North End (Paul Revere House, Hanover St) | North End | 42.3647 | -71.0542 | Little Italy; Mike's vs Modern Pastry cannoli debate | TA, NYT36, Social |
| 6 | USS Constitution | Charlestown | 42.3725 | -71.0565 | Oldest commissioned warship afloat (1797) | TA, LP |
| 7 | Old North Church | North End | 42.3664 | -71.0544 | "One if by land, two if by sea" lanterns | TA, LP |
| 8 | Harvard Yard + Harvard Square | Cambridge | 42.3744 | -71.1169 | Oldest US university (1636); John Harvard statue | TA, LP |
| 9 | MIT campus + Mass Ave | Cambridge | 42.3601 | -71.0942 | Great Dome, Frank Gehry Stata Center | GM, Reddit |
| 10 | Beacon Hill (Acorn St) | Beacon Hill | 42.3583 | -71.0692 | Most Instagrammed cobblestone street in US | TA, Social |
| 11 | Boston Public Library (Bates Hall) | Back Bay | 42.3494 | -71.0780 | McKim palace + Sargent murals | TA, Social |
| 12 | Copley Square (Trinity Church) | Back Bay | 42.3497 | -71.0754 | H.H. Richardson masterpiece + BPL reflection | TA, LP |
| 13 | Newbury Street | Back Bay | 42.3503 | -71.0810 | Brownstone shopping spine | TA |
| 14 | Bunker Hill Monument | Charlestown | 42.3764 | -71.0608 | First major Revolutionary battle obelisk | TA, LP |
| 15 | Isabella Stewart Gardner Museum | Fenway | 42.3387 | -71.0993 | Venetian palazzo; site of $500M unsolved heist | TA, NYT36 |

### 2-Hour Driving Tour — "Two River Crossings"
1. **Boston Common Parking** (42.3551, -71.0656) — start.
2. **Storrow Drive eastbound** along Charles River (~2 mi).
3. **Leonard P Zakim Bridge** — cross to Charlestown (~1 mi).
4. **USS Constitution / Bunker Hill** (42.3725, -71.0565) — 10-min stop (~0.5 mi).
5. Tobin Bridge south → **North End via Hanover St** (42.3647, -71.0542) (~2 mi).
6. **Waterfront / Long Wharf** (42.3602, -71.0500) (~1 mi).
7. **Seaport / Fan Pier** (42.3533, -71.0436) (~2 mi).
8. Back over **Mass Ave Bridge** → **Cambridge MIT + Harvard** drive-through (~5 mi).
9. End back on **Storrow → Beacon Hill** with Charles view (~3 mi).

### 4-Hour Walking Tour — "The Freedom Trail + North End"
*~3 mi, follow the red-brick line. This is Boston's canonical walk.*

1. **Boston Common Visitor Center** (42.3551, -71.0656) — pick up trail map.
2. **Massachusetts State House** (42.3588, -71.0638).
3. **Park Street Church + Granary Burying Ground** (42.3575, -71.0614) — Sam Adams, John Hancock graves.
4. **King's Chapel** (42.3577, -71.0602).
5. **Old South Meeting House** (42.3563, -71.0586) — site of Boston Tea Party planning.
6. **Old State House** (42.3588, -71.0575) — Boston Massacre site.
7. **Faneuil Hall / Quincy Market** (42.3600, -71.0568) — lunch in the food hall.
8. 🍝 **North End — Hanover St** walk to **Paul Revere House** (42.3638, -71.0538).
9. **Old North Church** (42.3664, -71.0544).
10. ☕ **Mike's Pastry OR Modern Pastry cannoli** (42.3634, -71.0547).
11. Cross **Charlestown Bridge** → **USS Constitution** (42.3725, -71.0565).
12. End at **Bunker Hill Monument** (42.3764, -71.0608).

---

## 8. Seattle 🔹

**Summary:** The Pacific Northwest's tech capital wraps around Elliott Bay with volcano views on clear days — Pike Place Market, the Space Needle, and ferry-boat Puget Sound vistas anchor a compact walkable core. **Strong for:** walking, scenic views (Mt Rainier), food-heavy, architecture. **Weak for:** weather-sensitive tours in rainy season; sunset reliability (clouds).
**Signature moments:** skyline reveal — Kerry Park at golden hour · short wow — Gum Wall at Post Alley · food pause — Pike Place Chowder · local texture — Ballard on a weekend · ending — Bainbridge ferry sunset · worth the detour — Chihuly Garden and Glass.
**Clusters:** `sea_downtown` · `sea_pike` · `sea_queenanne` · `sea_ballard` · `sea_capitolhill` · `sea_waterfront`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Pike Place Market (flying fish) | Downtown | 47.6085 | -122.3405 | 1907 public market; fish-throwers, first Starbucks next door | TA, GM, LP, Viator |
| 2 | Space Needle | Seattle Center | 47.6205 | -122.3493 | 1962 World's Fair icon; rotating glass floor | TA, GM |
| 3 | Chihuly Garden & Glass | Seattle Center | 47.6206 | -122.3509 | Most impressive glass art museum in the world | TA, GM, Social |
| 4 | Kerry Park viewpoint | Queen Anne | 47.6295 | -122.3600 | The canonical Space Needle + Rainier postcard | GM, Social |
| 5 | Gum Wall (Post Alley) | Downtown | 47.6082 | -122.3417 | Viral / gross tourist icon beneath Pike Place | TA, Social |
| 6 | Museum of Pop Culture (MoPOP) | Seattle Center | 47.6214 | -122.3481 | Frank Gehry building; Nirvana + sci-fi exhibits | TA, LP |
| 7 | Pioneer Square + Underground Tour | Pioneer Square | 47.6020 | -122.3321 | Seattle's original downtown; buried after 1889 fire | TA, LP |
| 8 | Bainbridge Island Ferry | Ferry Terminal | 47.6023 | -122.3380 | 35-min round trip with skyline views | NYT36, Reddit |
| 9 | Seattle Great Wheel | Waterfront | 47.6063 | -122.3425 | Pier 57 ferris wheel over Elliott Bay | TA, GM |
| 10 | First Starbucks (original store) | Pike Place | 47.6097 | -122.3421 | 1971 original, mermaid logo still intact | TA, Social |
| 11 | Seattle Art Museum (SAM) | Downtown | 47.6074 | -122.3381 | Hammering Man sculpture outside | TA, LP |
| 12 | Fremont Troll | Fremont | 47.6513 | -122.3475 | VW-crushing concrete troll under Aurora Bridge | TA, Social |
| 13 | Gas Works Park | Wallingford | 47.6456 | -122.3344 | Reclaimed coal-gas plant; best skyline view from north | GM, Social |
| 14 | Ballard Locks + Salmon Ladder | Ballard | 47.6655 | -122.3972 | Shipping locks + viewing window for spawning salmon | TA, Reddit |
| 15 | Discovery Park / West Point Lighthouse | Magnolia | 47.6587 | -122.4176 | 534-acre park; Rainier + Olympics view on clear day | LP, Reddit |

### 2-Hour Driving Tour — "Water + Volcano Views"
*Needs a clear day for Rainier. Best morning for SE light on the mountain.*

1. **Gas Works Park** (47.6456, -122.3344) — start with skyline photo.
2. **Aurora Bridge south → Fremont Troll** (47.6513, -122.3475) (~2 mi).
3. **Ballard Ave historic district** (47.6683, -122.3838) (~2 mi).
4. **Ballard Locks** brief stop (47.6655, -122.3972) (~1 mi).
5. **Magnolia Bridge → Discovery Park entrance** (47.6587, -122.4176) (~3 mi).
6. **Elliott Ave / Alaskan Way southbound** past Space Needle visible (~4 mi).
7. **Pier 66 waterfront** (47.6116, -122.3484) (~1 mi).
8. End at **Kerry Park** (47.6295, -122.3600) — Space Needle hero shot (~2 mi).

### 4-Hour Walking Tour — "Market to Space Needle"
*~2.8 mi, some hills near Queen Anne. Do before noon to see fishmongers.*

1. **Pike Place Market main entrance** (47.6085, -122.3405) — flying fish at 9am.
2. **Rachel the Pig / market arcade** (47.6089, -122.3402).
3. **Original Starbucks** (47.6097, -122.3421) — photo, skip line.
4. **Post Alley / Gum Wall** (47.6082, -122.3417).
5. ☕ **Piroshky Piroshky** pause (47.6090, -122.3412).
6. Down **Pike Street Hillclimb** to **Waterfront / Seattle Great Wheel** (47.6063, -122.3425).
7. **Olympic Sculpture Park** (47.6166, -122.3551) — walk along water.
8. Up the **Bell Street pedestrian bridge** → **Belltown** (47.6150, -122.3462).
9. 🍽️ **Biscuit Bitch or Top Pot Doughnuts** mid-walk fuel.
10. **Seattle Center → Chihuly Garden & Glass** (47.6206, -122.3509).
11. **Space Needle** (47.6205, -122.3493) — up at sunset if possible.
12. End at **Kerry Park** via steep Queen Anne walk (47.6295, -122.3600).

---

## 9. New Orleans 🔹

**Summary:** The most culturally distinct city in America — French Quarter wrought iron, Creole cooking, and live jazz 24/7 make NOLA a place where the tour IS the food-and-music sensory bath. **Strong for:** food-heavy, local flavor, romantic evening, walking. **Weak for:** family (Bourbon St. adult-skew), scenic drives.
**Signature moments:** short wow — Cathedral Basilica + Jackson Square · food pause — Café du Monde beignets · local texture — Frenchmen St. live jazz at 9pm · ending — Preservation Hall show · worth the detour — Lafayette Cemetery or Garden District streetcar.
**Clusters:** `nola_frenchquarter` · `nola_frenchmen` · `nola_garden` · `nola_warehouse` · `nola_treme`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Jackson Square + St. Louis Cathedral | French Quarter | 29.9574 | -90.0632 | NOLA's iconic plaza; oldest cathedral in continuous use in US | TA, GM, LP |
| 2 | Bourbon Street | French Quarter | 29.9585 | -90.0656 | 24/7 live music strip; Pat O'Brien's hurricanes | TA, GM |
| 3 | Café du Monde (original) | French Quarter | 29.9576 | -90.0621 | 1862 beignets + chicory coffee under the awning | TA, GM, Social |
| 4 | Frenchmen Street (live jazz) | Marigny | 29.9634 | -90.0585 | The locals' Bourbon; Spotted Cat, Blue Nile | NYT36, Reddit, LP |
| 5 | Garden District mansions + Magazine St | Garden District | 29.9258 | -90.0843 | Greek Revival + antebellum architecture; streetcar access | TA, NYT36, LP |
| 6 | St. Charles Streetcar | Uptown | 29.9275 | -90.0894 | Oldest continuously operating streetcar line in the world | TA, LP |
| 7 | Lafayette Cemetery No. 1 | Garden District | 29.9273 | -90.0842 | Above-ground tombs; Anne Rice Interview with the Vampire | TA, Social |
| 8 | National WWII Museum | Warehouse District | 29.9430 | -90.0703 | #1 museum in US on many lists; expansive campus | TA, GM |
| 9 | City Park + NOMA | Mid-City | 29.9833 | -90.0944 | Oldest live oaks in the country; sculpture garden | TA, LP |
| 10 | French Market | French Quarter | 29.9614 | -90.0603 | Open-air market since 1791 | TA |
| 11 | Preservation Hall | French Quarter | 29.9580 | -90.0645 | Bare-benches nightly traditional jazz since 1961 | TA, NYT36, LP |
| 12 | Bywater + Crescent Park | Bywater | 29.9624 | -90.0503 | Colorful shotgun houses; Rusty Rainbow bridge | NYT36, Social |
| 13 | Magazine Street (shopping) | Uptown | 29.9325 | -90.0854 | 6-mile corridor of boutiques, antiques, cafés | LP |
| 14 | Audubon Park + Zoo | Uptown | 29.9316 | -90.1250 | Ancient oaks, jogging loop | LP |
| 15 | Old Ursuline Convent / Royal Street | French Quarter | 29.9612 | -90.0608 | Oldest French colonial building in Mississippi Valley | LP |

### 2-Hour Driving Tour — "Beyond the Quarter"
1. **Jackson Square** (29.9574, -90.0632) — start.
2. **Esplanade Ave east** through Marigny/Bywater (~2 mi).
3. **Crescent Park / Rusty Rainbow** (29.9624, -90.0503) (~0.5 mi).
4. **Esplanade north → City Park entrance** (29.9833, -90.0944) (~4 mi).
5. **St. Charles Avenue southbound** (~5 mi scenic streetcar corridor).
6. Stop at **Audubon Park entry** (29.9316, -90.1250) (~0.5 mi).
7. Back up **Magazine Street** via Garden District (~4 mi).
8. **Lafayette Cemetery No. 1 exterior** (29.9273, -90.0842).
9. End at **National WWII Museum** (29.9430, -90.0703) (~2 mi).

### 4-Hour Walking Tour — "French Quarter + Marigny"
*~2.2 mi, very flat, best early evening so you catch Frenchmen live.*

1. **Jackson Square + St. Louis Cathedral** (29.9574, -90.0632).
2. **Pontalba Apartments + artist row** (29.9571, -90.0629).
3. **Café du Monde** (29.9576, -90.0621) — beignets pause.
4. **French Market** stroll (29.9614, -90.0603).
5. **Royal Street** antique shops + street music (29.9584, -90.0642).
6. **Preservation Hall** (29.9580, -90.0645) — note showtimes.
7. 🍽️ **Napoleon House muffuletta** (29.9569, -90.0650).
8. **Lafitte's Blacksmith Shop** (29.9599, -90.0627) — oldest bar in US (1772).
9. **Bourbon Street stretch** (29.9585, -90.0656) — 2 blocks only.
10. **Frenchmen Street entry** (29.9634, -90.0585) — evening jazz crawl.
11. ☕ **The Spotted Cat or d.b.a.** live music venue.
12. End with gumbo at **Coop's Place** (29.9586, -90.0615) or late beignet.

---

## 10. Nashville 🔹

**Summary:** Music City USA — honky-tonk Broadway by night, southern food by day, and the Grand Ole Opry pilgrimage for anyone who ever loved country music. **Strong for:** food-heavy, music-themed, local flavor. **Weak for:** scenic, architecture tours.
**Signature moments:** short wow — Broadway neon at night · food pause — Hattie B's hot chicken · local texture — The Bluebird Cafe songwriter round · ending — Opry House show.
**Clusters:** `nash_broadway` · `nash_gulch` · `nash_12south` · `nash_eastnash` · `nash_musicrow`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Broadway honky-tonks (Lower Broadway) | Downtown | 36.1612 | -86.7775 | Tootsies, Robert's, Legends — neon live music strip | TA, GM, Social |
| 2 | Grand Ole Opry House | Opryland | 36.2069 | -86.6923 | The home of country music since 1925 | TA, GM, LP |
| 3 | Ryman Auditorium | Downtown | 36.1613 | -86.7781 | "Mother Church of Country Music"; original Opry venue | TA, GM, LP |
| 4 | Country Music Hall of Fame | Downtown | 36.1583 | -86.7767 | Definitive country music museum | TA, GM, LP |
| 5 | The Parthenon (Centennial Park) | West End | 36.1496 | -86.8133 | Full-scale 1897 replica with 42-ft Athena inside | TA, GM, Social |
| 6 | Johnny Cash Museum | Downtown | 36.1606 | -86.7764 | Best-curated artist-specific museum in US | TA, GM |
| 7 | 12 South / Draper James / Mural wall | 12 South | 36.1228 | -86.7890 | "I Believe in Nashville" mural; walkable boutique row | NYT36, Social |
| 8 | Bluebird Cafe | Green Hills | 36.1053 | -86.8236 | Songwriter-in-the-round; Taylor Swift discovered here | TA, LP |
| 9 | Music Row + RCA Studio B | Music Row | 36.1494 | -86.7920 | Elvis recorded 200+ songs here | TA, LP |
| 10 | Centennial Park | West End | 36.1496 | -86.8133 | Lawn around the Parthenon; picnic central | GM |
| 11 | Nashville Farmers' Market + Bicentennial Capitol Mall | Germantown | 36.1714 | -86.7852 | Farmers market + state capitol walk | LP |
| 12 | Bridgestone Arena + Pedestrian Bridge | Downtown | 36.1592 | -86.7784 | John Seigenthaler Pedestrian Bridge = best skyline view | GM, Social |
| 13 | Assembly Food Hall / Fifth + Broadway | Downtown | 36.1618 | -86.7802 | 30-vendor food hall + rooftop bars | NYT36 |
| 14 | Frist Art Museum | Downtown | 36.1576 | -86.7815 | Art Deco former post office; rotating exhibits | LP |
| 15 | Belle Meade Plantation + Historic Site | West Nashville | 36.0947 | -86.8689 | Antebellum mansion; thoroughbred horse history | TA |

### 2-Hour Driving Tour — "Music Row + River Loop"
1. **Downtown / Broadway + 1st Ave parking** (36.1612, -86.7775) — start.
2. **Shelby Bottoms / Greenway drive along Cumberland River** (36.1731, -86.7540) (~2 mi).
3. Cross to **East Nashville → Main Street** (36.1825, -86.7507) (~1.5 mi).
4. South over Woodland Bridge back downtown (~2 mi).
5. **Music Row Roundabout — Musica statue** (36.1494, -86.7920) (~2 mi).
6. **Belmont University / 12 South mural** (36.1228, -86.7890) (~2.5 mi).
7. West on Edgehill → **Centennial Park / Parthenon** (36.1496, -86.8133) (~3 mi).
8. End driving back down West End / Broadway (~3 mi).

### 4-Hour Walking Tour — "Honky-Tonks + Riverfront"
*~2 mi, flat, best Thursday-Saturday after 4pm for live music overlap.*

1. **Country Music Hall of Fame** (36.1583, -86.7767).
2. **Johnny Cash Museum** (36.1606, -86.7764).
3. 🍗 **Hattie B's Hot Chicken pickup** or **Martin's BBQ** on Demonbreun (36.1585, -86.7788).
4. **Ryman Auditorium tour** (36.1613, -86.7781) — self-guided 45 min.
5. **Broadway honky-tonk crawl** — Robert's Western World → Tootsies → Legends (36.1612, -86.7775).
6. **Acme Feed & Seed rooftop** (36.1626, -86.7750).
7. **John Seigenthaler Pedestrian Bridge** (36.1617, -86.7741) — skyline photo.
8. ☕ **Assembly Food Hall** (36.1618, -86.7802) — pick-your-adventure snack.
9. **Printer's Alley** historic music bars (36.1624, -86.7777).
10. End on **Broadway at dusk** for the full neon blaze.

---

## 11. Austin 🔹

**Summary:** Live Music Capital of the World and barbecue mecca — 6th Street honky-tonks, Lady Bird Lake trails, and the quirky "Keep Austin Weird" ethos center a warm-weather college-town capital. **Strong for:** food-heavy (BBQ), local flavor, music, park/waterfront walks. **Weak for:** architecture, walking in summer heat.
**Signature moments:** short wow — Texas State Capitol dome · food pause — Franklin Barbecue or Terry Black's · local texture — Rainey Street bar district · ending — Congress Bridge bats at dusk · worth the detour — McKinney Falls State Park.
**Clusters:** `atx_downtown` · `atx_southcongress` · `atx_rainey` · `atx_zilker` · `atx_eastside`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Congress Avenue Bridge bats | Downtown | 30.2617 | -97.7454 | World's largest urban bat colony (1.5M) at sunset | TA, GM, Social, NYT36 |
| 2 | 6th Street entertainment district | Downtown | 30.2672 | -97.7413 | Live music strip; college + SXSW epicenter | TA, GM |
| 3 | Texas State Capitol | Downtown | 30.2747 | -97.7404 | Tallest state capitol in US (taller than US Capitol) | TA, LP |
| 4 | Lady Bird Lake + Ann and Roy Butler Trail | Downtown | 30.2620 | -97.7512 | 10-mi loop trail on former Colorado River reservoir | TA, GM, NYT36 |
| 5 | Franklin Barbecue | East Austin | 30.2701 | -97.7313 | Universally top-5 BBQ in America; 3-hour line | TA, Reddit, Social |
| 6 | South Congress Avenue (SoCo) | South Congress | 30.2498 | -97.7500 | I Love You So Much wall, Allens Boots, food trucks | NYT36, Social |
| 7 | Barton Springs Pool | Zilker | 30.2639 | -97.7714 | 3-acre spring-fed pool, 68°F year-round | TA, LP |
| 8 | Zilker Park + Hillside | Zilker | 30.2669 | -97.7728 | Austin's Central Park; ACL Festival home | TA |
| 9 | UT Tower / Texas Memorial Stadium | UT Campus | 30.2861 | -97.7394 | 307-ft 1937 tower visible from all over Austin | LP |
| 10 | Blanton Museum of Art | UT Campus | 30.2804 | -97.7386 | Ellsworth Kelly "Austin" chapel = massive Social draw | NYT36, Social |
| 11 | HOPE Outdoor Gallery / Graffiti Park (Carson Creek) | East Austin | 30.1990 | -97.6330 | Relocated graffiti park; street-art Instagram magnet | Social |
| 12 | Mount Bonnell | Tarrytown | 30.3213 | -97.7731 | Highest point in Austin; Colorado River + Hill Country view | TA, Social |
| 13 | Rainey Street (bungalow bars) | Downtown | 30.2599 | -97.7383 | Converted bungalow bar district | NYT36 |
| 14 | Cathedral of Junk | South Austin | 30.2280 | -97.8038 | Backyard folk-art sculpture; peak Austin weird | Reddit, Social |
| 15 | Bullock Texas State History Museum | Downtown | 30.2796 | -97.7390 | IMAX + Lone Star state narrative | LP |

### 2-Hour Driving Tour — "Hills, River, and Bats"
1. **Mount Bonnell** (30.3213, -97.7731) — start at highest point.
2. Down **Mount Bonnell Rd → FM 2222** scenic (~3 mi).
3. **Lake Austin Blvd along the water** (30.2831, -97.7681) (~2 mi).
4. **Veterans Dr → Zilker Park** (30.2669, -97.7728) (~3 mi).
5. **Barton Springs Rd → South 1st** past food trucks (~2 mi).
6. **South Congress Ave northbound** with skyline ahead (30.2498, -97.7500) (~3 mi).
7. Cross **Congress Ave Bridge at dusk** (30.2617, -97.7454) — bats emerge ~sunset (~0.5 mi).
8. Loop **State Capitol** (30.2747, -97.7404) (~1 mi).
9. End at **Rainey Street bars** (30.2599, -97.7383) (~1 mi).

### 4-Hour Walking Tour — "SoCo + Downtown + Bats at Sunset"
1. **South Congress — Jo's Coffee "I Love You So Much" wall** (30.2499, -97.7500).
2. **Allens Boots** (30.2481, -97.7506).
3. **Hotel San José + Guero's Taco Bar** (30.2467, -97.7505).
4. 🌮 **Torchy's Tacos or Veracruz** food truck pause.
5. Walk north over **S Congress bridge** into downtown (30.2617, -97.7454) — note bat spot.
6. **Texas State Capitol** self-tour (30.2747, -97.7404).
7. **Bullock Museum exterior** (30.2796, -97.7390).
8. **Blanton Museum — Ellsworth Kelly Austin chapel** (30.2804, -97.7386).
9. ☕ **Cosmic Coffee + Beer Garden** detour.
10. **6th Street walk west to east** (30.2672, -97.7413) — live music warm-up.
11. **Rainey Street bungalow bars** (30.2599, -97.7383).
12. Return to **Congress Bridge** for bat emergence at sunset.

---

## 12. Las Vegas 🔹

**Summary:** A 4-mile boulevard of replica world monuments, fountains, and dancing lights — the Strip is a theatrical single-corridor city best experienced as a slow drive at night or a stop-and-duck-inside walk. **Strong for:** night-only tours, photo-heavy at night, efficient drives. **Weak for:** local flavor, family-daytime; heat gates most summer walking.
**Signature moments:** short wow — Bellagio fountain show · night skyline reveal — High Roller observation wheel · local texture — Fremont Street (Old Vegas) · ending — Welcome to Las Vegas sign at dusk · worth the detour — Red Rock Canyon scenic drive.
**Clusters:** `vegas_strip_south` · `vegas_strip_central` · `vegas_strip_north` · `vegas_fremont` · `vegas_redrock`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Bellagio Fountains | The Strip | 36.1126 | -115.1767 | Synchronized water show every 15-30 min; free | TA, GM, Social |
| 2 | The Strip (Las Vegas Blvd S) | Strip | 36.1147 | -115.1728 | The defining cruise; 4 miles of megacasinos | TA, GM |
| 3 | Fremont Street Experience | Downtown | 36.1701 | -115.1428 | Canopy LED screen + old-Vegas neon | TA, GM |
| 4 | Sphere | Paradise | 36.1213 | -115.1661 | 366-ft LED exosphere; newest icon | GM, Social, Reddit |
| 5 | The Venetian — Grand Canal | Strip | 36.1213 | -115.1678 | Indoor canal with gondolas under painted sky | TA, GM, Social |
| 6 | Caesars Palace / Forum Shops | Strip | 36.1162 | -115.1745 | Roman-themed megaresort; fountain-show animatronics | TA |
| 7 | High Roller Observation Wheel | LINQ | 36.1175 | -115.1698 | 550-ft ferris wheel — tallest in W. hemisphere | TA, GM |
| 8 | Neon Museum (Neon Boneyard) | Downtown | 36.1792 | -115.1345 | Restored vintage casino signs | TA, NYT36, Social |
| 9 | Red Rock Canyon Scenic Loop | Red Rock | 36.1366 | -115.4380 | 13-mi loop drive through red sandstone | TA, LP |
| 10 | Hoover Dam | Boulder City (35mi SE) | 36.0161 | -114.7377 | 1935 engineering marvel + Mike O'Callaghan bridge | TA, GM, LP |
| 11 | Paris Las Vegas — Eiffel Tower | Strip | 36.1125 | -115.1716 | Half-scale Eiffel; 46th-floor view deck | TA |
| 12 | MGM Grand / New York-New York skyline | Strip | 36.1027 | -115.1729 | Mini-Manhattan skyline + Brooklyn Bridge replica | GM |
| 13 | Wynn / Encore | Strip | 36.1290 | -115.1651 | Luxury end of Strip; floral atriums | TA |
| 14 | Stratosphere / STRAT SkyPod | North Strip | 36.1474 | -115.1566 | 1,149-ft tower thrill rides | TA |
| 15 | Valley of Fire State Park | 55 mi NE | 36.4860 | -114.5274 | Red sandstone wonderland; best day trip | TA, LP |

### 2-Hour Driving Tour — "The Strip + Fremont Neon"
*Essential LV drive is at night. Traffic crawls — embrace it.*

1. **Mandalay Bay south end** (36.0924, -115.1750) — start at the south pylon.
2. **Las Vegas Blvd northbound**: MGM → NY-NY → Excalibur → Luxor (~1.5 mi).
3. **Paris / Eiffel Tower** (36.1125, -115.1716) — slow past (~0.5 mi).
4. **Bellagio Fountain drive-by at :15/:30 past** (36.1126, -115.1767).
5. **Caesars → Venetian → Wynn** (~2 mi).
6. Cut right on Sahara → **The STRAT** (36.1474, -115.1566) (~1 mi).
7. Continue north on LV Blvd → **Fremont Street parking** (36.1701, -115.1428) (~2 mi).
8. Walk Fremont 15 min for neon canopy.
9. Return via **Main St → Charleston → LV Blvd** loop back to south Strip.

### 4-Hour Walking Tour — "Strip Stop-In Crawl"
*~2.5 mi walking + long indoor crosses. Temperature makes this brutal midday; do evening.*

1. **Bellagio Conservatory + Fountain lobby** (36.1126, -115.1767) — seasonal displays inside.
2. **Bellagio Fountain show** (outside on plaza).
3. **Caesars Palace Forum Shops** (36.1162, -115.1745) — walk through atrium.
4. **High Roller observation wheel** optional (36.1175, -115.1698).
5. 🍽️ **Wahlburgers / Gordon Ramsay Burger / In-N-Out** food stop at LINQ.
6. **The Venetian St. Mark's Square indoor** (36.1213, -115.1678) — gondoliers.
7. **Wynn Conservatory + Lake of Dreams** (36.1290, -115.1651).
8. Rideshare to **Sphere exterior** (36.1213, -115.1661) at night.
9. Rideshare to **Fremont Street** (36.1701, -115.1428) for contrast — old-Vegas neon.
10. **Neon Museum Boneyard** (36.1792, -115.1345) — book evening tour.

---

## 13. San Diego 🔹

**Summary:** Southern California's perfect-weather beach town — Balboa Park, Coronado's cross-bridge view, and La Jolla's sea-lion coves make San Diego a gentle rival to LA with better walkability. **Strong for:** family, scenic sunset, walking, coastal drives. **Weak for:** architecture, deep-history tours.
**Signature moments:** skyline reveal — Coronado Bridge crossing · sunset stop — Sunset Cliffs · short wow — La Jolla Cove sea lions · food pause — Puesto tacos or Hodad's · local texture — Little Italy Mercato.
**Clusters:** `sd_balboa` · `sd_downtown` · `sd_coronado` · `sd_lajolla` · `sd_oceanbeach` · `sd_gaslamp`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Balboa Park (Botanical Building + museums) | Balboa Park | 32.7341 | -117.1443 | 1,200 acres, 17 museums; Spanish Colonial Revival crown | TA, GM, LP |
| 2 | San Diego Zoo | Balboa Park | 32.7353 | -117.1490 | World-leading conservation zoo | TA, GM |
| 3 | USS Midway Museum | Embarcadero | 32.7137 | -117.1751 | Aircraft carrier museum; Unconditional Surrender kiss statue | TA, GM |
| 4 | Coronado Island / Hotel del Coronado | Coronado | 32.6809 | -117.1784 | 1888 Victorian beach resort; Some Like It Hot | TA, GM, Social |
| 5 | La Jolla Cove + Sea Lions | La Jolla | 32.8501 | -117.2720 | Wild sea lions haul out on the rocks; bucket list | TA, GM, Social |
| 6 | Gaslamp Quarter | Downtown | 32.7106 | -117.1596 | Victorian historic district; restaurants + bars | TA, GM |
| 7 | Sunset Cliffs Natural Park | Point Loma | 32.7347 | -117.2560 | Literal cliff-top sunset park; no railings | Social, Reddit |
| 8 | Cabrillo National Monument | Point Loma | 32.6727 | -117.2415 | Lighthouse + panoramic bay view | TA, LP |
| 9 | Old Town San Diego | Old Town | 32.7540 | -117.1978 | Birthplace of California; Mexican food row | TA, LP |
| 10 | Mission Beach + Belmont Park | Mission Beach | 32.7706 | -117.2520 | Boardwalk + 1925 wooden roller coaster | TA |
| 11 | Torrey Pines State Reserve | Torrey Pines | 32.9185 | -117.2525 | Seaside cliffs + rare pines; Black's Beach glider port | LP, Reddit |
| 12 | Little Italy | Little Italy | 32.7230 | -117.1686 | Saturday Mercato farmer's market | NYT36 |
| 13 | Seaport Village / Waterfront Park | Embarcadero | 32.7084 | -117.1711 | Bay walkway, giant rubber ducky photo | TA |
| 14 | Chicano Park murals | Barrio Logan | 32.6987 | -117.1493 | Largest collection of outdoor murals in US | NYT36, Social |
| 15 | Mount Soledad Cross + view | La Jolla | 32.8389 | -117.2472 | 360° view of coastline + bay | Reddit |

### 2-Hour Driving Tour — "Coast + Coronado Loop"
1. **Sunset Cliffs Natural Park** (32.7347, -117.2560) — start for ocean bluffs.
2. **Cabrillo National Monument** (32.6727, -117.2415) (~3 mi).
3. **Shelter Island Drive** harbor view (32.7197, -117.2231) (~4 mi).
4. **Harbor Drive east → Embarcadero** past USS Midway (32.7137, -117.1751) (~4 mi).
5. **Coronado Bridge southbound** (32.7018, -117.1564) (~2 mi).
6. **Orange Ave + Hotel del Coronado** (32.6809, -117.1784) (~2 mi).
7. **Silver Strand Blvd south** ocean views (~3 mi) — optional.
8. Return over Coronado Bridge → **Little Italy** (32.7230, -117.1686).
9. End up at **Mount Soledad** (32.8389, -117.2472) (~8 mi to La Jolla).

### 4-Hour Walking Tour — "Balboa Park + Gaslamp"
1. **Cabrillo Bridge entry to Balboa Park** (32.7306, -117.1485).
2. **El Prado** walk past California Tower (32.7316, -117.1506).
3. **Botanical Building + Lily Pond** (32.7308, -117.1497) — photo.
4. **Spanish Village Art Center** (32.7346, -117.1462).
5. **San Diego Zoo entry** (32.7353, -117.1490) — optional 2-hr detour.
6. ☕ **Prado Restaurant or Panama 66** pause.
7. South on **6th Ave → Bankers Hill → Little Italy** (32.7230, -117.1686) (~1 mi walk).
8. 🍕 **Buona Forchetta or Pappalecco** food stop.
9. **Waterfront Park** (32.7209, -117.1737).
10. **Embarcadero → USS Midway exterior + Kiss statue** (32.7137, -117.1751).
11. **Gaslamp Quarter** evening (32.7106, -117.1596).
12. End at **Seaport Village** (32.7084, -117.1711).

---

## 14. Philadelphia 🔹

**Summary:** America's original capital and the revolutionary history cradle — Independence Hall, the Liberty Bell, Rocky's Art Museum steps, and cheesesteak rivalry in one dense walkable grid. **Strong for:** walking, architecture_historic, first-time (for history-curious), food-heavy. **Weak for:** scenic drives, sunset tours.
**Signature moments:** short wow — Rocky steps at PMA · food pause — Pat's vs Geno's cheesesteak · local texture — Reading Terminal Market · ending — Elfreth's Alley at golden hour · worth the detour — Barnes Foundation.
**Clusters:** `phl_oldcity` · `phl_center` · `phl_parkway` · `phl_fairmount` · `phl_southphl` · `phl_universitycity`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Independence Hall + Liberty Bell | Old City | 39.9489 | -75.1500 | Where the Declaration was signed; Liberty Bell next door | TA, GM, LP |
| 2 | Philadelphia Museum of Art (Rocky Steps) | Fairmount | 39.9656 | -75.1810 | 72 stone steps; Rocky statue at the bottom | TA, GM, Social |
| 3 | Reading Terminal Market | Downtown | 39.9532 | -75.1591 | 1893 indoor public market; the defining Philly food stop | TA, GM, NYT36 |
| 4 | Eastern State Penitentiary | Fairmount | 39.9685 | -75.1722 | 1829 castle prison; Al Capone's cell | TA, Reddit, Social |
| 5 | Rittenhouse Square | Rittenhouse | 39.9495 | -75.1725 | 1682 Penn-plan square; café-lined | TA, NYT36 |
| 6 | Italian Market (9th St) | South Philly | 39.9378 | -75.1570 | Oldest outdoor market in US; Rocky ran here | TA, LP |
| 7 | Magic Gardens (Isaiah Zagar) | South Street | 39.9410 | -75.1590 | Outdoor mosaic labyrinth | TA, Social |
| 8 | Elfreth's Alley | Old City | 39.9528 | -75.1419 | Oldest continuously inhabited street in US (1703) | TA, Social |
| 9 | Love Park / LOVE sculpture | Center City | 39.9538 | -75.1650 | Robert Indiana LOVE = Philly postcard | TA, Social |
| 10 | Boathouse Row (Schuylkill River) | Fairmount | 39.9707 | -75.1861 | Lit-up Victorian boathouses along river | GM, Social |
| 11 | City Hall + Dilworth Park | Center City | 39.9526 | -75.1652 | Tallest masonry building; William Penn statue | TA, LP |
| 12 | Pat's King of Steaks + Geno's | South Philly | 39.9333 | -75.1588 | Cheesesteak rivalry corners of 9th & Passyunk | TA, Reddit |
| 13 | Longwood Gardens (30 mi SW) | Kennett Square | 39.8718 | -75.6744 | Best botanical garden in US on many lists | TA |
| 14 | Benjamin Franklin Parkway | Center City | 39.9598 | -75.1720 | Champs-Élysées inspiration; flag corridor | GM |
| 15 | Betsy Ross House | Old City | 39.9522 | -75.1449 | First-flag legend home | TA, LP |

### 2-Hour Driving Tour — "River to Rocky"
1. **Penn's Landing waterfront** (39.9462, -75.1408) — start.
2. **Columbus Blvd north → Market St** (~2 mi).
3. **Old City — Independence Hall** (39.9489, -75.1500) (~1 mi) drive past.
4. **Arch St → Benjamin Franklin Parkway** flag corridor (~1.5 mi).
5. **Rocky Steps / Philadelphia Museum of Art** (39.9656, -75.1810) — parking lot loop (~1 mi).
6. **Kelly Drive** along Schuylkill past Boathouse Row (39.9707, -75.1861) (~2 mi).
7. **Strawberry Mansion Bridge** (~2 mi).
8. **West River Dr southbound** back through Fairmount (~3 mi).
9. End at **Rittenhouse Square** (39.9495, -75.1725) (~2 mi).

### 4-Hour Walking Tour — "Old City + Reading Terminal"
1. **Independence Hall** (39.9489, -75.1500).
2. **Liberty Bell Center** (39.9496, -75.1503).
3. **Congress Hall + Old City Hall** (39.9491, -75.1497).
4. **Benjamin Franklin's grave** at Christ Church Burial Ground (39.9518, -75.1488).
5. **Elfreth's Alley** (39.9528, -75.1419).
6. **Betsy Ross House** (39.9522, -75.1449).
7. **Christ Church** (39.9516, -75.1446).
8. 🥨 **Reading Terminal Market** (39.9532, -75.1591) — DiNic's roast pork + Bassetts ice cream.
9. **Chinatown gate** (39.9547, -75.1562).
10. **City Hall courtyard + Clothespin** (39.9526, -75.1652).
11. **LOVE Park** (39.9538, -75.1650).
12. End at **Rittenhouse Square** (39.9495, -75.1725).

---

## 15. Charleston 🔹

**Summary:** The South's most beautifully preserved pre-war port — pastel Rainbow Row, palmetto-lined Battery, and a walkable peninsula where every side street yields a wrought-iron gate and a harbor breeze. **Strong for:** romantic, walking, architecture_historic, food-heavy. **Weak for:** scale (small city; 2h can cover it).
**Signature moments:** short wow — Rainbow Row pastel lineup · food pause — Husk or FIG · local texture — Gullah market stands at City Market · ending — Battery sunset · worth the detour — Magnolia Plantation.
**Clusters:** `chs_historic` · `chs_french` · `chs_battery` · `chs_upper`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Rainbow Row | French Quarter | 32.7751 | -79.9287 | 13 pastel Georgian houses on E Bay St | TA, GM, Social |
| 2 | The Battery + White Point Garden | South of Broad | 32.7701 | -79.9300 | Cannon-lined promenade at the harbor tip | TA, GM, LP |
| 3 | Charleston City Market | Downtown | 32.7803 | -79.9312 | Sweetgrass basket vendors since 1804 | TA, GM |
| 4 | Middleton Place + Magnolia Plantation | Ashley River (14 mi NW) | 32.8974 | -80.1378 | Oldest landscaped gardens in US | TA, LP |
| 5 | Fort Sumter | Charleston Harbor | 32.7522 | -79.8749 | Civil War first-shot site; ferry from Liberty Square | TA, GM, LP |
| 6 | King Street (antiques + shopping) | Downtown | 32.7816 | -79.9331 | 2-mi shopping spine | TA, NYT36 |
| 7 | French Quarter (Church + Chalmers Sts) | French Quarter | 32.7767 | -79.9290 | Cobblestone alleys, gas lamps | TA, LP |
| 8 | Pineapple Fountain / Waterfront Park | Waterfront | 32.7773 | -79.9258 | Live oak-lined pier + famous fountain | TA, Social |
| 9 | St. Michael's Church | French Quarter | 32.7764 | -79.9296 | 1761 oldest church in Charleston | LP |
| 10 | Angel Oak Tree | Johns Island (10 mi SW) | 32.7106 | -80.0748 | 400-year-old 66-ft oak; bucket-list photo | TA, Social |
| 11 | Sullivan's Island + Fort Moultrie | Sullivan's Island | 32.7587 | -79.8450 | Laid-back beach + Revolutionary fort | LP |
| 12 | Folly Beach | Folly Beach | 32.6551 | -79.9409 | Laid-back surf town end-of-island beach | TA |
| 13 | Gibbes Museum of Art | Downtown | 32.7793 | -79.9316 | Signature low-country portraiture | LP |
| 14 | Pineapple-topped houses + Philadelphia Alley | French Quarter | 32.7785 | -79.9289 | Classic low-country residential blocks | Social |
| 15 | USS Yorktown / Patriots Point | Mount Pleasant | 32.7910 | -79.9073 | WWII aircraft carrier museum | TA |

### 2-Hour Driving Tour — "Peninsula + Bridge View"
1. **The Battery / White Point Garden** (32.7701, -79.9300) — start.
2. **E Bay St / Rainbow Row** slow pass (32.7751, -79.9287) (~0.5 mi).
3. **Waterfront Park** pull-off (32.7773, -79.9258).
4. **Calhoun St east → Arthur Ravenel Bridge** (32.8031, -79.9126) (~2 mi).
5. Cross to **Mount Pleasant / Patriots Point** (32.7910, -79.9073) — USS Yorktown view (~3 mi).
6. Return via **Coleman Blvd → Shem Creek** (32.7951, -79.8882) (~2 mi).
7. Back over **Ravenel Bridge southbound** for skyline (~2 mi).
8. **East Bay → Market St** past City Market (32.7803, -79.9312) (~1 mi).
9. End at **Colonial Lake** (32.7758, -79.9358).

### 4-Hour Walking Tour — "South of Broad + King Street"
1. **The Battery** (32.7701, -79.9300).
2. **Rainbow Row** (32.7751, -79.9287).
3. **St. Philip's Church + Dock St Theatre** (32.7787, -79.9296).
4. **French Quarter cobblestones** — Chalmers St, Queen St (32.7767, -79.9290).
5. **Pineapple Fountain / Waterfront Park** (32.7773, -79.9258).
6. 🍤 **Hyman's Seafood or 82 Queen** lunch pause.
7. **City Market** (32.7803, -79.9312) — sweetgrass baskets.
8. **Gibbes Museum** (32.7793, -79.9316).
9. **King Street** north stretch shopping (32.7816, -79.9331).
10. ☕ **Callie's Hot Little Biscuit** or **Kudu Coffee**.
11. **Marion Square + Holy City landmarks** (32.7856, -79.9336).
12. End at **Second Sunday on King** if Sunday; else **Charleston Place courtyard**.

---

## 16. Savannah 🔹

**Summary:** 22 moss-draped garden squares, Spanish moss dripping from every oak, and river-port ghost stories — Savannah is America's most atmospheric small city and a walking-tour dream. **Strong for:** walking, romantic, local flavor, architecture_historic. **Weak for:** scenic drives; pure-family (historic cemetery / ghost-tour adult theming).
**Signature moments:** short wow — Forsyth Park fountain · food pause — Leopold's ice cream · local texture — Bonaventure Cemetery · ending — River Street at dusk with a praline.
**Clusters:** `sav_squares` · `sav_riverstreet` · `sav_forsyth` · `sav_starland`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Forsyth Park (fountain) | Historic District | 32.0704 | -81.0958 | 30-acre park with 1858 fountain; the Savannah photo | TA, GM, Social |
| 2 | Historic Squares (Chippewa, Madison, Monterey) | Historic District | 32.0768 | -81.0935 | James Oglethorpe 1733 plan; the defining Savannah feature | TA, LP |
| 3 | River Street | Riverfront | 32.0815 | -81.0910 | Cobblestone + cotton warehouses turned bars | TA, GM |
| 4 | Mercer Williams House | Monterey Sq | 32.0736 | -81.0957 | Midnight in the Garden of Good and Evil house | TA, Social |
| 5 | Bonaventure Cemetery | East Savannah | 32.0418 | -81.0488 | Spanish-moss cemetery; Johnny Mercer, Gracie Watson | TA, LP, Social |
| 6 | Telfair Museums (Jepson + Owens-Thomas) | Historic District | 32.0797 | -81.0933 | Bird Girl statue from Midnight lives here | TA |
| 7 | Cathedral of St. John the Baptist | Historic District | 32.0762 | -81.0899 | Twin-spire Gothic revival cathedral | TA |
| 8 | Wormsloe Historic Site (Oak Avenue) | Isle of Hope | 31.9717 | -81.0666 | 400-oak driveway tunnel = iconic photo | TA, GM, Social |
| 9 | SCAD Museum of Art | Historic District | 32.0770 | -81.0946 | Converted railway depot gallery | LP |
| 10 | Broughton Street | Historic District | 32.0795 | -81.0921 | Shopping/dining main street | TA |
| 11 | Leopold's Ice Cream | Historic District | 32.0795 | -81.0919 | 1919 soda fountain institution | TA, Reddit |
| 12 | Tybee Island Beach + Lighthouse (18 mi E) | Tybee Island | 32.0213 | -80.8457 | Closest beach; 1736 lighthouse | TA |
| 13 | Factors Walk | Riverfront | 32.0813 | -81.0901 | Cobble bluff walk behind Bay Street | LP |
| 14 | Fort Pulaski | Cockspur Island | 32.0283 | -80.8895 | Civil War coastal fort with pristine moat | LP |
| 15 | Mrs. Wilkes Dining Room | Historic District | 32.0752 | -81.0945 | Family-style Southern lunch; line wraps the block | TA, Reddit |

### 2-Hour Driving Tour — "Squares, Moss, and Oaks"
1. **Forsyth Park fountain** (32.0704, -81.0958) — start.
2. **Bull Street north** through the squares (32.0760, -81.0937) (~1 mi).
3. **Johnson Square + City Hall** (32.0800, -81.0912) (~0.3 mi).
4. **River Street bluff view** (32.0815, -81.0910) (~0.5 mi).
5. **Victory Dr east** → **Bonaventure Cemetery** (32.0418, -81.0488) (~5 mi).
6. Walk the moss-draped lanes 10 min.
7. Back west via **Skidaway Rd → Wormsloe Historic Site oak avenue** (31.9717, -81.0666) (~7 mi).
8. Return to **Forsyth Park** via **Abercorn** (~9 mi).

### 4-Hour Walking Tour — "Squares Crawl + River Street"
*~2.5 mi of shade + benches. Savannah's walking tour is arguably the best in America.*

1. **Forsyth Park fountain** (32.0704, -81.0958).
2. **Monterey Square + Mercer Williams House** (32.0736, -81.0957).
3. **Madison Square** (32.0746, -81.0946).
4. **Chippewa Square (Forrest Gump bench site)** (32.0762, -81.0943).
5. 🍨 **Leopold's Ice Cream** pause (32.0795, -81.0919).
6. **Wright Square** (32.0778, -81.0927).
7. **Cathedral of St. John the Baptist** (32.0762, -81.0899).
8. **Reynolds Square + Planters Inn** (32.0795, -81.0909).
9. **City Market** (32.0795, -81.0942) — food + art stalls.
10. **River Street via Factors Walk steps** (32.0815, -81.0910).
11. 🍤 🍺 **River House Seafood or Huey's** early dinner.
12. End at **Emmet Park bluff** (32.0820, -81.0889) at dusk.

---

## 17. Santa Fe 🔹

**Summary:** America's oldest state capital at 7,200 ft — Pueblo-Revival adobe architecture, green chile on everything, and the largest art market in the US per capita. **Strong for:** walking, architecture (Pueblo Revival), food-heavy (green chile), local flavor. **Weak for:** family with young kids, skyline photography.
**Signature moments:** short wow — Loretto Chapel staircase · food pause — The Shed or La Choza · local texture — Canyon Road gallery walk · ending — Cross of the Martyrs sunset over the town.
**Clusters:** `sf_plaza` · `sf_canyonroad` · `sf_railyard` · `sf_museumhill`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Santa Fe Plaza | Downtown | 35.6874 | -105.9378 | 400-year-old central plaza; Palace of Governors portal | TA, GM, LP |
| 2 | Georgia O'Keeffe Museum | Downtown | 35.6879 | -105.9411 | Only museum dedicated to a female American master | TA, GM |
| 3 | Loretto Chapel (Miraculous Staircase) | Downtown | 35.6859 | -105.9378 | Mystery spiral staircase with no visible support | TA, Social |
| 4 | Canyon Road gallery walk | Eastside | 35.6847 | -105.9275 | Half-mile adobe strip with 80+ art galleries | TA, LP |
| 5 | Meow Wolf (House of Eternal Return) | Siler Rd | 35.6743 | -106.0011 | Immersive art installation; the viral SF export | TA, Social, Reddit |
| 6 | San Miguel Chapel | Barrio de Analco | 35.6852 | -105.9373 | Oldest church structure in US (c. 1610) | TA, LP |
| 7 | Cathedral Basilica of St. Francis of Assisi | Downtown | 35.6866 | -105.9364 | Romanesque sandstone; Lamy's cathedral | TA |
| 8 | New Mexico Museum of Art | Plaza | 35.6880 | -105.9391 | 1917 Pueblo Revival template building | LP |
| 9 | Museum Hill (Folk Art + Indian Arts) | SE Santa Fe | 35.6598 | -105.9229 | 4 museums in one complex with mountain views | TA, LP |
| 10 | Palace of the Governors | Plaza | 35.6880 | -105.9378 | 1610 oldest public building in US | TA, LP |
| 11 | Railyard District + Farmers' Market | Railyard | 35.6838 | -105.9486 | Saturday farmers market + SITE art museum | NYT36 |
| 12 | Bandelier National Monument (45 mi NW) | Los Alamos area | 35.7780 | -106.2709 | Ancestral Pueblo cliff dwellings | TA, LP |
| 13 | Ten Thousand Waves Spa | Foothills | 35.7317 | -105.8803 | Mountain Japanese onsen-style retreat | LP, Reddit |
| 14 | Santuario de Chimayó (25 mi N) | Chimayó | 36.0006 | -105.9294 | "Lourdes of America" healing dirt pilgrimage | TA, LP |
| 15 | Cross of the Martyrs overlook | Downtown | 35.6929 | -105.9380 | Sunset skyline view of adobe city | Social |

### 2-Hour Driving Tour — "High Road Glimpse"
1. **Santa Fe Plaza** (35.6874, -105.9378) — start.
2. **Alameda → Canyon Road** (35.6847, -105.9275) (~1 mi).
3. East on **Upper Canyon Rd** into foothills (~2 mi).
4. **Hyde Park Rd / Ski Santa Fe start** (35.7583, -105.8250) (~7 mi, fast gain elevation).
5. Return via **Bishop's Lodge Rd** (~6 mi).
6. **Cross of the Martyrs overlook** (35.6929, -105.9380) — city photo.
7. West to **Meow Wolf / Siler Road** (35.6743, -106.0011) (~3 mi) — exterior or ticketed entry.
8. End at **Railyard district + farmers market** (35.6838, -105.9486).

### 4-Hour Walking Tour — "Plaza + Canyon Road"
*~2 mi at altitude — hydrate. Best late afternoon for gallery openings on Canyon Rd (Fridays).*

1. **Santa Fe Plaza** (35.6874, -105.9378).
2. **Palace of the Governors portal** (35.6880, -105.9378) — Native American vendors.
3. **Cathedral Basilica of St. Francis** (35.6866, -105.9364).
4. **Loretto Chapel + staircase** (35.6859, -105.9378).
5. **San Miguel Chapel** (35.6852, -105.9373).
6. **Oldest House** (35.6851, -105.9375).
7. 🌮 **The Shed or La Choza** green chile lunch (35.6862, -105.9395).
8. **Georgia O'Keeffe Museum** (35.6879, -105.9411).
9. Walk east on **Alameda** along river.
10. **Canyon Road gallery crawl** (35.6847, -105.9275) — Morning Star, Nedra Matteucci, 80+ galleries.
11. ☕ **Kakawa Chocolate House** (35.6849, -105.9357).
12. Return to **Cross of the Martyrs** (35.6929, -105.9380) for sunset adobe view.

---

## 18. Portland, OR 🔹

**Summary:** The Pacific Northwest's quirky counterweight — Forest Park in the city limits, food-cart pods, craft beer gardens, and short drives to waterfalls and volcano views. **Strong for:** food-heavy (cart pods), local flavor, hidden gems, nature day-trips. **Weak for:** architecture, classic first-time tours.
**Signature moments:** short wow — Powell's City of Books · food pause — Pine State Biscuits or Nong's Khao Man Gai · local texture — Alberta Arts 3rd Thursday · worth the detour — Multnomah Falls (30 mi east).
**Clusters:** `pdx_downtown` · `pdx_pearl` · `pdx_alberta` · `pdx_hawthorne` · `pdx_gorge`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Powell's City of Books | Pearl District | 45.5230 | -122.6814 | Largest independent bookstore in the world | TA, GM, LP |
| 2 | Multnomah Falls (30 mi E) | Columbia Gorge | 45.5762 | -122.1158 | 620-ft tallest waterfall in Oregon | TA, GM, Social |
| 3 | Portland Japanese Garden | Washington Park | 45.5189 | -122.7079 | Top-rated Japanese garden outside Japan | TA, LP |
| 4 | International Rose Test Garden | Washington Park | 45.5193 | -122.7073 | 10,000 roses + Mt. Hood view | TA, GM |
| 5 | Pittock Mansion | Forest Heights | 45.5254 | -122.7162 | 1914 chateau; best skyline + Hood view | TA, Social |
| 6 | Voodoo Doughnut / Blue Star | Downtown | 45.5227 | -122.6732 | Pink-box doughnut pilgrimage | TA, Social |
| 7 | Lan Su Chinese Garden | Chinatown | 45.5259 | -122.6731 | Suzhou-style walled garden | TA, LP |
| 8 | Washington Park + Hoyt Arboretum | West | 45.5211 | -122.7147 | 410-acre park with lightrail | LP |
| 9 | Forest Park (Wildwood Trail) | NW | 45.5600 | -122.7500 | Largest urban forest in US (5,200 acres) | TA, Reddit |
| 10 | Portland Saturday Market | Old Town | 45.5232 | -122.6698 | Nation's largest continuously operating outdoor arts market | TA |
| 11 | Tom McCall Waterfront Park | Downtown | 45.5187 | -122.6713 | River-facing park + Saturday market | GM |
| 12 | Alberta Arts District | NE | 45.5587 | -122.6442 | Gallery + mural district | NYT36 |
| 13 | Mississippi Ave / Division St food scene | Various | 45.5540 | -122.6746 | Food-cart pods + craft brewery rows | NYT36, Reddit |
| 14 | Oregon Museum of Science & Industry | Central Eastside | 45.5083 | -122.6654 | OMNIMAX + USS Blueback sub | TA |
| 15 | Columbia River Gorge Scenic Highway | 25-40 mi E | 45.5859 | -122.1180 | Historic Hwy 30 waterfall strip | TA, LP |

### 2-Hour Driving Tour — "West Hills + Gorge Teaser"
1. **Pittock Mansion** (45.5254, -122.7162) — start with skyline+Hood view.
2. **W Burnside down to Washington Park** (45.5189, -122.7079) (~2 mi).
3. **Rose Garden + Japanese Garden exterior** (45.5193, -122.7073).
4. **Skyline Blvd north ridge drive** (45.5434, -122.7362) (~6 mi).
5. Down Cornell → **Thurman St / NW 23rd** (~4 mi).
6. **Broadway Bridge** across river (~1.5 mi).
7. East on **Broadway → Alberta Arts District** (45.5587, -122.6442) (~3 mi).
8. **MLK south → Hawthorne Bridge** back downtown (~3 mi).
9. End at **Tom McCall Waterfront Park** (45.5187, -122.6713).

### 4-Hour Walking Tour — "Pearl District + Waterfront"
1. **Powell's City of Books** (45.5230, -122.6814) — browse 45 min.
2. **Pearl District walk east** on NW 11th.
3. ☕ **Stumptown Coffee or Ristretto Roasters** (45.5236, -122.6815).
4. **Pine Street Market food hall** (45.5225, -122.6711).
5. **Portland Saturday Market** (45.5232, -122.6698) if weekend.
6. **Burnside Bridge** east over Willamette (45.5235, -122.6690).
7. **Lan Su Chinese Garden** (45.5259, -122.6731).
8. 🍩 **Voodoo Doughnut** (45.5227, -122.6732).
9. **Tom McCall Waterfront Park** south walk (45.5187, -122.6713).
10. **Tilikum Crossing pedestrian bridge** (45.5051, -122.6688).
11. 🍽️ **Pok Pok or Cartopia food pod** on Hawthorne (45.5121, -122.6584).
12. Return via **Hawthorne Bridge sunset**.

---

## 19. Denver 🔹

**Summary:** Mile High city and gateway to the Rockies — craft beer pioneer with walkable downtown LoDo, Red Rocks Amphitheatre, and quick access to 14,000-ft peaks. **Strong for:** scenic drives (foothills), nature day-trips, food + beer. **Weak for:** compact walking tours of deep history.
**Signature moments:** skyline reveal — Lookout Mountain / Buffalo Bill · short wow — Colorado State Capitol 15th step (exactly 1 mile high) · food pause — Rioja or Wynkoop · ending — Red Rocks Amphitheatre · worth the detour — Mt. Evans Scenic Byway (seasonal, highest paved road in US).
**Clusters:** `den_lodo` · `den_capitol` · `den_rino` · `den_redrocks` · `den_cityp park`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Red Rocks Park + Amphitheatre | Morrison (15 mi W) | 39.6654 | -105.2057 | Natural 9,500-seat sandstone amphitheater | TA, GM, LP |
| 2 | Union Station (Crawford Hotel) | LoDo | 39.7527 | -105.0010 | Restored 1881 rail terminal; food + hotel + Amtrak | TA, NYT36 |
| 3 | Denver Art Museum | Golden Triangle | 39.7372 | -104.9897 | Libeskind-designed spire building | TA, LP |
| 4 | 16th Street Mall | Downtown | 39.7467 | -104.9992 | Pedestrian/transit mile through downtown | TA |
| 5 | Larimer Square | LoDo | 39.7479 | -105.0001 | Oldest block in Denver; string lights | TA, NYT36 |
| 6 | Denver Botanic Gardens | Cheesman Park | 39.7317 | -104.9611 | 24-acre city garden | TA, LP |
| 7 | Mount Evans Scenic Byway (55 mi W, seasonal) | Clear Creek | 39.5883 | -105.6438 | Highest paved road in North America (14,130 ft) | TA, Reddit |
| 8 | RiNo Arts District (murals) | River North | 39.7700 | -104.9831 | Crush Walls street-art district | NYT36, Social |
| 9 | Coors Field | LoDo | 39.7559 | -104.9942 | Mile-high MLB ballpark; view of Rockies | TA |
| 10 | Civic Center Park + State Capitol | Golden Triangle | 39.7392 | -104.9848 | Golden-dome Capitol; 15th step = exactly 1 mile high | TA, LP |
| 11 | Denver Museum of Nature & Science | City Park | 39.7475 | -104.9428 | T-rex + IMAX + Mount Evans view off roof | TA |
| 12 | Washington Park | South | 39.6969 | -104.9720 | 165-acre classic urban park | GM |
| 13 | Confluence Park | Platte River | 39.7548 | -105.0078 | Where Cherry Creek meets S Platte; kayak chute | GM, Social |
| 14 | Tattered Cover Bookstore | Colfax | 39.7400 | -104.9700 | Iconic independent bookstore | TA |
| 15 | Molly Brown House Museum | Capitol Hill | 39.7385 | -104.9801 | Titanic survivor's Victorian | LP |

### 2-Hour Driving Tour — "Foothills + Red Rocks"
1. **Union Station** (39.7527, -105.0010) — start.
2. **I-25 north briefly → 6th Ave west** (~6 mi).
3. **Colfax / Dinosaur Ridge / Red Rocks** (39.6654, -105.2057) (~15 mi).
4. Loop the **amphitheatre stage** (driveable except concert nights).
5. **Lookout Mountain / Buffalo Bill Museum** (39.7320, -105.2390) (~7 mi).
6. Return via **6th Ave → I-25** (~12 mi).
7. **RiNo Arts District** mural drive (39.7700, -104.9831) (~3 mi).
8. End at **Larimer Square** (39.7479, -105.0001).

### 4-Hour Walking Tour — "LoDo + Capitol Hill + RiNo"
1. **Union Station Great Hall** (39.7527, -105.0010).
2. **Wynkoop Brewing Company** (39.7531, -104.9989) — founder: John Hickenlooper.
3. **Coors Field exterior + The Rockies Rooftop** (39.7559, -104.9942).
4. **Larimer Square** (39.7479, -105.0001) — lights.
5. 🍽️ **Rioja or Tamayo** lunch pause.
6. **16th Street Mall walk south** (~0.8 mi).
7. **Civic Center Park + State Capitol 15th step** (39.7392, -104.9848) — Mile High marker.
8. **Denver Art Museum exterior (Libeskind)** (39.7372, -104.9897).
9. Rideshare or walk 15 min to **RiNo Arts District**.
10. **Larimer St mural crawl** (39.7700, -104.9831).
11. ☕ **Huckleberry Roasters** or Ratio Beerworks.
12. End at **Confluence Park** sunset (39.7548, -105.0078).

---

## 20. Honolulu / Oahu 🔹

**Summary:** Waikiki's beach crescent + Diamond Head + Pearl Harbor + North Shore surf in one hour-wide island — Oahu is the accessible Hawaiian experience at scale. **Strong for:** scenic sunset drives, family, iconic driving (island circumnavigation), beach photography. **Weak for:** walking-only tours (Waikiki aside).
**Signature moments:** short wow — Diamond Head summit · sunset stop — Magic Island · food pause — Leonard's malasadas · ending — North Shore sunset at Sunset Beach · worth the detour — Kualoa Regional Park ridges (Jurassic Park filming).
**Clusters:** `oahu_waikiki` · `oahu_diamondhead` · `oahu_pearlharbor` · `oahu_northshore` · `oahu_windward` · `oahu_leeward`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Waikiki Beach | Waikiki | 21.2793 | -157.8294 | 2-mi crescent with Diamond Head framing | TA, GM |
| 2 | Diamond Head State Monument | Kahala | 21.2620 | -157.8058 | 760-ft crater hike; bucket-list Oahu summit | TA, GM, LP |
| 3 | Pearl Harbor National Memorial (USS Arizona) | Pearl City | 21.3649 | -157.9507 | Dec 7 1941 site; floating memorial over sunken battleship | TA, GM, LP |
| 4 | Hanauma Bay | East Oahu | 21.2690 | -157.6938 | Volcanic-crater snorkel bay; reservations required | TA, LP |
| 5 | North Shore (Pipeline + Waimea Bay) | Haleiwa | 21.6408 | -158.0514 | Winter big-wave surf capital | TA, LP, Social |
| 6 | Dole Plantation | Wahiawa | 21.5263 | -158.0378 | Pineapple maze + train ride | TA |
| 7 | Polynesian Cultural Center | Laie | 21.6410 | -157.9245 | 6 Pacific villages + canoe show | TA, LP |
| 8 | Iolani Palace | Downtown Honolulu | 21.3068 | -157.8583 | Only royal palace on US soil | TA, LP |
| 9 | Byodo-In Temple | Kaneohe | 21.4327 | -157.8276 | Replica of 1,000-yr Japanese temple | TA, Social |
| 10 | Lanikai Beach | Kailua | 21.3928 | -157.7147 | Powder-sugar sand; Mokulua island view | TA, Social |
| 11 | Nuuanu Pali Lookout | Windward | 21.3666 | -157.7932 | Cliff viewpoint of Koolau mountains | TA, LP |
| 12 | Chinatown Honolulu | Downtown | 21.3120 | -157.8610 | Oldest Chinatown in US | LP, NYT36 |
| 13 | Magic Island / Ala Moana Beach | Ala Moana | 21.2897 | -157.8514 | Sunset photo of Diamond Head from the west | GM, Social |
| 14 | Makapu'u Point Lighthouse | East Oahu | 21.3107 | -157.6497 | 2-mi paved coastal hike | TA |
| 15 | Halona Blowhole + From Here to Eternity Beach | East Oahu | 21.2817 | -157.6719 | Sea blowhole + classic movie cove | GM, Social |

### 2-Hour Driving Tour — "East Shore Loop"
1. **Waikiki / Kalakaua Ave start** (21.2793, -157.8294).
2. **Diamond Head crater exterior drive** (21.2620, -157.8058) (~3 mi).
3. **Kahala Ave coastal** → **Hawaii Kai** (~6 mi).
4. **Hanauma Bay lookout** (21.2690, -157.6938) (~4 mi).
5. **Halona Blowhole** (21.2817, -157.6719) (~2 mi).
6. **Sandy Beach + Makapu'u overlook** (21.3107, -157.6497) (~3 mi).
7. **Pali Highway scenic return** via **Nuuanu Pali Lookout** (21.3666, -157.7932) (~8 mi).
8. End back on H-1 to **Ala Moana Beach Park / Magic Island** (21.2897, -157.8514) for sunset (~10 mi).

### 4-Hour Walking Tour — "Waikiki + Diamond Head + Kalakaua"
1. **Duke Kahanamoku statue + Waikiki Beach** (21.2757, -157.8243).
2. ☕ **Island Vintage Coffee** (21.2770, -157.8270).
3. **Royal Hawaiian Center + Pink Palace** (21.2762, -157.8279).
4. **Waikiki Wall / Kapahulu Groin** — surfers photo (21.2721, -157.8222).
5. **Diamond Head trailhead** via Monsarrat Ave (21.2620, -157.8058) — 1.5 hr hike.
6. Return to Waikiki.
7. 🥤 **Leonard's Malasadas truck or poke bowl**.
8. **Kalakaua Ave** shopping walk (21.2793, -157.8294).
9. **Waikiki Beach sunset** (21.2793, -157.8294).
10. **Moana Surfrider Hotel banyan tree + Mai Tai Bar** (21.2769, -157.8267).
11. End with **torch lighting ceremony** at Kuhio Beach (21.2728, -157.8245).

---

## 21. Key West 🔹

**Summary:** Southernmost point in the continental US — a 4-sq-mile conch-republic island of Hemingway's six-toed cats, Duval Street bars, and Mallory Square sunsets. **Strong for:** walking, sunset, local flavor, 2h efficient. **Weak for:** architecture tours in the classical sense; family at adult-bar blocks of Duval.
**Signature moments:** short wow — Southernmost Point marker · food pause — Blue Heaven · local texture — Mallory Square sunset celebration · ending — Mallory Square at golden hour · worth the detour — Fort Zachary Taylor Beach.
**Clusters:** `kw_oldtown` · `kw_duval` · `kw_mallory` · `kw_fort_zach`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Southernmost Point Buoy | South Key West | 24.5465 | -81.7975 | "90 miles to Cuba" photo-op buoy | TA, GM, Social |
| 2 | Mallory Square Sunset Celebration | Old Town | 24.5603 | -81.8074 | Nightly sunset + street performers | TA, GM |
| 3 | Ernest Hemingway Home | Old Town | 24.5515 | -81.8000 | 40+ six-toed cats, Hemingway's writing studio | TA, GM, LP |
| 4 | Duval Street | Old Town | 24.5551 | -81.8010 | 1.25-mi bar/shop spine end-to-end | TA, GM |
| 5 | Sloppy Joe's Bar | Duval | 24.5582 | -81.8040 | Hemingway's original hangout | TA |
| 6 | Dry Tortugas National Park (ferry) | 70 mi W | 24.6277 | -82.8732 | Fort Jefferson + pristine reefs | TA, LP |
| 7 | Fort Zachary Taylor State Park | Truman Annex | 24.5465 | -81.8105 | Civil War fort + best public beach in KW | TA |
| 8 | Key West Butterfly & Nature Conservatory | Duval | 24.5489 | -81.7993 | Glass dome with 50+ species free-flying | TA |
| 9 | Truman Little White House | Old Town | 24.5542 | -81.8080 | Truman's winter retreat | TA, LP |
| 10 | Key West Lighthouse | Old Town | 24.5513 | -81.8004 | Climb 88 steps for island view | TA |
| 11 | Smathers Beach | South | 24.5467 | -81.7692 | Half-mile sand strip; watersports | TA |
| 12 | Key West Cemetery | Old Town | 24.5549 | -81.7964 | Above-ground graves with famously funny epitaphs | LP |
| 13 | Harry S Truman Waterfront Park | West | 24.5542 | -81.8087 | New park + ferry dock | GM |
| 14 | Conch Tour Train | Old Town | 24.5594 | -81.8045 | Classic narrated tour; been running since 1958 | TA |
| 15 | The Gardens Hotel / Peacock Courtyard | Old Town | 24.5542 | -81.8025 | Lush botanical hotel; public lunch | LP |

### 2-Hour Driving Tour — "Old Town Loop + Higgs Beach"
1. **Southernmost Point Buoy** (24.5465, -81.7975) — start.
2. **Duval St south-to-north slow drive** (~1.3 mi).
3. **Mallory Square** (24.5603, -81.8074) — park briefly.
4. **Caroline St / Historic Seaport** (24.5598, -81.8053) (~0.5 mi).
5. **Roosevelt Blvd east along ocean** (24.5540, -81.7610) (~3 mi).
6. **Smathers Beach pull-off** (24.5467, -81.7692).
7. **Atlantic Blvd → Higgs Beach** (24.5472, -81.7902) (~2.5 mi).
8. End at **Fort Zachary Taylor State Park** (24.5465, -81.8105) for sunset (~2 mi).

### 4-Hour Walking Tour — "Duval End-to-End"
*Classic KW on foot. ~2.5 mi, very flat, very hot — stay hydrated, duck into AC frequently.*

1. **Southernmost Point Buoy** (24.5465, -81.7975) — start south.
2. **Ernest Hemingway Home** (24.5515, -81.8000) — 45-min tour.
3. **Key West Lighthouse** (24.5513, -81.8004).
4. **Duval St** north — stop at **Butterfly Conservatory** (24.5489, -81.7993).
5. 🍹 **Sloppy Joe's or Capt Tony's Saloon** (24.5582, -81.8040).
6. **Kermit's Key Lime Shoppe** detour (24.5598, -81.8053).
7. **Historic Seaport boardwalk** (24.5598, -81.8053).
8. 🍤 **Half Shell Raw Bar or Conch Republic** seafood pause.
9. **Mallory Square** arriving an hour before sunset (24.5603, -81.8074).
10. **Truman Little White House** (24.5542, -81.8080).
11. End at **Mallory Square Sunset Celebration**.

---

## 22. Asheville 🔹

**Summary:** Blue Ridge Mountains foothills with America's largest home (Biltmore), a deep craft-brewery scene, and an arts-and-craft river district — outdoor adventure plus urban weirdness. **Strong for:** scenic drives (Blue Ridge Parkway), food + beer, local flavor. **Weak for:** major-icon walking tours.
**Signature moments:** short wow — Biltmore Estate façade · food pause — Buxton Hall BBQ or Cúrate · local texture — River Arts District studios · scenic drive — Blue Ridge Parkway milepost 384 sunset.
**Clusters:** `avl_downtown` · `avl_biltmore` · `avl_rad` · `avl_southslope` · `avl_brp`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Biltmore Estate | South Asheville | 35.5401 | -82.5515 | Largest private home in America (250 rooms, 8,000 acres) | TA, GM, LP |
| 2 | Blue Ridge Parkway | Surrounds city | 35.5892 | -82.3776 | "America's Favorite Drive"; 469 mi total | TA, GM, LP |
| 3 | Downtown Asheville | Downtown | 35.5946 | -82.5540 | Art Deco + walkable indie retail | TA, NYT36 |
| 4 | River Arts District (RAD) | West | 35.5836 | -82.5717 | Former industrial riverfront; artist studios | NYT36, Social |
| 5 | Grove Park Inn | North | 35.6168 | -82.5370 | 1913 arts-and-crafts resort; sunset terrace view | TA, LP |
| 6 | Chimney Rock State Park (25 mi SE) | Chimney Rock | 35.4321 | -82.2504 | 315-ft monolith; Last of the Mohicans | TA, LP |
| 7 | Sierra Nevada Brewery (Mills River) | 15 mi S | 35.4004 | -82.5665 | Tap tour + gardens | TA |
| 8 | Basilica of Saint Lawrence | Downtown | 35.5970 | -82.5548 | 1909 self-supporting tile dome | LP |
| 9 | Folk Art Center / Allanstand | Blue Ridge Pkwy | 35.5878 | -82.4558 | Southern Highland Craft Guild home | TA |
| 10 | North Carolina Arboretum | SW | 35.5068 | -82.6022 | 434 acres of bonsai + native gardens | TA |
| 11 | French Broad River Greenway | West | 35.5846 | -82.5760 | River walking + kayak launches | LP |
| 12 | Black Mountain (15 mi E) | Black Mountain | 35.6176 | -82.3215 | Cute adjacent town; Seven Sisters view | Reddit |
| 13 | Thomas Wolfe Memorial | Downtown | 35.5961 | -82.5510 | "Look Homeward Angel" boyhood boardinghouse | LP |
| 14 | Craggy Gardens / Mt. Mitchell (25 mi NE) | BRP | 35.6988 | -82.3805 | Highest peak east of Mississippi (6,684 ft) | TA, LP |
| 15 | Asheville Pinball Museum / South Slope breweries | Downtown | 35.5920 | -82.5548 | 75+ playable pinball + brewery crawl | Reddit |

### 2-Hour Driving Tour — "Blue Ridge + Grove Park"
1. **Downtown Asheville** (35.5946, -82.5540) — start.
2. **Tunnel Rd → Blue Ridge Parkway south entrance** (~5 mi).
3. **BRP northbound** — stop at **Craggy Gardens Visitor Center** optional (35.6988, -82.3805) (~20 mi, 35 min).
4. Short loops OK — minimum: **Folk Art Center** (35.5878, -82.4558).
5. Exit at **US-70 → Grove Park Inn** (35.6168, -82.5370) sunset terrace (~7 mi).
6. Back downtown via **Charlotte St** (~2 mi).
7. **South to Biltmore Village** (35.5690, -82.5483) (~3 mi).
8. **Biltmore Estate entry gate** drive-past (35.5401, -82.5515) (~2 mi).

### 4-Hour Walking Tour — "Downtown + South Slope + RAD"
1. **Pritchard Park** (35.5951, -82.5546) — start near the drum circle square.
2. **Vance Monument + Battery Park Ave** (35.5950, -82.5540).
3. **Thomas Wolfe Memorial** (35.5961, -82.5510).
4. **Grove Arcade** (35.5957, -82.5561) — 1929 shopping arcade.
5. **Basilica of Saint Lawrence** (35.5970, -82.5548).
6. ☕ **Double D's Coffee bus** or **Old Europe**.
7. **South Slope brewery cluster** — Hi-Wire, Burial, Wicked Weed (35.5906, -82.5521).
8. 🍺 Choose one flight.
9. Rideshare to **River Arts District** (35.5836, -82.5717) or walk 25 min.
10. **12 Bones Smokehouse** optional detour (35.5892, -82.5706).
11. Studio crawl around **Roberts St** (35.5845, -82.5717).
12. End at **Wedge Brewing** along French Broad (35.5913, -82.5690).

---

## 23. Minneapolis 🔹

**Summary:** City of Lakes with 22 freshwater lakes inside city limits, Mississippi River rapids, and a Scandinavian-rooted arts scene anchored by Walker Art Center's Spoonbridge sculpture. **Strong for:** park/lakeside walks, architecture (Guthrie Theater cantilever), sculpture photography. **Weak for:** winter outdoor (8 months of cold).
**Signature moments:** short wow — Spoonbridge and Cherry · food pause — Matt's Bar Jucy Lucy · local texture — Minneapolis Farmers Market · scenic — Stone Arch Bridge at sunset.
**Clusters:** `mpls_downtown` · `mpls_northeast` · `mpls_uptown` · `mpls_chain-of-lakes` · `mpls_mill_district`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Minneapolis Sculpture Garden — Spoonbridge & Cherry | Loring Park | 44.9698 | -93.2890 | Claes Oldenburg icon; Walker's free outdoor wing | TA, GM, Social |
| 2 | Stone Arch Bridge | Mill District | 44.9808 | -93.2568 | 1883 curved limestone railway bridge | TA, GM, Social |
| 3 | St. Anthony Falls + Mill City Museum | Mill District | 44.9796 | -93.2562 | Only major waterfall on Mississippi; flour-milling history | TA, LP |
| 4 | Walker Art Center | Loring Park | 44.9691 | -93.2881 | Top contemporary art museum in the Midwest | TA, LP |
| 5 | Chain of Lakes — Bde Maka Ska | Uptown | 44.9400 | -93.3117 | City's largest lake; walking/biking loop | TA, GM |
| 6 | Minnehaha Falls | South | 44.9156 | -93.2108 | 53-ft urban waterfall; Longfellow's Hiawatha | TA, Social |
| 7 | Mall of America | Bloomington | 44.8548 | -93.2422 | Largest mall in US; indoor theme park | TA |
| 8 | U.S. Bank Stadium + The Commons | Downtown East | 44.9736 | -93.2575 | Vikings glass stadium | TA |
| 9 | Minneapolis Institute of Art (Mia) | Whittier | 44.9583 | -93.2749 | Free encyclopedic museum | TA, LP |
| 10 | Guthrie Theater Endless Bridge | Mill District | 44.9790 | -93.2540 | Jean Nouvel cantilever with river view | LP, Social |
| 11 | Nicollet Mall | Downtown | 44.9756 | -93.2727 | Mary Tyler Moore hat-toss statue | TA |
| 12 | Foshay Tower observation deck | Downtown | 44.9748 | -93.2704 | 1929 obelisk tower; Washington Monument of the Prairie | LP |
| 13 | Chain of Lakes — Lake of the Isles | Uptown | 44.9588 | -93.3040 | Adjacent lake with walkable loop | GM |
| 14 | Mississippi Gorge + Father Hennepin Bluff | Mill District | 44.9833 | -93.2540 | Best skyline+falls photo | Social, Reddit |
| 15 | Midtown Global Market | Phillips | 44.9483 | -93.2608 | International food hall | NYT36 |

### 2-Hour Driving Tour — "River + Lakes Loop"
1. **Stone Arch Bridge lot** (44.9808, -93.2568) — start.
2. **Main St SE → University / Dinkytown** (~2 mi).
3. **Como Ave → St. Anthony Main** (44.9851, -93.2546) (~1 mi).
4. **Mississippi River Blvd south** past gorge (~4 mi).
5. **Minnehaha Parkway west** (~4 mi).
6. **Minnehaha Falls Park** (44.9156, -93.2108) (~0.5 mi).
7. Continue **parkway around Lake Nokomis → Bde Maka Ska** (44.9400, -93.3117) (~6 mi).
8. Up **Hennepin Ave** → **Walker Sculpture Garden** (44.9698, -93.2890) (~3 mi).
9. End at **Nicollet Mall / Mary Tyler Moore statue** (44.9756, -93.2727) (~1 mi).

### 4-Hour Walking Tour — "Mill District Loop"
1. **Gold Medal Park** (44.9780, -93.2540) — start.
2. **Guthrie Theater Endless Bridge** (44.9790, -93.2540).
3. **Mill City Museum exterior** (44.9796, -93.2562).
4. **Stone Arch Bridge** walk across (44.9808, -93.2568).
5. **St. Anthony Main** east bank (44.9851, -93.2546).
6. 🍽️ **Tugg's Tavern or Aster Cafe** riverfront.
7. **Nicollet Island** detour (44.9842, -93.2597).
8. Back across to **Mill Ruins Park** (44.9795, -93.2580).
9. **Washington Ave → US Bank Stadium Commons** (44.9736, -93.2575).
10. ☕ **Spyhouse Coffee** downtown.
11. **Nicollet Mall + Foshay Tower** (44.9748, -93.2704).
12. End at **Walker Sculpture Garden** Spoonbridge (44.9698, -93.2890) via 12-min rideshare.

---

## 24. Atlanta 🔹

**Summary:** Capital of the New South — Civil Rights history, hip-hop royalty, world-class aquarium, and MLK Jr.'s boyhood home make ATL a cultural heavyweight. **Strong for:** first-time highlights with history, food-heavy (southern + global), family (aquarium). **Weak for:** walking-only (sprawl).
**Signature moments:** short wow — MLK Historic Site birthplace · food pause — Busy Bee Cafe or Mary Mac's · local texture — Ponce City Market + BeltLine · ending — Jackson Street Bridge skyline photo.
**Clusters:** `atl_downtown` · `atl_mlk` · `atl_ponce` · `atl_midtown` · `atl_westside`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Georgia Aquarium | Downtown | 33.7634 | -84.3951 | Largest aquarium in the W. hemisphere; whale sharks | TA, GM, LP |
| 2 | World of Coca-Cola | Downtown | 33.7626 | -84.3926 | Coke tasting hall, 100+ global flavors | TA, GM |
| 3 | Martin Luther King Jr. National Historical Park | Sweet Auburn | 33.7556 | -84.3729 | King birth home + Ebenezer Baptist + tomb | TA, GM, LP |
| 4 | BeltLine Eastside Trail | Various | 33.7816 | -84.3700 | 22-mi loop trail on old rail corridor | TA, NYT36, Social |
| 5 | Centennial Olympic Park | Downtown | 33.7608 | -84.3930 | 1996 Olympics legacy park with fountains | TA |
| 6 | Ponce City Market | Old Fourth Ward | 33.7721 | -84.3653 | Former Sears distribution building food hall | NYT36, Social |
| 7 | Piedmont Park | Midtown | 33.7867 | -84.3739 | Atlanta's Central Park; skyline view | TA, GM |
| 8 | Atlanta Botanical Garden | Midtown | 33.7906 | -84.3735 | Orchid collection + canopy walk | TA |
| 9 | High Museum of Art | Midtown | 33.7906 | -84.3856 | Richard Meier + Renzo Piano buildings | TA, LP |
| 10 | Fox Theatre | Midtown | 33.7726 | -84.3854 | 1929 Moorish-Egyptian movie palace | TA |
| 11 | Jackson Street Bridge skyline view | Old Fourth Ward | 33.7609 | -84.3741 | Walking Dead opening credit photo | Social |
| 12 | Stone Mountain (17 mi E) | Stone Mountain | 33.8053 | -84.1456 | Largest granite monolith in the world | TA |
| 13 | College Football Hall of Fame | Downtown | 33.7616 | -84.3946 | Interactive chip tech | TA |
| 14 | Atlanta History Center | Buckhead | 33.8434 | -84.3862 | Cyclorama painting + Swan House | LP |
| 15 | Little Five Points | East Atlanta | 33.7646 | -84.3488 | Indie music/vintage/tattoo hub | Reddit |

### 2-Hour Driving Tour — "Midtown + MLK"
1. **Centennial Olympic Park** (33.7608, -84.3930) — start.
2. **Luckie St → Auburn Ave east** — MLK district (33.7556, -84.3729) (~1.5 mi).
3. **Freedom Parkway east → Little Five Points** (33.7646, -84.3488) (~3 mi).
4. **Ponce de Leon Ave west** (~2 mi).
5. **Ponce City Market exterior** (33.7721, -84.3653).
6. **Monroe Dr north → Piedmont Park** (33.7867, -84.3739) (~2 mi).
7. **Peachtree St south** through Midtown past **Fox Theatre** (33.7726, -84.3854) (~2 mi).
8. End at **Jackson Street Bridge** for skyline sunset (33.7609, -84.3741) (~2 mi).

### 4-Hour Walking Tour — "BeltLine + Ponce City + MLK"
1. **Ponce City Market rooftop + food hall** (33.7721, -84.3653) — start.
2. **BeltLine Eastside Trail south** (33.7718, -84.3656) — mural walk.
3. **Krog Street Market** (33.7546, -84.3616) — another food hall pause.
4. **Krog Street Tunnel** graffiti (33.7557, -84.3629).
5. Rideshare or 20-min walk to **MLK Jr. Historic Park** (33.7556, -84.3729).
6. **Ebenezer Baptist Church Heritage Sanctuary** (33.7554, -84.3731).
7. **King Center / Tomb** (33.7555, -84.3720).
8. **Auburn Avenue Research Library + Sweet Auburn Market** (33.7547, -84.3778).
9. Rideshare to **Centennial Olympic Park** (33.7608, -84.3930).
10. **World of Coca-Cola** (33.7626, -84.3926) — 30 min.
11. **Georgia Aquarium exterior / Skyview Ferris Wheel** (33.7634, -84.3951).
12. End on **Jackson Street Bridge** at sunset (33.7609, -84.3741).

---

## 25. San Antonio 🔹

**Summary:** Historic Spanish missions and the most beloved River Walk in North America — a soft alternative to Austin with serious historical weight (the Alamo). **Strong for:** walking, family, first-time highlights with history, romantic (River Walk night). **Weak for:** scenic drives, architecture_modern.
**Signature moments:** short wow — Alamo façade · food pause — Mi Tierra (24h Tex-Mex) · local texture — Pearl District farmers market · ending — River Walk barge at dusk.
**Clusters:** `sat_alamo` · `sat_riverwalk` · `sat_pearl` · `sat_missions`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | The Alamo | Downtown | 29.4260 | -98.4861 | "Remember the Alamo" 1836 mission-battle site | TA, GM, LP |
| 2 | San Antonio River Walk | Downtown | 29.4260 | -98.4897 | 15-mi urban canal below street level | TA, GM, LP |
| 3 | San Antonio Missions National Historical Park | South | 29.3596 | -98.4709 | 4 Spanish colonial missions; UNESCO site | TA, LP |
| 4 | Mission San José | South | 29.3600 | -98.4780 | "Queen of the Missions" — 1720 Rose Window | TA, LP |
| 5 | Pearl District | North Downtown | 29.4452 | -98.4800 | Converted brewery food hall + weekend market | NYT36, Social |
| 6 | Tower of the Americas | HemisFair Park | 29.4199 | -98.4838 | 750-ft 1968 World's Fair tower | TA |
| 7 | Market Square / El Mercado | Downtown | 29.4251 | -98.4954 | Largest Mexican market in US | TA, LP |
| 8 | San Fernando Cathedral | Downtown | 29.4245 | -98.4930 | Light-show projection "San Antonio: The Saga" | TA, Social |
| 9 | Historic Pearl Farmers Market | Pearl | 29.4456 | -98.4800 | Best farmers market in Texas | NYT36 |
| 10 | Japanese Tea Garden | Brackenridge Park | 29.4641 | -98.4723 | Converted 1917 rock quarry | TA |
| 11 | Brackenridge Park | North | 29.4619 | -98.4745 | Zoo + golf + Japanese garden complex | GM |
| 12 | McNay Art Museum | North | 29.4783 | -98.4668 | First modern-art museum in Texas | LP |
| 13 | King William Historic District | South of Downtown | 29.4144 | -98.4892 | Victorian German immigrant mansions | LP |
| 14 | Mi Tierra Cafe | Market Square | 29.4253 | -98.4956 | 24-hour mariachi restaurant | TA, Reddit |
| 15 | Natural Bridge Caverns (25 mi NE) | Natural Bridge | 29.6927 | -98.3421 | Largest show caverns in TX | TA |

### 2-Hour Driving Tour — "Mission Trail + Pearl"
1. **The Alamo** (29.4260, -98.4861) — start.
2. **Roosevelt Ave south → Mission Trail** (~4 mi).
3. **Mission Concepción** (29.3855, -98.4827) (~1 mi).
4. **Mission San José** (29.3600, -98.4780) (~3 mi).
5. **Mission San Juan** (29.3345, -98.4644) (~2 mi) — optional.
6. Return via **Alamo Plaza → Broadway north** (~5 mi).
7. **Pearl District + Pearl Brewery complex** (29.4452, -98.4800) (~2 mi).
8. End at **Japanese Tea Garden** (29.4641, -98.4723).

### 4-Hour Walking Tour — "River Walk + Alamo + King William"
1. **The Alamo** (29.4260, -98.4861) — start.
2. **Alamo Plaza + Emily Morgan hotel** (29.4263, -98.4858).
3. Descend to **River Walk at Commerce St** (29.4253, -98.4869).
4. **River Walk southbound** to **La Villita Historic Arts Village** (29.4230, -98.4872).
5. **Tower of the Americas base** (29.4199, -98.4838).
6. ☕ **Schilo's Delicatessen or Esquire Tavern** pause.
7. **River Walk north loop** toward downtown.
8. **Market Square / El Mercado** (29.4251, -98.4954).
9. 🌮 **Mi Tierra Cafe** (29.4253, -98.4956) — mandatory.
10. **San Fernando Cathedral + Main Plaza** (29.4245, -98.4930).
11. Rideshare to **Pearl District** (29.4452, -98.4800).
12. End at **Pearl Farmers Market or The Bottling Department food hall**.

---

# EUROPE

---

## 26. London ✅ (v2)

### A. City summary

2,000 years of royal, imperial, and pop culture in one Thames-side megalopolis — Big Ben, Tower Bridge, the West End theaters, and a museum landscape nearly all free to enter.

- **Strongest for:** walking first-time highlights, architecture, romantic evening (Thames bridges lit), food-heavy (Borough Market).
- **Weak for:** driving (Congestion Zone + slow traffic + narrow streets); scenic sunset drives.
- **Unique strength:** museums are free — a 4h walking tour can include 2 world-class museums at zero cost, which reshapes the scoring of variety + story_richness.

### B. Gold-standard stop graph

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | walking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Westminster Bridge + Big Ben view | icon | 10 | 9 | 9 | 15 | light | any | lon_westminster |
| Westminster Abbey | icon | 9 | 8 | 10 | 60 | light | morning | lon_westminster |
| Trafalgar Sq + National Gallery | icon | 9 | 7 | 9 | 45 | light | any | lon_center |
| Covent Garden | neighborhood | 8 | 7 | 8 | 30 | light | any | lon_center |
| St. Paul's Cathedral | icon | 9 | 9 | 10 | 45 | moderate | any | lon_city |
| Millennium Bridge + Tate Modern | viewpoint | 8 | 9 | 8 | 60 | light | afternoon | lon_bankside |
| Borough Market | food | 8 | 7 | 8 | 45 | light | midday | lon_bankside |
| Tower Bridge + Tower of London | icon | 10 | 9 | 10 | 60 | light | afternoon | lon_tower |
| Buckingham Palace (Changing Guard) | icon | 9 | 7 | 9 | 45 | light | morning | lon_westminster |
| British Museum | museum | 9 | 7 | 10 | 120 | light | any | lon_bloomsbury |
| Camden + Primrose Hill | neighborhood | 7 | 8 | 7 | 60 | moderate | golden_hour | lon_north |

**Clusters:** `lon_westminster` · `lon_center` · `lon_city` · `lon_bankside` · `lon_tower` · `lon_bloomsbury` · `lon_north`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Waterloo Bridge looking east — the canonical London Thames view |
| Best sunset stop | Primrose Hill (classic London skyline at golden hour) |
| Best short wow | Millennium Bridge crossing from Tate Modern to St. Paul's |
| Best scenic drive segment | Embankment eastbound from Westminster to Tower |
| Best coffee/food pause | Borough Market (Monmouth Coffee + food stalls) |
| Best local texture | Columbia Road Flower Market (Sundays) |
| Best ending point | Tower Bridge at dusk with lit bascules |
| Best worth-the-detour | Shakespeare's Globe evening performance |

### C. Benchmark tours

Both tours below are strong calibration candidates — **LON-2 (Westminster to Tower) is the candidate gold tour for London**, pending calibration pass.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Big Ben / Houses of Parliament | Westminster | 51.5007 | -0.1246 | The defining London silhouette; Elizabeth Tower | TA, GM, LP |
| 2 | Tower Bridge + Tower of London | Tower Hill | 51.5055 | -0.0754 | Neo-Gothic bascule bridge + Crown Jewels | TA, GM, LP |
| 3 | Buckingham Palace (Changing the Guard) | St. James | 51.5014 | -0.1419 | Royal residence; 11am ceremony on schedule days | TA, GM, LP |
| 4 | British Museum | Bloomsbury | 51.5194 | -0.1270 | Rosetta Stone + Parthenon Marbles; free | TA, GM, LP |
| 5 | Westminster Abbey | Westminster | 51.4993 | -0.1273 | Coronation church since 1066 | TA, GM, LP |
| 6 | Tate Modern | Bankside | 51.5076 | -0.0994 | Massive converted power station; free | TA, LP |
| 7 | Trafalgar Square + National Gallery | Westminster | 51.5080 | -0.1281 | Nelson's Column + free Western-art museum | TA, GM |
| 8 | Covent Garden | West End | 51.5117 | -0.1240 | Victorian market + street performers | TA, NYT36 |
| 9 | Hyde Park / Kensington Gardens | West London | 51.5073 | -0.1657 | 350-acre royal park; Serpentine | TA |
| 10 | St. Paul's Cathedral | City of London | 51.5138 | -0.0984 | Wren's dome; Diana-Charles wedding | TA, GM, LP |
| 11 | Borough Market | Bankside | 51.5054 | -0.0907 | Best food market in UK | NYT36, Social |
| 12 | Camden Market + Primrose Hill | North London | 51.5413 | -0.1464 | Alt market + skyline view from the hill | NYT36, Social |
| 13 | London Eye | South Bank | 51.5033 | -0.1196 | 443-ft ferris wheel over Thames | TA, GM |
| 14 | Notting Hill + Portobello Road Market | West London | 51.5170 | -0.2057 | Pastel houses + Saturday antiques market | TA, Social |
| 15 | Shakespeare's Globe | Bankside | 51.5081 | -0.0972 | Reconstructed Elizabethan playhouse | TA, LP |

#### Tour LON-1 — "Thames Bridges Loop" (2h driving)

*Central London driving is slow and has Congestion Zone £15/day charge. Do evenings post-7pm or Sunday morning.*

Intent: `first_time_highlights`, `scenic_sunset` (evening), `minimal_walking`.

1. **Tower Bridge north side** (51.5055, -0.0754) — start.
2. **Lower Thames St → Victoria Embankment** (~2 mi).
3. Past **Tower of London, HMS Belfast visible** (~1 mi).
4. **Westminster Bridge southbound** (51.5007, -0.1218) (~1 mi).
5. **Along South Bank → Waterloo Bridge** (51.5080, -0.1156) (~1 mi).
6. Over Waterloo Bridge to north — **The Strand** (~1 mi).
7. **Trafalgar Square drive-by** (51.5080, -0.1281) (~0.3 mi).
8. **The Mall westbound** to **Buckingham Palace** (51.5014, -0.1419) (~0.8 mi).
9. **Hyde Park Corner → Park Lane** (~1 mi).
10. End via **Oxford St → Tottenham Court Rd** back toward City.

#### Tour LON-2 — "Westminster to Tower" (4h walking) [CANDIDATE GOLD]

*Classic London walk along the Thames. ~3 mi, all flat. Best-scoring London tour; promotion-candidate for gold once calibrated.*

Intent: `first_time_highlights`, `architecture_historic`, `food_heavy` (at Borough).

1. **Westminster Bridge + Big Ben view** (51.5007, -0.1246).
2. **Houses of Parliament + Westminster Abbey** (51.4993, -0.1273).
3. **Horse Guards Parade** (51.5046, -0.1280).
4. **Trafalgar Square + National Gallery** (51.5080, -0.1281) — 30-min browse.
5. **Covent Garden Piazza** (51.5117, -0.1240).
6. **Monmouth Coffee or Covent Garden Market stalls** pause.
7. **Royal Courts of Justice + Fleet Street** (51.5138, -0.1122).
8. **St. Paul's Cathedral** (51.5138, -0.0984) — exterior + optional £21 entry.
9. **Millennium Bridge** south (51.5096, -0.0982).
10. **Tate Modern** (51.5076, -0.0994) — 30 min.
11. **Borough Market** food stop (51.5054, -0.0907).
12. **Shakespeare's Globe** (51.5081, -0.0972).
13. End at **Tower Bridge** (51.5055, -0.0754).

### D. Scoring metadata

**LON-1 (Thames Bridges Loop):** `tour_absolute ≈ 82` · iconic 9.0 · geographic 8.5 · time_realism 7.5 (traffic + CZ) · narrative 7.5 · scenic 9.0 · variety 7.0 · usability 7.0. Primary intent `first_time_highlights` = 84. **Final (hybrid) = 82.8**.

**LON-2 (Westminster to Tower):** `tour_absolute ≈ 91` · iconic 9.5 · geographic 9.5 · time_realism 8.5 · narrative 9.5 · scenic 9.0 · variety 9.5 · usability 9.0. Primary intent `first_time_highlights` = 95. **Final (hybrid) = 92.6**. Candidate for gold promotion once calibration pass confirms.

---

## 27. Paris ✅ (v2)

### A. City summary

The most visited city on earth — Eiffel Tower, Louvre, Notre-Dame, and café-lined Haussmann boulevards make Paris the textbook "walkable romantic capital."

- **Strongest for:** romantic evening, walking first-time highlights, architecture, photo-heavy, food-heavy (bakery/bistro density).
- **Weak for:** driving tours (narrow streets, ZTL-like restrictions, scooter chaos); kid-heavy itineraries (distance between child-friendly stops).
- **Unique strength:** the Eiffel Tower sparkles every hour on the hour from dusk to 1am — the single most reliable nocturnal set piece in any major city.

### B. Gold-standard stop graph

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | walking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Trocadéro | viewpoint | 9 | 10 | 7 | 15 | light | golden_hour | paris_eiffel |
| Eiffel Tower base (Champ de Mars) | icon | 10 | 10 | 9 | 30 | light | any | paris_eiffel |
| Louvre Cour Napoléon (pyramid) | icon | 10 | 10 | 10 | 30 | light | any | paris_right |
| Musée d'Orsay | museum | 9 | 7 | 10 | 90 | light | any | paris_seine |
| Place Vendôme | icon | 8 | 9 | 8 | 10 | light | night | paris_right |
| Palais Royal (Colonnes de Buren) | neighborhood | 7 | 9 | 8 | 15 | light | any | paris_right |
| Pont Alexandre III | icon | 9 | 10 | 8 | 15 | light | night | paris_seine |
| Montmartre + Sacré-Cœur | icon | 9 | 9 | 9 | 60 | heavy | morning | paris_montmartre |
| Sainte-Chapelle | icon | 8 | 10 | 9 | 45 | light | midday | paris_cite |
| Notre-Dame exterior | icon | 9 | 8 | 10 | 20 | light | any | paris_cite |
| Le Marais (Place des Vosges) | neighborhood | 7 | 8 | 8 | 45 | light | any | paris_marais |
| Luxembourg Gardens | park | 8 | 9 | 7 | 45 | light | afternoon | paris_left |

**Clusters:** `paris_eiffel` · `paris_right` · `paris_seine` · `paris_montmartre` · `paris_cite` · `paris_marais` · `paris_left`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Trocadéro terrace (Eiffel at any time) |
| Best sunset stop | Sacré-Cœur steps at golden hour |
| Best short wow | Sainte-Chapelle upper chapel |
| Best scenic drive segment | Pont Neuf → Pont Alexandre III along Seine (after 8pm) |
| Best coffee/food pause | Angelina hot chocolate; Du Pain et des Idées bakery |
| Best local texture | Rue Mouffetard market morning |
| Best ending point | Trocadéro at the 10pm Eiffel sparkle |
| Best worth-the-detour | Musée d'Orsay top floor Impressionists |

### C. Benchmark tours

#### Tour PAR-1 — "Right Bank After Dark" (2.5h walking evening) [GOLD]

See full benchmark with per-stop attributes and score breakdown in [gold-standard-tours.md — Tour 7](./gold-standard-tours.md#tour-7--right-bank-after-dark). Target user: couple on a Paris date night. Intent tags: `romantic`, `scenic_sunset` (night variant), `photo_heavy`. **`tour_absolute` = 90.5 · romantic fit = 97**.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Eiffel Tower | 7th arr. | 48.8584 | 2.2945 | The symbol of France; evening sparkle on the hour | TA, GM, LP |
| 2 | Louvre Museum | 1st arr. | 48.8606 | 2.3376 | Mona Lisa + I.M. Pei pyramid | TA, GM, LP |
| 3 | Notre-Dame Cathedral (exterior) | Île de la Cité | 48.8530 | 2.3499 | Gothic masterpiece; reopening post-2019 fire | TA, LP |
| 4 | Arc de Triomphe + Champs-Élysées | 8th arr. | 48.8738 | 2.2950 | 12-avenue star intersection; rooftop view | TA, GM, LP |
| 5 | Montmartre + Sacré-Cœur | 18th arr. | 48.8867 | 2.3431 | Bohemian hilltop; basilica over Paris | TA, GM |
| 6 | Musée d'Orsay | 7th arr. | 48.8600 | 2.3266 | Best Impressionist collection on earth | TA, LP |
| 7 | Seine + Pont des Arts / Pont Neuf walk | Central | 48.8588 | 2.3417 | River promenades; bouquinistes book stalls | LP |
| 8 | Palace of Versailles (30 min SW) | Versailles | 48.8049 | 2.1204 | Louis XIV's chateau + hall of mirrors | TA, LP |
| 9 | Sainte-Chapelle | Île de la Cité | 48.8554 | 2.3450 | 15 stained-glass panels = glass cathedral | TA, Social |
| 10 | Le Marais | 3rd/4th arr. | 48.8566 | 2.3603 | Oldest preserved district; Jewish quarter + boutiques | NYT36, LP |
| 11 | Luxembourg Gardens | 6th arr. | 48.8462 | 2.3371 | Senate palace garden; classic Parisian people-watching | TA |
| 12 | Centre Pompidou | 3rd arr. | 48.8606 | 2.3522 | Inside-out Rogers+Piano museum of modern art | TA, LP |
| 13 | Latin Quarter + Shakespeare & Co | 5th arr. | 48.8527 | 2.3470 | Bookstore + Sorbonne quarter | LP |
| 14 | Pantheon | 5th arr. | 48.8462 | 2.3464 | Foucault's pendulum + French mausoleum | LP |
| 15 | Trocadéro + Palais de Chaillot | 16th arr. | 48.8616 | 2.2893 | The canonical Eiffel photo spot | Social, GM |

#### Tour PAR-2 — "Right Bank + Seine Sweep" (2h driving)

*Evening driving works despite Paris's narrow streets — traffic quiets after 9pm and the lit-river route is dense with icons.*

Intent: `romantic`, `scenic_sunset` (night), `minimal_walking`.

### 2-Hour Driving Tour — "Right Bank + Seine Sweep"
1. **Trocadéro** (48.8616, 2.2893) — start with Eiffel view.
2. **Quai Branly east along Seine** (~2 km).
3. **Place de la Concorde** (48.8656, 2.3212).
4. **Champs-Élysées west to Arc de Triomphe** (48.8738, 2.2950) (~2 km).
5. **Avenue Foch → Bois de Boulogne** edge.
6. Back via **Avenue Kléber → Trocadéro** (~3 km).
7. **Quai Branly → Pont Alexandre III** (48.8637, 2.3135).
8. **Quai des Tuileries past Louvre** (48.8606, 2.3376).
9. **Pont Neuf** (48.8570, 2.3417).
10. End at **Rue de Rivoli → Place Vendôme** (48.8676, 2.3292).

#### Tour PAR-3 — "Rive Droite Classic" (4h walking)

Intent: `first_time_highlights`, `architecture_historic`, `food_heavy` (soft).

1. **Trocadéro** (48.8616, 2.2893) — start with photo.
2. Cross **Pont d'Iéna** to **Eiffel Tower base** (48.8584, 2.2945).
3. Walk **Champ de Mars → École Militaire**.
4. **Café Constant or Les Cocottes** on Rue Saint-Dominique.
5. Along Seine east to **Musée d'Orsay** (48.8600, 2.3266) — 45 min.
6. Cross **Pont Royal** → **Jardin des Tuileries** (48.8634, 2.3275).
7. **Louvre exterior + pyramid photo** (48.8606, 2.3376).
8. **Palais Royal gardens + Colonnes de Buren** (48.8640, 2.3364).
9. **Angelina Rue de Rivoli hot chocolate** (48.8651, 2.3276).
10. **Rue Saint-Honoré → Place Vendôme** (48.8676, 2.3292).
11. **Opéra Garnier** (48.8720, 2.3316).
12. End at **Café de la Paix** outdoor table (48.8710, 2.3313).

### D. Scoring metadata

**PAR-1 (Right Bank After Dark):** `tour_absolute = 90.5` · iconic 9.5 · geographic 9.0 · time_realism 9.0 · narrative 9.5 · scenic 10 · variety 7.0 · usability 8.5. Primary intent `romantic` = 97. **Final (hybrid) = 93.1**. Full breakdown in [gold-standard-tours.md — Tour 7](./gold-standard-tours.md#tour-7--right-bank-after-dark).

**PAR-2 (Right Bank + Seine Sweep):** `tour_absolute ≈ 82` · iconic 9.0 · geographic 8.0 · time_realism 7.0 (daytime traffic) · narrative 8.5 · scenic 9.0 · variety 7.5 · usability 7.5. Primary intent `scenic_sunset` = 85. **Final (hybrid) = 83.2**.

**PAR-3 (Rive Droite Classic):** `tour_absolute ≈ 90` · iconic 9.5 · geographic 9.0 · time_realism 8.5 · narrative 9.0 · scenic 9.0 · variety 9.0 · usability 8.5. Primary intent `first_time_highlights` = 93. **Final (hybrid) = 91.2**. Strong candidate — if PAR-1 weren't already gold, this would be the Paris gold tour.

---

## 28. Rome ✅ (v2)

### A. City summary

2,500 years of layered civilization in one open-air museum — Colosseum, Vatican, Trevi Fountain, and the best espresso culture in Europe.

- **Strongest for:** iconic walking, architecture_historic, first-time highlights, food-heavy (Trastevere).
- **Weak for:** driving tours (ZTL restrictions in the historic core); sunset-focused (east-facing centro, west-facing Gianicolo is the workaround).
- **Unique strength:** the centro storico is the world's densest walkable icon cluster — 4h delivers 4+ top-tier world landmarks plus neighborhood texture.

### B. Gold-standard stop graph

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | walking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Colosseum + Arch | icon | 10 | 9 | 10 | 60 | light | morning | rome_ancient |
| Roman Forum + Palatine | icon | 10 | 8 | 10 | 75 | moderate | morning | rome_ancient |
| Trevi Fountain | icon | 10 | 9 | 8 | 20 | light | midday | rome_baroque |
| Pantheon | icon | 10 | 9 | 10 | 20 | light | midday | rome_baroque |
| Piazza Navona | icon | 9 | 8 | 9 | 15 | light | any | rome_baroque |
| Spanish Steps | icon | 8 | 7 | 7 | 15 | moderate | any | rome_baroque |
| Vatican (St. Peter's) | icon | 10 | 9 | 10 | 120 | heavy | morning | rome_vatican |
| Castel Sant'Angelo | icon | 8 | 8 | 9 | 30 | light | afternoon | rome_vatican |
| Trastevere (Piazza S. Maria) | neighborhood | 8 | 7 | 9 | 60 | light | afternoon | rome_trastevere |
| Gianicolo terrace | viewpoint | 6 | 9 | 6 | 15 | moderate | golden_hour | rome_trastevere |
| Piazza del Popolo + Pincio | viewpoint | 7 | 9 | 7 | 20 | moderate | afternoon | rome_baroque |

**Clusters:** `rome_ancient` · `rome_baroque` · `rome_vatican` · `rome_trastevere`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Gianicolo terrace at golden hour |
| Best sunset stop | Pincio Terrace over Piazza del Popolo |
| Best short wow | Pantheon oculus interior |
| Best scenic drive segment | Gianicolo → Tiber perimeter → Castel Sant'Angelo |
| Best coffee/food pause | Sant'Eustachio espresso or Giolitti gelato |
| Best local texture | Trastevere after 7pm |
| Best ending point | Piazza Santa Maria in Trastevere with an aperitivo |
| Best worth-the-detour | Campo de' Fiori morning market |

### C. Benchmark tours

#### Tour ROM-1 — "Centro Storico Classics" (4h walking) [GOLD]

See full benchmark with per-stop attributes and score breakdown in [gold-standard-tours.md — Tour 2](./gold-standard-tours.md#tour-2--centro-storico-classics). Target user: first-time Rome visitor on foot. Intent tags: `first_time_highlights`, `architecture_historic`, `photo_heavy`. **`tour_absolute` = 93.0 · first_time fit = 97**.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Colosseum | Monti | 41.8902 | 12.4922 | 80 AD amphitheater; #1 Italian landmark | TA, GM, LP |
| 2 | Roman Forum + Palatine Hill | Monti | 41.8925 | 12.4853 | Ancient civic heart of Rome | TA, LP |
| 3 | Vatican — St. Peter's + Sistine Chapel | Vatican City | 41.9022 | 12.4533 | Largest church + Michelangelo's ceiling | TA, GM, LP |
| 4 | Trevi Fountain | Trevi | 41.9009 | 12.4833 | Baroque fountain; coin toss = return to Rome | TA, GM, Social |
| 5 | Pantheon | Pigna | 41.8986 | 12.4769 | 2000-year-old dome; best-preserved Roman building | TA, GM, LP |
| 6 | Piazza Navona | Parione | 41.8992 | 12.4731 | Bernini's Fountain of the Four Rivers | TA, LP |
| 7 | Spanish Steps + Piazza di Spagna | Campo Marzio | 41.9058 | 12.4823 | 135-step climb; Trinità dei Monti top | TA, GM |
| 8 | Castel Sant'Angelo | Parione | 41.9031 | 12.4663 | Hadrian's mausoleum + riverside bridge | TA, LP |
| 9 | Trastevere | Trastevere | 41.8890 | 12.4666 | Cobblestone neighborhood; best dinner Rome | LP, NYT36, Social |
| 10 | Piazza del Popolo + Pincio Terrace | Flaminio | 41.9108 | 12.4768 | Twin churches + sunset terrace over city | TA |
| 11 | Villa Borghese Gardens + Galleria | Pinciano | 41.9137 | 12.4921 | Park + Bernini sculptures museum | TA, LP |
| 12 | Campo de' Fiori market | Parione | 41.8957 | 12.4722 | Daily market; Bruno statue | NYT36 |
| 13 | Altar of the Fatherland / Piazza Venezia | Central | 41.8955 | 12.4823 | The "wedding cake" monument + rooftop view | TA |
| 14 | Bocca della Verità / Mouth of Truth | Ripa | 41.8881 | 12.4816 | Roman Holiday hand-in-mouth photo | TA, Social |
| 15 | Ostia Antica (20 mi SW) | Ostia | 41.7551 | 12.2921 | Roman port ruins, Pompeii-lite | LP |

#### Tour ROM-2 — "Ancient Loop + Gianicolo View" (2h driving)

*Central Rome is largely ZTL (residents only). This route sticks to driveable perimeter roads. The gold walking tour (ROM-1) covers the core — this is the complement for visitors staying outside the historic center.*

Intent: `first_time_highlights`, `scenic_sunset`, `minimal_walking`.

### 2-Hour Driving Tour — "Ancient Loop + Gianicolo View"
*Central Rome is largely restricted ZTL (residents only). This route sticks to driveable perimeter roads.*

1. **Piazzale Garibaldi / Gianicolo** (41.8914, 12.4625) — start with panorama.
2. **Via Garibaldi down → Trastevere perimeter** (~1.5 km).
3. **Lungotevere Trastevere north** past Tiber Island (~2 km).
4. **Lungotevere in Sassia → Castel Sant'Angelo** (41.9031, 12.4663) (~2 km).
5. **Via della Conciliazione → St. Peter's exterior** (41.9022, 12.4533).
6. **Viale Vaticano north → Via Flaminia** (~4 km).
7. **Piazza del Popolo** (41.9108, 12.4768).
8. **Via Veneto south** past US Embassy (~2 km).
9. Via Nazionale → **Piazza Venezia** (41.8955, 12.4823).
10. End with **Via dei Fori Imperiali past Colosseum** (41.8902, 12.4922).

### 4-Hour Walking Tour — "Centro Storico Classics" (ROM-1 route)

*(This is the ROM-1 gold tour — full structured per-stop attributes and scoring in [gold-standard-tours.md — Tour 2](./gold-standard-tours.md#tour-2--centro-storico-classics). Summary below.)*

1. **Colosseum + Arch of Constantine** (41.8902, 12.4922).
2. **Roman Forum + Palatine Hill** (41.8925, 12.4853) — optional 60-min browse.
3. **Via dei Fori Imperiali north to Piazza Venezia** (41.8955, 12.4823).
4. **Altar of the Fatherland terrace** (41.8955, 12.4823).
5. **Via del Corso → Trevi Fountain** (41.9009, 12.4833).
6. **Giolitti gelato** or **Sant'Eustachio coffee** (41.8977, 12.4752).
7. **Pantheon** (41.8986, 12.4769).
8. **Piazza Navona** (41.8992, 12.4731) — Bernini fountain.
9. **Campo de' Fiori market** (41.8957, 12.4722).
10. **Ditirambo or Emma Pizzeria** lunch pause.
11. Cross Ponte Sisto to **Trastevere** (41.8890, 12.4666).
12. End at **Piazza Santa Maria in Trastevere** with spritz (41.8894, 12.4695).

### D. Scoring metadata

**ROM-1 (Centro Storico Classics):** `tour_absolute = 93.0` · iconic 10 · geographic 9.5 · time_realism 8.5 · narrative 9.5 · scenic 9.0 · variety 9.0 · usability 8.5. Primary intent `first_time_highlights` = 97. **Final (hybrid) = 94.6**. Full breakdown in [gold-standard-tours.md — Tour 2](./gold-standard-tours.md#tour-2--centro-storico-classics).

**ROM-2 (Ancient Loop + Gianicolo):** `tour_absolute ≈ 81` · iconic 8.5 · geographic 8.5 · time_realism 8.0 · narrative 8.0 · scenic 8.5 · variety 7.5 · usability 7.5. Primary intent `scenic_sunset` = 85 (Gianicolo finale). **Final (hybrid) = 82.6**.

---

## 29. Barcelona ✅ (v2)

### A. City summary

Gaudí's modernist fever dream by the Mediterranean — Sagrada Família, Park Güell, tapas on Gothic alley terraces, and Barceloneta beach 10 minutes from the cathedral.

- **Strongest for:** architecture (Modernisme), walking first-time highlights, food-heavy (Boqueria + El Born tapas), local flavor.
- **Weak for:** minimal-walking driving tours (narrow Gothic Quarter streets + parking scarcity); kid-heavy (high-crowd stress at Sagrada Família, Park Güell).
- **Unique strength:** Gaudí's Modernisme stops (Sagrada, Casa Batlló, Casa Milà, Park Güell) form a unique architectural arc found nowhere else — architecture_modern tours score near-max here.

### B. Gold-standard stop graph

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | walking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Sagrada Família | icon | 10 | 10 | 10 | 90 | light | morning | bcn_eixample |
| Casa Batlló | icon | 9 | 9 | 10 | 60 | light | any | bcn_eixample |
| Casa Milà (La Pedrera) | icon | 9 | 9 | 10 | 60 | light | afternoon | bcn_eixample |
| Park Güell | icon | 9 | 10 | 9 | 90 | heavy | morning | bcn_gracia |
| La Rambla + Boqueria | neighborhood | 9 | 7 | 8 | 60 | light | morning | bcn_rambla |
| Gothic Quarter + Cathedral | neighborhood | 9 | 8 | 10 | 60 | light | any | bcn_gothic |
| Barcelona Cathedral | icon | 8 | 9 | 10 | 30 | light | any | bcn_gothic |
| El Born + Santa Maria del Mar | neighborhood | 7 | 8 | 9 | 60 | light | afternoon | bcn_born |
| Picasso Museum | museum | 8 | 7 | 9 | 90 | light | any | bcn_born |
| Barceloneta Beach | waterfront | 7 | 8 | 6 | 45 | light | afternoon | bcn_beach |
| Bunkers del Carmel | viewpoint | 6 | 10 | 7 | 30 | heavy | golden_hour | bcn_carmel |
| Montjuïc (Castle + Magic Fountain) | viewpoint | 7 | 9 | 7 | 60 | moderate | night | bcn_montjuic |

**Clusters:** `bcn_eixample` · `bcn_gracia` · `bcn_rambla` · `bcn_gothic` · `bcn_born` · `bcn_beach` · `bcn_carmel` · `bcn_montjuic`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Bunkers del Carmel at golden hour |
| Best sunset stop | Bunkers del Carmel (free, 360°) |
| Best short wow | Pont del Bisbe in Gothic Quarter |
| Best scenic drive segment | Passeig de Gràcia Modernisme corridor |
| Best coffee/food pause | La Boqueria fresh juice + jamón |
| Best local texture | El Born at aperitivo hour |
| Best ending point | Santa Maria del Mar nave + tapas row |
| Best worth-the-detour | Sagrada Família interior with timed entry |

### C. Benchmark tours

Both tours below are candidate gold — **BCN-2 (Gothic + El Born + Boqueria) is the candidate Barcelona gold tour**, pending calibration.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Sagrada Família | Eixample | 41.4036 | 2.1744 | Gaudí's unfinished basilica; most visited site in Spain | TA, GM, LP |
| 2 | Park Güell | Gràcia | 41.4145 | 2.1527 | Mosaic terrace + lizard fountain | TA, GM, Social |
| 3 | Casa Batlló | Eixample | 41.3917 | 2.1649 | Gaudí "bone-and-skull" facade | TA, LP |
| 4 | La Rambla | Ciutat Vella | 41.3809 | 2.1729 | 1.2-km pedestrian spine | TA, GM |
| 5 | Gothic Quarter (Barri Gòtic) | Ciutat Vella | 41.3833 | 2.1767 | Medieval maze + Barcelona Cathedral | TA, LP |
| 6 | La Boqueria Market | La Rambla | 41.3817 | 2.1720 | 1840 covered market; Instagram/food hub | TA, Social |
| 7 | Casa Milà (La Pedrera) | Eixample | 41.3954 | 2.1619 | Gaudí rooftop with ventilator warriors | TA, LP |
| 8 | Barceloneta Beach | Barceloneta | 41.3784 | 2.1925 | Urban beach + chiringuitos | TA |
| 9 | Montjuïc Hill + Magic Fountain | Montjuïc | 41.3711 | 2.1516 | Olympic hill + evening fountain show | TA, LP |
| 10 | Picasso Museum | El Born | 41.3853 | 2.1808 | 4,000 works in medieval palaces | TA, LP |
| 11 | Santa Maria del Mar | El Born | 41.3841 | 2.1819 | Catalan Gothic masterpiece | LP |
| 12 | Camp Nou / FC Barcelona | Les Corts | 41.3809 | 2.1228 | Largest football stadium in Europe | TA |
| 13 | El Born district | El Born | 41.3856 | 2.1820 | Narrow lanes + vermut bars | NYT36 |
| 14 | Bunkers del Carmel viewpoint | Carmel | 41.4182 | 2.1588 | Free panorama of all Barcelona | Social, Reddit |
| 15 | Palau de la Música Catalana | Ciutat Vella | 41.3875 | 2.1753 | Modernista stained-glass concert hall | LP |

#### Tour BCN-1 — "Montjuïc + Tibidabo Lite" (2h driving)

Intent: `scenic_sunset`, `first_time_highlights`, `minimal_walking`.

### 2-Hour Driving Tour — "Montjuïc + Tibidabo Lite"
1. **Plaça d'Espanya** (41.3756, 2.1491) — start.
2. **Av Reina Maria Cristina → Montjuïc road** (41.3711, 2.1516) — hairpins up (~3 km).
3. **Montjuïc Castle parking** (41.3631, 2.1660) — panorama of port.
4. Down **Passeig de Montjuïc** east side (~3 km).
5. **Port Vell marina** (41.3766, 2.1820).
6. **Passeig de Colom → Via Laietana** north (~2 km).
7. **Passeig de Gràcia south → north** past Casa Batlló (41.3917, 2.1649) and Casa Milà (41.3954, 2.1619) (~1 km).
8. **Av Diagonal to Av Tibidabo** (41.4245, 2.1351) (~6 km).
9. End at **Bunkers del Carmel** (41.4182, 2.1588) (~4 km).

#### Tour BCN-2 — "Gothic + El Born + Boqueria" (4h walking) [CANDIDATE GOLD]

Intent: `first_time_highlights`, `architecture_historic`, `food_heavy`.

1. **Plaça de Catalunya** (41.3870, 2.1701) — start.
2. **La Rambla south** (41.3809, 2.1729).
3. **La Boqueria market** (41.3817, 2.1720) — fresh juice + jamón.
4. **Gran Teatre del Liceu exterior** (41.3803, 2.1735).
5. **Plaça Reial** (41.3797, 2.1751).
6. East into **Gothic Quarter — Plaça Sant Jaume** (41.3829, 2.1769).
7. **Barcelona Cathedral** (41.3839, 2.1769).
8. **Pont del Bisbe** (41.3831, 2.1764) — Instagram bridge.
9. **La Vinateria del Call or Bodega La Puntual** pause.
10. East to **Plaça del Rei → Via Laietana** (41.3838, 2.1780).
11. **Santa Maria del Mar** (41.3841, 2.1819).
12. **Picasso Museum exterior or visit** (41.3853, 2.1808).
13. End at **El Born cultural center + tapas row** (41.3856, 2.1820).

### D. Scoring metadata

**BCN-1 (Montjuïc + Tibidabo Lite):** `tour_absolute ≈ 80` · iconic 7.5 · geographic 8.0 · time_realism 7.5 · narrative 8.0 · scenic 9.0 · variety 7.0 · usability 7.5. Primary intent `scenic_sunset` = 86. **Final (hybrid) = 82.4**.

**BCN-2 (Gothic + El Born + Boqueria):** `tour_absolute ≈ 90` · iconic 9.0 · geographic 9.5 · time_realism 9.0 · narrative 9.0 · scenic 8.5 · variety 9.0 · usability 8.5. Primary intent `first_time_highlights` = 94. **Final (hybrid) = 91.6**. Candidate for gold.

---

## 30. Amsterdam 🔹

**Summary:** Golden Age canals in UNESCO-listed concentric rings, bicycles outnumbering residents, gabled merchant houses, and a serious museum quarter — the archetypal "just walk / just bike" city. **Strong for:** walking, architecture, museums, romantic (canal-side evening). **Weak for:** driving (nearly impossible), family (bike-chaos safety).
**Signature moments:** short wow — Rijksmuseum Night Watch gallery · food pause — De Drie Graefjes apple pie or bitterballen at Café Hoppe · local texture — Jordaan canals + Sunday Noordermarkt · ending — Magere Brug (Skinny Bridge) at golden hour.
**Clusters:** `ams_center` · `ams_jordaan` · `ams_museumplein` · `ams_deplan` · `ams_eastdocks`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Canal Ring (Grachtengordel) | Central | 52.3738 | 4.8910 | UNESCO 17th-c canal system | TA, LP |
| 2 | Anne Frank House | Jordaan | 52.3752 | 4.8840 | Hidden annex + secret diary museum | TA, GM, LP |
| 3 | Rijksmuseum | Museumplein | 52.3600 | 4.8852 | Rembrandt Night Watch + Vermeer | TA, GM, LP |
| 4 | Van Gogh Museum | Museumplein | 52.3584 | 4.8811 | 200+ Van Goghs | TA, LP |
| 5 | Dam Square + Royal Palace | Central | 52.3731 | 4.8922 | National square; war memorial | TA |
| 6 | Jordaan district | Jordaan | 52.3737 | 4.8832 | Former working-class neighborhood; brown cafés | NYT36, LP |
| 7 | Vondelpark | Oud-Zuid | 52.3579 | 4.8686 | 45-hectare city park | TA |
| 8 | Bloemenmarkt | Central | 52.3671 | 4.8916 | Floating flower market | TA |
| 9 | Red Light District | De Wallen | 52.3743 | 4.8988 | Oldest part of Amsterdam + canals | TA |
| 10 | Begijnhof courtyard | Central | 52.3697 | 4.8900 | Hidden beguinage courtyard | LP |
| 11 | NEMO Science Museum rooftop | Oosterdok | 52.3737 | 4.9126 | Free rooftop skyline + water | Social |
| 12 | A'DAM Lookout + swing | Amsterdam Noord | 52.3842 | 4.9029 | Rooftop swing over IJ | TA, Social |
| 13 | Keukenhof Gardens (seasonal, 35 mi SW) | Lisse | 52.2706 | 4.5466 | 7M tulips, mid-March through mid-May | TA, Social |
| 14 | Albert Cuyp Market | De Pijp | 52.3557 | 4.8953 | Largest outdoor market in Netherlands | NYT36 |
| 15 | Rembrandt House Museum | Central | 52.3695 | 4.9011 | Rembrandt's former home + studio | LP |

### 2-Hour Driving Tour — "Outer Ring + North via Ferry"
*Amsterdam center is dense and has camera-enforced restrictions. Park at a P+R and bike/tram instead. If driving, stick to ring road.*

1. **Westerpark** (52.3872, 4.8817) — start.
2. **Haarlemmerweg south → Nassaukade** outer canal (~3 km).
3. **Leidseplein outside Melkweg** (52.3645, 4.8817).
4. **Van Baerlestraat → Museumplein exterior** (52.3584, 4.8811).
5. **Stadhouderskade east** past Heineken Exp. (~3 km).
6. **Plantage area → Maritime Museum** (52.3708, 4.9114).
7. **IJtunnel north → Amsterdam Noord** (~3 km).
8. **A'DAM Tower / NDSM Wharf** (52.3994, 4.8953) optional.
9. Return via IJtunnel to end near **Dam Square** (52.3731, 4.8922).

### 4-Hour Walking Tour — "Canal Ring + Jordaan + Museumplein"
1. **Amsterdam Centraal Station** (52.3791, 4.9003) — start.
2. **Damrak south** to **Dam Square** (52.3731, 4.8922).
3. **Royal Palace + Nieuwe Kerk** (52.3731, 4.8914).
4. **Spui + Begijnhof courtyard** (52.3697, 4.8900).
5. **Bloemenmarkt** (52.3671, 4.8916).
6. **Rembrandtplein** (52.3661, 4.8961).
7. ☕ **Café Luxembourg** or **Van Stapele Koekmakerij** cookie.
8. Canal walk up **Herengracht or Keizersgracht** (52.3738, 4.8910).
9. **Anne Frank House** (52.3752, 4.8840) — book ahead.
10. **Jordaan lanes** — Westerstraat, Bloemstraat (52.3737, 4.8832).
11. 🧀 **Foodhallen (De Hallen food hall)** detour (52.3656, 4.8714).
12. **Vondelpark** entrance (52.3579, 4.8686).
13. End at **Rijksmuseum passageway** (52.3600, 4.8852) — exterior cycle-through photo.

---

## 31. Lisbon 🔹

**Summary:** Seven hills over the Tagus — pastel azulejo tiles, yellow tram 28, fado in the Alfama, and the best Atlantic-cliff sunsets in Europe at under half the price of Paris. **Strong for:** scenic sunset, romantic, walking (hilly), local flavor, food. **Weak for:** minimal-walking (hills); family with strollers.
**Signature moments:** sunset stop — Miradouro da Senhora do Monte · short wow — Tram 28 uphill ride · food pause — Pastéis de Belém · local texture — Alfama fado house evening · ending — Praça do Comércio at night.
**Clusters:** `lis_baixa` · `lis_alfama` · `lis_chiado` · `lis_belem` · `lis_principereal` · `lis_lxfactory`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Belém Tower + Jerónimos Monastery | Belém | 38.6916 | -9.2165 | UNESCO Manueline complex + age of discovery | TA, GM, LP |
| 2 | Pastéis de Belém | Belém | 38.6975 | -9.2035 | Original custard-tart bakery since 1837 | TA, Social |
| 3 | São Jorge Castle | Alfama | 38.7139 | -9.1334 | Moorish castle + best skyline over city | TA, LP |
| 4 | Alfama district + Miradouro de Santa Luzia | Alfama | 38.7120 | -9.1307 | Oldest district; tile-lined terrace | TA, LP, Social |
| 5 | Tram 28 | Central | 38.7134 | -9.1409 | Historic tram climbing the hills | TA |
| 6 | LX Factory | Alcântara | 38.7027 | -9.1780 | Industrial complex turned artsy food hall | NYT36, Social |
| 7 | Time Out Market | Cais do Sodré | 38.7068 | -9.1459 | Best of Lisbon's chefs under one roof | NYT36, Social |
| 8 | Praça do Comércio | Baixa | 38.7074 | -9.1366 | Grand riverfront square with arch | TA |
| 9 | Miradouro da Senhora do Monte | Graça | 38.7183 | -9.1328 | Highest free viewpoint | LP, Social |
| 10 | Elevador de Santa Justa | Baixa | 38.7123 | -9.1394 | 1902 wrought-iron elevator | TA, Social |
| 11 | Chiado + Livraria Bertrand | Chiado | 38.7104 | -9.1418 | Oldest bookshop in the world (1732) | LP |
| 12 | National Tile Museum | Beato | 38.7247 | -9.1135 | Portugal's azulejo story | LP |
| 13 | Sintra (15 mi NW) | Sintra | 38.7946 | -9.3907 | Pena Palace fairy-tale + Moorish castle | TA, LP |
| 14 | Cascais (20 mi W) | Cascais | 38.6969 | -9.4215 | Seaside fishing town on train line | TA |
| 15 | Bairro Alto nightlife | Bairro Alto | 38.7132 | -9.1450 | Fado bars + late-night crawl | LP |

### 2-Hour Driving Tour — "Seven Hills + Belém"
1. **Miradouro da Senhora do Monte** (38.7183, -9.1328) — start high.
2. Down **Calçada do Monte** to **Alfama edge** (~1.5 km).
3. **Av. Infante Dom Henrique → 25 de Abril Bridge view** (~3 km).
4. West along **Av. Brasília** past Cristo Rei view (~3 km).
5. **MAAT museum pull-off** (38.6961, -9.1941).
6. **Belém monumental axis** — Padrão dos Descobrimentos (38.6935, -9.2056).
7. **Belém Tower** (38.6916, -9.2165).
8. **Jerónimos Monastery** (38.6979, -9.2060).
9. Return via **Av. 24 de Julho → Cais do Sodré** (~6 km).
10. End at **Praça do Comércio** (38.7074, -9.1366).

### 4-Hour Walking Tour — "Baixa + Alfama + Chiado"
1. **Praça do Comércio** (38.7074, -9.1366) — start.
2. **Rua Augusta Arch + pedestrian street** (38.7099, -9.1373).
3. **Rossio Square** (38.7138, -9.1393).
4. **Elevador de Santa Justa** (38.7123, -9.1394) — ride up.
5. **Largo do Carmo + Carmo Convent ruins** (38.7122, -9.1407).
6. ☕ **A Brasileira café** Chiado (38.7104, -9.1418).
7. **Rua Garrett shopping + Bertrand bookshop** (38.7104, -9.1413).
8. **Miradouro de São Pedro de Alcântara** (38.7154, -9.1440).
9. Walk or Tram 28 to **Alfama**.
10. **Miradouro de Santa Luzia** (38.7120, -9.1307).
11. **São Jorge Castle** (38.7139, -9.1334).
12. 🐟 **Time Out Market** finish (38.7068, -9.1459).

---

## 32. Berlin 🔹

**Summary:** Europe's most emotionally raw capital — Brandenburg Gate, the surviving Wall, cold-war checkpoints, and Museum Island on the Spree, wrapped in the continent's most creative club scene. **Strong for:** walking, architecture (both historic and modern), museums, story-heavy history tours. **Weak for:** scenic sunset (flat city); romantic-fairy-tale tours.
**Signature moments:** short wow — East Side Gallery Wall murals · food pause — Curry 36 currywurst · local texture — Kreuzberg + Turkish market (Tuesdays & Fridays) · ending — Reichstag dome evening entry.
**Clusters:** `ber_mitte` · `ber_museum-island` · `ber_kreuzberg` · `ber_prenzlauerberg` · `ber_eastside`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Brandenburg Gate | Mitte | 52.5163 | 13.3777 | Symbol of reunification | TA, GM, LP |
| 2 | Reichstag Building | Mitte | 52.5186 | 13.3762 | Norman Foster glass dome; book ahead | TA, LP |
| 3 | Memorial to the Murdered Jews of Europe | Mitte | 52.5139 | 13.3784 | Peter Eisenman's 2,711 concrete slabs | TA, LP |
| 4 | East Side Gallery | Friedrichshain | 52.5055 | 13.4398 | 1.3 km Berlin Wall segment with murals | TA, Social |
| 5 | Museum Island (Pergamon, Neues) | Mitte | 52.5208 | 13.3973 | 5 museums on UNESCO island | TA, LP |
| 6 | Berlin Wall Memorial (Bernauer Str) | Mitte | 52.5353 | 13.3901 | Best-preserved Wall section + watchtower | LP |
| 7 | Checkpoint Charlie | Mitte | 52.5076 | 13.3904 | Famous Cold War crossing; touristy | TA |
| 8 | Tiergarten + Victory Column | Tiergarten | 52.5145 | 13.3501 | 520-acre park + golden Viktoria | TA |
| 9 | Berliner Dom | Mitte | 52.5192 | 13.4010 | Baroque cathedral dome | TA |
| 10 | TV Tower (Fernsehturm) | Mitte | 52.5208 | 13.4094 | 368-m tower + revolving restaurant | TA |
| 11 | Kreuzberg + Görlitzer Park | Kreuzberg | 52.4979 | 13.4358 | Turkish-German grit + döner capital | LP, Reddit |
| 12 | Prenzlauer Berg + Kollwitzplatz | Pankow | 52.5385 | 13.4175 | Gentrified Altbau blocks + cafés | NYT36 |
| 13 | Topography of Terror | Kreuzberg | 52.5065 | 13.3808 | Former Gestapo HQ site; free outdoor exhibit | LP |
| 14 | Holocaust Memorial + Berlin Wall Documentation | Various | 52.5353 | 13.3901 | Essential history arc | LP |
| 15 | Hackescher Markt / Hackesche Höfe | Mitte | 52.5243 | 13.4024 | Art nouveau courtyard maze | LP |

### 2-Hour Driving Tour — "Unter den Linden + East Side"
1. **Siegessäule (Victory Column)** (52.5145, 13.3501) — start at the roundabout.
2. **Straße des 17. Juni east** through Tiergarten (~2 km).
3. **Brandenburg Gate** (52.5163, 13.3777).
4. **Unter den Linden** east (~2 km).
5. **Museum Island / Berliner Dom** (52.5192, 13.4010).
6. **Karl-Liebknecht-Straße → TV Tower** (52.5208, 13.4094).
7. **Stralauer Straße → East Side Gallery** (52.5055, 13.4398) (~4 km).
8. **Oberbaum Bridge** (52.5019, 13.4454).
9. West via **Skalitzer → Kreuzberg**.
10. End at **Potsdamer Platz** (52.5096, 13.3756).

### 4-Hour Walking Tour — "Mitte to Kreuzberg"
1. **Reichstag exterior** (52.5186, 13.3762).
2. **Brandenburg Gate** (52.5163, 13.3777).
3. **Holocaust Memorial walk-through** (52.5139, 13.3784).
4. **Potsdamer Platz** (52.5096, 13.3756).
5. **Topography of Terror** (52.5065, 13.3808).
6. **Checkpoint Charlie** (52.5076, 13.3904).
7. ☕ **Café Einstein or Barcomi's** pause.
8. **Gendarmenmarkt** (52.5137, 13.3927).
9. **Museum Island walk + Berliner Dom** (52.5208, 13.3973).
10. **Hackesche Höfe courtyards** (52.5243, 13.4024).
11. 🌭 **Curry 36 or Mustafa's Gemüse Kebap** rideshare to Kreuzberg.
12. End at **East Side Gallery** (52.5055, 13.4398) sunset walk.

---

## 33. Prague 🔹

**Summary:** Bohemia's medieval capital with the greatest concentration of preserved Gothic and Baroque architecture in Europe — Charles Bridge, Astronomical Clock, and pilsner at the source. **Strong for:** walking, architecture_historic, first-time highlights, romantic, photo-heavy. **Weak for:** driving (old town pedestrianized); modern-architecture interest.
**Signature moments:** short wow — Charles Bridge at dawn (tourist-free) · food pause — U Medvidku brewery tank pilsner · local texture — Letná Park beer garden · sunset — Prague Castle from Strahov monastery · ending — Old Town Square at the astronomical clock top-of-hour.
**Clusters:** `prg_oldtown` · `prg_castle` · `prg_malastrana` · `prg_josefov` · `prg_vinohrady` · `prg_letna`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Charles Bridge | Old Town/Malá Strana | 50.0865 | 14.4114 | 1357 stone bridge with baroque statues | TA, GM, LP |
| 2 | Prague Castle + St. Vitus Cathedral | Hradčany | 50.0909 | 14.4005 | Largest ancient castle in the world | TA, GM, LP |
| 3 | Old Town Square + Astronomical Clock | Old Town | 50.0870 | 14.4208 | 1410 clock; hourly 12-apostle show | TA, GM, LP |
| 4 | Old Town | Staré Město | 50.0875 | 14.4213 | Medieval lanes; most walked square m² | TA, LP |
| 5 | Jewish Quarter (Josefov) + synagogues | Josefov | 50.0903 | 14.4187 | Oldest surviving Jewish cemetery in Europe | TA, LP |
| 6 | Lennon Wall | Malá Strana | 50.0860 | 14.4067 | Graffiti wall homage; evolving | TA, Social |
| 7 | Wenceslas Square | New Town | 50.0814 | 14.4283 | Historic protest square; National Museum | TA |
| 8 | Strahov Monastery + library | Strahov | 50.0854 | 14.3896 | Baroque library halls | LP, Social |
| 9 | Petřín Hill + tower | Petřín | 50.0835 | 14.3968 | Mini-Eiffel tower + panorama | LP |
| 10 | Dancing House | New Town | 50.0755 | 14.4142 | Gehry's "Fred & Ginger" building | TA |
| 11 | Vyšehrad + cemetery | Vyšehrad | 50.0648 | 14.4188 | Rock fortress, Dvořák grave, alt view | LP |
| 12 | Žižkov TV Tower (crawling babies) | Žižkov | 50.0832 | 14.4427 | Brutalist tower with David Černý sculptures | Social |
| 13 | Municipal House (Obecní dům) | Old Town | 50.0889 | 14.4285 | Art Nouveau concert hall | LP |
| 14 | Powder Tower | Old Town | 50.0879 | 14.4280 | Medieval gate into Old Town | TA |
| 15 | Kampa Island + John Lennon Pub | Malá Strana | 50.0840 | 14.4084 | Vltava island with Kafka museum neighbor | LP |

### 2-Hour Driving Tour — "Bohemian Heights Loop"
*Central Prague is pedestrian + ZTL — mostly a perimeter drive with parking at hotel + walking.*

1. **Letná Park hill** (50.0946, 14.4187) — start with the panorama.
2. **Prague Castle drive-by via Jelení** (50.0909, 14.4005).
3. **Strahov Monastery** (50.0854, 14.3896).
4. Down through **Malá Strana outskirts**.
5. Over **Mánesův most** to Josefov (~1.5 km).
6. **Embankment drive past Dancing House** (50.0755, 14.4142) (~2 km).
7. **Vyšehrad fortress** (50.0648, 14.4188) — parking + quick walk.
8. North on highway around city.
9. End at **Žižkov TV Tower** (50.0832, 14.4427) or hotel.

### 4-Hour Walking Tour — "Castle + Bridge + Old Town"
1. **Prague Castle main gate** (50.0909, 14.4005) — start.
2. **St. Vitus Cathedral** interior (50.0906, 14.4001).
3. **Golden Lane** (50.0916, 14.4020).
4. **Castle Gardens descent to Malá Strana** (~500 m).
5. **St. Nicholas Church Malá Strana** (50.0880, 14.4036).
6. **Lennon Wall** (50.0860, 14.4067).
7. 🍺 **U Glaubiců or Café Savoy** pause.
8. **Charles Bridge walk east** (50.0865, 14.4114).
9. **Klementinum / Bridge Tower** (50.0862, 14.4150).
10. **Old Town Square + Astronomical Clock** (50.0870, 14.4208).
11. **Týn Church** (50.0879, 14.4226).
12. **Josefov — Old New Synagogue + cemetery** (50.0903, 14.4187).
13. End at **Municipal House** (50.0889, 14.4285).

---

## 34. Dublin 🔹

**Summary:** Georgian doors, literary pubs, Guinness at St. James's Gate, and the Book of Kells at Trinity — small-scale walkable Ireland with outsized pub-culture pull. **Strong for:** walking, pub/food-heavy, local flavor, literary-themed. **Weak for:** scenic drives; architecture_modern.
**Signature moments:** short wow — Book of Kells Long Room · food pause — The Brazen Head (oldest pub) · local texture — Temple Bar evening trad session · ending — Ha'penny Bridge at dusk.
**Clusters:** `dub_templebar` · `dub_trinity` · `dub_georgian` · `dub_smithfield`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Trinity College + Book of Kells | Central | 53.3438 | -6.2546 | 9th-c illuminated Gospels + Long Room library | TA, GM, LP |
| 2 | Guinness Storehouse | Liberties | 53.3419 | -6.2867 | 7-floor tour + Gravity Bar pint with skyline | TA, GM, Viator |
| 3 | Temple Bar | Temple Bar | 53.3456 | -6.2635 | Cobblestone pub district | TA, GM |
| 4 | St. Patrick's Cathedral | Liberties | 53.3393 | -6.2712 | Ireland's largest cathedral | TA, LP |
| 5 | Dublin Castle | Central | 53.3428 | -6.2671 | Former seat of British rule | TA, LP |
| 6 | EPIC The Irish Emigration Museum | Docklands | 53.3477 | -6.2481 | Best interactive museum Dublin | TA |
| 7 | Kilmainham Gaol | Kilmainham | 53.3420 | -6.3095 | 1916 Easter Rising prison | TA, LP |
| 8 | Grafton Street | Central | 53.3414 | -6.2598 | Pedestrianized shopping spine | TA |
| 9 | St. Stephen's Green | Central | 53.3385 | -6.2591 | Victorian garden square | TA |
| 10 | Christ Church Cathedral | Central | 53.3435 | -6.2713 | Medieval cathedral + crypt | LP |
| 11 | Phoenix Park | NW | 53.3559 | -6.3298 | 1,750 acres; largest enclosed city park in Europe | TA |
| 12 | Ha'penny Bridge | Central | 53.3465 | -6.2632 | 1816 iron pedestrian bridge | TA, Social |
| 13 | Howth Cliff Walk (9 mi N) | Howth | 53.3817 | -6.0705 | Seaside cliff walk | LP |
| 14 | National Museum of Archaeology | Central | 53.3408 | -6.2544 | Celtic gold + bog bodies | LP |
| 15 | Glasnevin Cemetery | North | 53.3700 | -6.2727 | Irish historical leaders; round tower | LP |

### 2-Hour Driving Tour — "Liffey + Phoenix Park"
1. **Trinity College** (53.3438, -6.2546) — start.
2. **College Green → Dame St** (~1 km).
3. **Christ Church Cathedral** (53.3435, -6.2713).
4. **Kilmainham Gaol** (53.3420, -6.3095) (~3 km).
5. **Phoenix Park — Wellington Monument** (53.3559, -6.3298) (~3 km).
6. **Papal Cross + Áras an Uachtaráin exterior** (~2 km).
7. **North Quays along Liffey eastbound** (~5 km).
8. **Samuel Beckett Bridge + Docklands** (53.3477, -6.2438).
9. End at **EPIC Museum** (53.3477, -6.2481).

### 4-Hour Walking Tour — "Trinity + Temple Bar + Guinness"
1. **Trinity College + Book of Kells** (53.3438, -6.2546) — book ahead.
2. **Grafton Street** walk (53.3414, -6.2598).
3. **St. Stephen's Green** (53.3385, -6.2591).
4. **Little Museum of Dublin** optional (53.3383, -6.2586).
5. **Molly Malone statue** (53.3432, -6.2596).
6. ☕ **Bewley's Grafton Street** pause.
7. **Dame Street → Dublin Castle** (53.3428, -6.2671).
8. **Christ Church Cathedral** (53.3435, -6.2713).
9. **Temple Bar cobblestone crawl** (53.3456, -6.2635).
10. 🍺 **The Temple Bar Pub or The Brazen Head** (Ireland's oldest pub).
11. **Ha'penny Bridge** (53.3465, -6.2632).
12. Rideshare to **Guinness Storehouse** (53.3419, -6.2867) — end at Gravity Bar pint at sunset.

---

## 35. Edinburgh 🔹

**Summary:** Two cities in one — the medieval Old Town with a castle on a volcanic rock spine, and the Georgian New Town grid — separated by a garden valley where the ghost stories never stop. **Strong for:** walking, architecture_historic, romantic, literary tours, photo-heavy. **Weak for:** warm-weather-only driving; scale for multi-day itineraries.
**Signature moments:** short wow — Edinburgh Castle esplanade · food pause — The Witchery or Oink hog roast · local texture — Grassmarket pubs · ending — Arthur's Seat summit at golden hour · worth the detour — Dean Village (10 min walk from Princes St).
**Clusters:** `edi_oldtown` · `edi_newtown` · `edi_castle` · `edi_arthurseat` · `edi_dean`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Edinburgh Castle | Old Town | 55.9486 | -3.1999 | Volcanic-rock fortress; 1% of UK visits | TA, GM, LP |
| 2 | Royal Mile | Old Town | 55.9497 | -3.1910 | Castle-to-Palace medieval spine | TA, GM, LP |
| 3 | Arthur's Seat | Holyrood Park | 55.9446 | -3.1618 | Dormant volcano; easy summit walk | TA, Social |
| 4 | Palace of Holyroodhouse | Old Town | 55.9529 | -3.1723 | Queen's official Scottish residence | TA, LP |
| 5 | Calton Hill | East Central | 55.9551 | -3.1825 | Acropolis + panoramic views | TA, Social |
| 6 | Princes Street Gardens | New Town | 55.9522 | -3.1945 | Valley gardens with castle view | TA |
| 7 | National Museum of Scotland | Old Town | 55.9474 | -3.1904 | Free, excellent; Dolly the sheep | TA, LP |
| 8 | Victoria Street | Old Town | 55.9481 | -3.1945 | Curved street; Diagon Alley inspiration | TA, Social |
| 9 | Grassmarket | Old Town | 55.9476 | -3.1953 | Historic market square + pubs | TA |
| 10 | Dean Village | West End | 55.9530 | -3.2157 | Sub-valley hamlet on Water of Leith | Social, Reddit |
| 11 | The Real Mary King's Close | Old Town | 55.9498 | -3.1902 | Underground 17th-c street tour | TA |
| 12 | Scott Monument | New Town | 55.9523 | -3.1936 | Gothic spire to Sir Walter Scott | TA |
| 13 | Greyfriars Kirkyard + Bobby | Old Town | 55.9468 | -3.1907 | Harry Potter name inspirations | TA, Social |
| 14 | Royal Botanic Garden | Stockbridge | 55.9652 | -3.2102 | 72-acre garden with glasshouses | LP |
| 15 | Leith / Royal Yacht Britannia | Leith | 55.9817 | -3.1756 | Royal yacht museum | TA |

### 2-Hour Driving Tour — "Old + Holyrood + Leith"
1. **Castle Esplanade parking** (55.9486, -3.1999) — start.
2. Down **Johnston Terrace → Grassmarket** (~1 km).
3. **George IV Bridge north → Princes St** (~1 km).
4. **Calton Hill drive** (55.9551, -3.1825) (~1 km).
5. **Holyrood Palace + Arthur's Seat circular drive** (55.9529, -3.1723) (~3 km).
6. **Leith Walk north** to **Royal Yacht Britannia** (55.9817, -3.1756) (~4 km).
7. Return via **Inverleith Row + Botanic Garden** (55.9652, -3.2102) (~3 km).
8. End at **Dean Village overlook** (55.9530, -3.2157) (~3 km).

### 4-Hour Walking Tour — "Royal Mile + Arthur's Seat"
1. **Edinburgh Castle Esplanade** (55.9486, -3.1999).
2. **Royal Mile east** — Lawnmarket (55.9490, -3.1926).
3. **Victoria Street south detour** (55.9481, -3.1945).
4. **Grassmarket** (55.9476, -3.1953).
5. **Greyfriars Bobby + Kirkyard** (55.9468, -3.1907).
6. **National Museum of Scotland** (55.9474, -3.1904) — 45 min.
7. ☕ **The Elephant House café + pub row**.
8. Return to Royal Mile → **St. Giles' Cathedral** (55.9498, -3.1907).
9. **Mary King's Close** tour (55.9498, -3.1902).
10. **Canongate + Museum of Edinburgh** (55.9513, -3.1811).
11. **Palace of Holyroodhouse** (55.9529, -3.1723).
12. End with **Arthur's Seat mini-climb** (55.9446, -3.1618) or easier **Salisbury Crags** loop.

---

## 36. Istanbul 🔹

**Summary:** Two continents, three empires — Byzantine-Ottoman-Turkic layers in one megacity where Hagia Sophia faces the Blue Mosque across a plaza, and the Grand Bazaar has been selling carpets since 1461. **Strong for:** architecture_historic, food-heavy, first-time highlights, photo-heavy, scenic (Bosphorus). **Weak for:** minimal-walking; kid-focused tours (crowd density).
**Signature moments:** short wow — Hagia Sophia interior dome · food pause — Çiya Sofrası or Hafız Mustafa baklava · local texture — Kadıköy market (Asian side) · ending — Bosphorus ferry at sunset · worth the detour — Süleymaniye Mosque terrace view.
**Clusters:** `ist_sultanahmet` · `ist_grandbazaar` · `ist_beyoglu` · `ist_galata` · `ist_kadikoy` · `ist_bosphorus`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Hagia Sophia | Sultanahmet | 41.0086 | 28.9802 | 537 AD church-mosque-museum-mosque | TA, GM, LP |
| 2 | Blue Mosque (Sultanahmet Camii) | Sultanahmet | 41.0054 | 28.9768 | Six-minaret Ottoman masterpiece | TA, GM, LP |
| 3 | Topkapı Palace | Sultanahmet | 41.0115 | 28.9833 | Ottoman sultans' palace + harem | TA, LP |
| 4 | Grand Bazaar (Kapalıçarşı) | Beyazıt | 41.0106 | 28.9680 | 4,000 shops; one of oldest covered markets | TA, GM, LP |
| 5 | Basilica Cistern | Sultanahmet | 41.0084 | 28.9779 | 6th-c underground cistern; Medusa columns | TA, LP, Social |
| 6 | Spice Bazaar (Mısır Çarşısı) | Eminönü | 41.0165 | 28.9701 | 1660 Egyptian bazaar — saffron, Turkish delight | TA |
| 7 | Galata Tower | Galata | 41.0256 | 28.9742 | 1348 Genoese tower + 360° view | TA, Social |
| 8 | Bosphorus ferry cruise | Eminönü docks | 41.0171 | 28.9742 | Europe↔Asia shoreline | TA, LP, Viator |
| 9 | Süleymaniye Mosque | Fatih | 41.0162 | 28.9639 | Mimar Sinan's masterpiece | LP |
| 10 | Dolmabahçe Palace | Beşiktaş | 41.0392 | 29.0004 | 19th-c European-style palace | TA, LP |
| 11 | Istiklal Street + Taksim Square | Beyoğlu | 41.0351 | 28.9780 | Pedestrian shopping spine | TA |
| 12 | Chora Church (Kariye Mosque) | Fatih | 41.0315 | 28.9394 | Byzantine mosaics/frescoes | LP |
| 13 | Bebek / Ortaköy / Bosphorus villages | Bosphorus | 41.0475 | 29.0470 | Affluent coast neighborhoods | NYT36 |
| 14 | Karaköy + Tophane waterfront | Karaköy | 41.0256 | 28.9779 | Trendy cafés + galleries | NYT36 |
| 15 | Princes' Islands (Büyükada) | Marmara Sea | 40.8683 | 29.1245 | Car-free island escape | LP |

### 2-Hour Driving Tour — "Bosphorus Shoreline"
*Istanbul traffic is brutal — best early morning.*

1. **Eminönü waterfront** (41.0171, 28.9742) — start.
2. **Kennedy Caddesi coastal road** toward Topkapı (~2 km).
3. Around Seraglio Point (41.0108, 28.9837).
4. **Kennedy Cad west** past Yedikule (41.0120, 28.9223) — Theodosian walls view (~7 km).
5. Return north via **Kennedy Cad → Galata Bridge** (41.0205, 28.9738).
6. Over bridge → **Karaköy** → **Kabataş** (~3 km).
7. **Dolmabahçe Palace exterior** (41.0392, 29.0004).
8. **Bosphorus coast road north — Bebek, Arnavutköy, Rumeli Hisarı** (41.0835, 29.0514) (~12 km).
9. Return the same coast route for opposite light.

### 4-Hour Walking Tour — "Sultanahmet + Grand Bazaar"
1. **Hagia Sophia** (41.0086, 28.9802) — start.
2. **Sultanahmet Square / Hippodrome** (41.0060, 28.9762).
3. **Blue Mosque** (41.0054, 28.9768).
4. **Topkapı Palace** main gate (41.0115, 28.9833).
5. **Basilica Cistern** (41.0084, 28.9779).
6. ☕ **Hafiz Mustafa Turkish delight + tea** (41.0112, 28.9766).
7. West to **Grand Bazaar** (41.0106, 28.9680) — 45 min.
8. **Süleymaniye Mosque** (41.0162, 28.9639).
9. **Spice Bazaar** (41.0165, 28.9701).
10. 🐟 **Eminönü balık ekmek fish sandwich** boats (41.0177, 28.9737).
11. Cross **Galata Bridge** on foot (41.0205, 28.9738).
12. End at **Galata Tower** (41.0256, 28.9742).

---

## 37. Athens 🔹

**Summary:** The source code of Western civilization — Acropolis and Parthenon still the highest-altitude tourist site in Europe, with neon-buzzing Plaka below and a Riviera just 20 minutes away. **Strong for:** first-time highlights, architecture_historic, walking (hilly), photo-heavy. **Weak for:** scenic-driving tours; hot-summer walking.
**Signature moments:** short wow — Parthenon on the Acropolis · food pause — Psarras Taverna or Loukoumades Krinos · local texture — Monastiraki flea market · sunset — Lykavittos Hill · ending — Plaka tavernas evening.
**Clusters:** `ath_acropolis` · `ath_plaka` · `ath_monastiraki` · `ath_syntagma` · `ath_lykavittos`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Acropolis + Parthenon | Acropolis | 37.9715 | 23.7267 | 5th-c BC temple; canonical photo | TA, GM, LP |
| 2 | Acropolis Museum | Makrygianni | 37.9686 | 23.7285 | Bernard Tschumi glass museum below the hill | TA, LP |
| 3 | Ancient Agora + Temple of Hephaestus | Monastiraki | 37.9755 | 23.7222 | Best-preserved Doric temple | TA, LP |
| 4 | Plaka district | Plaka | 37.9715 | 23.7300 | Neoclassical lanes below Acropolis | TA, LP |
| 5 | Temple of Olympian Zeus | Central | 37.9694 | 23.7333 | 15 remaining Corinthian columns | TA |
| 6 | Panathenaic Stadium | Pangrati | 37.9684 | 23.7411 | Only marble stadium in the world; 1896 Olympics | TA |
| 7 | Anafiotika | Plaka | 37.9723 | 23.7286 | Hidden Cycladic-style hamlet on the Acropolis slope | Social |
| 8 | Monastiraki flea market + Square | Monastiraki | 37.9762 | 23.7258 | Tzistarakis Mosque + antique market | TA |
| 9 | Lycabettus Hill | Kolonaki | 37.9834 | 23.7445 | Highest natural point; funicular to top | TA, Social |
| 10 | Syntagma Square + Changing of the Guard | Central | 37.9756 | 23.7348 | Parliament evzones hourly ceremony | TA |
| 11 | National Archaeological Museum | Exarcheia | 37.9890 | 23.7324 | World's best ancient Greek collection | LP |
| 12 | Cape Sounion (Temple of Poseidon, 43 mi SE) | Sounion | 37.6501 | 24.0245 | Sunset temple on Aegean cliff | TA, LP |
| 13 | Psyri nightlife district | Psyri | 37.9785 | 23.7242 | Bars + mezedopoleia | NYT36 |
| 14 | Hadrian's Library + Roman Agora | Central | 37.9759 | 23.7251 | Roman overlay | LP |
| 15 | Varvakios Central Market | Central | 37.9792 | 23.7273 | Meat/fish hall; a real Athens scene | NYT36 |

### 2-Hour Driving Tour — "Acropolis Circle + Coast"
1. **Filopappos Hill parking** (37.9691, 23.7199) — start with Acropolis photo.
2. **Dionysiou Areopagitou (pedestrian on top section, skirt it)** via Propyleou (~1 km).
3. **Panathenaic Stadium** (37.9684, 23.7411).
4. **Syntagma Square drive-by** (37.9756, 23.7348).
5. **Vasilissis Sofias → Lycabettus Hill base** (37.9834, 23.7445) (~3 km).
6. South via **Kifisias → Poseidonos Ave coastal** (~10 km).
7. **Glyfada waterfront** (37.8655, 23.7576).
8. Return via **coast road north** for Aegean view (~8 km).
9. End at **Filopappos Hill** at sunset (37.9691, 23.7199).

### 4-Hour Walking Tour — "Acropolis + Plaka + Monastiraki"
1. **Acropolis main entrance (Propylaea)** (37.9715, 23.7267) — book timed entry.
2. **Parthenon + Erechtheion** walk (37.9715, 23.7266).
3. **Mars Hill (Areopagus)** (37.9724, 23.7249).
4. Descend to **Ancient Agora** (37.9755, 23.7222).
5. **Monastiraki Square** (37.9762, 23.7258).
6. **Flea market alleys** (37.9768, 23.7255).
7. ☕ **Little Kook or Klimataria** pause.
8. Climb up into **Plaka** (37.9715, 23.7300).
9. **Anafiotika hamlet** (37.9723, 23.7286).
10. 🍽️ **Liondi or Tzitzikas kai Mermigas** mezedes.
11. **Syntagma Square + Evzone guard** (37.9756, 23.7348).
12. **National Garden walk**.
13. End at **Panathenaic Stadium** (37.9684, 23.7411).

---

## 38. Copenhagen 🔹

**Summary:** Scandinavia's most livable harbor city — Nyhavn's colored canal row, Tivoli's 1843 amusement gardens, and a bicycle infrastructure that makes walking almost optional. **Strong for:** walking, family (Tivoli), architecture (historic + modern), food-heavy (new Nordic). **Weak for:** scenic drives.
**Signature moments:** short wow — Nyhavn colored houses · food pause — Torvehallerne market · local texture — Reffen street-food village · ending — Tivoli Gardens at night · worth the detour — Louisiana Museum of Modern Art (35 min north).
**Clusters:** `cph_indre` · `cph_nyhavn` · `cph_vesterbro` · `cph_christianshavn` · `cph_refshaleoen`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Nyhavn | Central | 55.6798 | 12.5914 | Painted 17th-c townhouses along canal | TA, GM, Social |
| 2 | The Little Mermaid | Langelinie | 55.6929 | 12.5994 | Hans Christian Andersen statue | TA, GM |
| 3 | Tivoli Gardens | Central | 55.6737 | 12.5683 | 1843 amusement park inspired Disneyland | TA, GM, LP |
| 4 | Rosenborg Castle + crown jewels | Central | 55.6855 | 12.5771 | 1606 Renaissance royal palace | TA, LP |
| 5 | Christiansborg Palace + Tower | Slotsholmen | 55.6761 | 12.5797 | Parliament + free observation tower | TA |
| 6 | Freetown Christiania | Christianshavn | 55.6735 | 12.5950 | Self-proclaimed autonomous hippie community | TA, LP |
| 7 | Amalienborg Palace + changing of the guard | Frederiksstaden | 55.6840 | 12.5932 | Rococo royal residence | TA |
| 8 | Round Tower (Rundetårn) | Central | 55.6814 | 12.5758 | 1642 tower with ramp instead of stairs | TA, LP |
| 9 | Strøget (pedestrian street) | Central | 55.6784 | 12.5745 | One of longest pedestrian streets in Europe | TA |
| 10 | Reffen / Refshaleøen food street | Refshaleøen | 55.6933 | 12.6099 | Street-food container city | NYT36 |
| 11 | Copenhagen Opera House | Holmen | 55.6866 | 12.6011 | Henning Larsen harbor opera | LP |
| 12 | Our Savior's Church tower | Christianshavn | 55.6721 | 12.5910 | Climbable spiral exterior spire | TA, Social |
| 13 | Louisiana Museum (22 mi N) | Humlebæk | 55.9695 | 12.5440 | Modern art by the sea | TA, LP |
| 14 | Kronborg Castle (Hamlet, 29 mi N) | Helsingør | 56.0382 | 12.6213 | Shakespeare's Elsinore | TA |
| 15 | Frederiksborg Castle (25 mi N) | Hillerød | 55.9347 | 12.3006 | Renaissance water castle | LP |

### 2-Hour Driving Tour — "Harbor + Langelinie"
1. **Rådhuspladsen / Tivoli perimeter** (55.6760, 12.5683) — start.
2. **H.C. Andersens Blvd** south.
3. **Langebro bridge** across harbor (~1 km).
4. **Christianshavn — Our Savior's** (55.6721, 12.5910).
5. **Christiania exterior** (55.6735, 12.5950).
6. **Knippelsbro back to Slotsholmen** (~1.5 km).
7. North along **Havnegade → Nyhavn bridge** (55.6798, 12.5914).
8. **Esplanaden → Kastellet** (55.6902, 12.5938).
9. **Langelinie — Little Mermaid** (55.6929, 12.5994).
10. End at **Reffen** (55.6933, 12.6099) via Refshalevej bridge.

### 4-Hour Walking Tour — "Nyhavn + Old Town + Tivoli"
1. **Kongens Nytorv** (55.6792, 12.5852).
2. **Nyhavn north side photo** (55.6798, 12.5914).
3. **Amalienborg Palace + guard change** (55.6840, 12.5932).
4. **Frederik's Church (Marble Church)** (55.6836, 12.5912).
5. **Langelinie → Little Mermaid** (55.6929, 12.5994).
6. ☕ **Andersen Bakery or Sankt Peders Stræde** cinnamon bun.
7. Return via **Bredgade → Kongens Nytorv**.
8. **Strøget pedestrian** west (55.6784, 12.5745).
9. **Round Tower climb** (55.6814, 12.5758).
10. **Christiansborg Tower** (55.6761, 12.5797).
11. 🧆 **Torvehallerne food hall** optional (55.6830, 12.5703).
12. End at **Tivoli Gardens** at dusk (55.6737, 12.5683).

---

## 39. Venice 🔹

**Summary:** 118 islands, 400 bridges, zero cars — La Serenissima is the most implausibly beautiful city in the world and the only one in which the "walking tour" IS the only tour. **Strong for:** walking, romantic, photo-heavy, architecture_historic. **Weak for:** driving (literally no cars); family with strollers (bridges).
**Signature moments:** short wow — Piazza San Marco arrival · food pause — All'Arco cicchetti bar · local texture — Rialto market morning · sunset — Giudecca Canal from Zattere · ending — St Mark's at night with orchestra cafés · worth the detour — Burano's painted houses.
**Clusters:** `ven_sanmarco` · `ven_rialto` · `ven_dorsoduro` · `ven_castello` · `ven_cannaregio` · `ven_burano`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | St. Mark's Square + Basilica | San Marco | 45.4342 | 12.3388 | Napoleon's "drawing room of Europe" | TA, GM, LP |
| 2 | Doge's Palace | San Marco | 45.4337 | 12.3402 | Venetian Gothic + Bridge of Sighs | TA, LP |
| 3 | Rialto Bridge + Market | San Marco/San Polo | 45.4380 | 12.3358 | 1591 arched bridge; morning fish market | TA, GM, LP |
| 4 | Grand Canal + Vaporetto #1 | Central | 45.4347 | 12.3383 | The main artery; essential boat ride | TA, LP |
| 5 | Murano (glass) + Burano (colors) | Lagoon | 45.4586 | 12.3527 | Island day trip; colorful fisherman houses | TA, Social |
| 6 | St. Mark's Campanile | San Marco | 45.4343 | 12.3389 | 98-m bell tower with elevator | TA |
| 7 | Gallerie dell'Accademia | Dorsoduro | 45.4313 | 12.3281 | Titian + Tintoretto collection | LP |
| 8 | Peggy Guggenheim Collection | Dorsoduro | 45.4310 | 12.3311 | Modern art in Grand Canal palazzo | LP |
| 9 | Libreria Acqua Alta | Castello | 45.4380 | 12.3424 | Books in gondolas; flood-proof bookshop | Social |
| 10 | Santa Maria della Salute | Dorsoduro | 45.4303 | 12.3346 | Baroque basilica at Grand Canal entrance | TA |
| 11 | Dorsoduro + Zattere promenade | Dorsoduro | 45.4290 | 12.3290 | Quieter neighborhood with Giudecca canal views | NYT36 |
| 12 | Jewish Ghetto (Cannaregio) | Cannaregio | 45.4446 | 12.3260 | Oldest Jewish ghetto in the world (1516) | LP |
| 13 | Bridge of Sighs + Prison | San Marco | 45.4340 | 12.3410 | Covered bridge to former prisons | TA |
| 14 | Scala Contarini del Bovolo | San Marco | 45.4356 | 12.3349 | Hidden external spiral staircase | Social |
| 15 | T Fondaco dei Tedeschi rooftop (free) | San Marco | 45.4386 | 12.3367 | Free Grand Canal panorama with reservation | Social |

### "2-Hour Driving Tour" — N/A (Venice is car-free)
*Use this as a **2-hour Grand Canal Vaporetto #1 + water taxi** tour instead:*

1. **Piazzale Roma vaporetto stop** (45.4386, 12.3194) — start.
2. **Vaporetto #1 eastbound** down Grand Canal.
3. Pass **Santa Lucia station → Ca' d'Oro** (45.4408, 12.3340).
4. **Rialto Bridge** (45.4380, 12.3358).
5. Continue past **Ca' Rezzonico, Accademia Bridge** (45.4313, 12.3281).
6. Off at **San Marco-Vallaresso** (45.4330, 12.3382).
7. Switch to line going to **San Giorgio Maggiore island** for best skyline photo (45.4294, 12.3434).
8. Back to San Marco → Bacino San Marco sunset ride.
9. Optional vaporetto #4.2 to **Murano** if time (45.4586, 12.3527).

### 4-Hour Walking Tour — "San Marco + Rialto + Dorsoduro"
1. **St. Mark's Square** (45.4342, 12.3388) — start.
2. **St. Mark's Basilica** (45.4345, 12.3397) — book skip-the-line.
3. **Doge's Palace + Bridge of Sighs** (45.4337, 12.3402).
4. **St. Mark's Campanile** (45.4343, 12.3389) — elevator to top.
5. ☕ **Caffè Florian** under the arcade (45.4338, 12.3380).
6. North via Mercerie to **Rialto Bridge** (45.4380, 12.3358).
7. **Rialto Market fish+produce** (45.4398, 12.3342).
8. 🍷 **Cantina Do Mori cicchetti crawl** (45.4397, 12.3339).
9. Cross back via Rialto to **Scala Contarini del Bovolo** (45.4356, 12.3349).
10. **Accademia Bridge** (45.4314, 12.3283).
11. **Peggy Guggenheim** (45.4310, 12.3311) or exterior.
12. **Zattere promenade walk** (45.4290, 12.3290).
13. End at **Santa Maria della Salute** (45.4303, 12.3346) at sunset.

---

## 40. Florence 🔹

**Summary:** The birthplace of the Renaissance — Uffizi, Duomo, Michelangelo's David, and a compact walkable historic center where every church has a Giotto or a Botticelli. **Strong for:** walking, architecture_historic, museums, romantic. **Weak for:** driving (ZTL restrictions); family (indoor-museum energy).
**Signature moments:** short wow — Duomo Brunelleschi dome · food pause — All'Antico Vinaio panini · local texture — Oltrarno artisan workshops · sunset — Piazzale Michelangelo · worth the detour — Boboli Gardens.
**Clusters:** `flr_duomo` · `flr_uffizi` · `flr_oltrarno` · `flr_sanlorenzo` · `flr_santacroce`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Duomo (Santa Maria del Fiore) | Central | 43.7731 | 11.2560 | Brunelleschi's dome; #1 Florence photo | TA, GM, LP |
| 2 | Uffizi Gallery | Central | 43.7678 | 11.2553 | Botticelli Venus + Renaissance pantheon | TA, GM, LP |
| 3 | Ponte Vecchio | Central | 43.7680 | 11.2530 | 1345 goldsmith bridge over the Arno | TA, GM, LP |
| 4 | Accademia (David) | Central | 43.7767 | 11.2589 | Michelangelo's David | TA, LP |
| 5 | Piazzale Michelangelo | Oltrarno | 43.7629 | 11.2648 | Sunset panorama of all Florence | TA, Social |
| 6 | Piazza della Signoria + Palazzo Vecchio | Central | 43.7696 | 11.2558 | Outdoor sculpture museum + town hall | TA, LP |
| 7 | Santa Croce | Santa Croce | 43.7685 | 11.2622 | Pantheon of Italians; Michelangelo+Galileo tombs | TA, LP |
| 8 | Boboli Gardens + Pitti Palace | Oltrarno | 43.7650 | 11.2496 | Medici palace + sculpture garden | TA, LP |
| 9 | Baptistery (Gates of Paradise) | Central | 43.7729 | 11.2555 | Ghiberti's 1425 gilded doors | TA |
| 10 | Bargello | Central | 43.7702 | 11.2579 | Donatello's bronze David | LP |
| 11 | Mercato Centrale | San Lorenzo | 43.7769 | 11.2531 | Upstairs food hall; lampredotto street food | NYT36, Social |
| 12 | Santo Spirito | Oltrarno | 43.7652 | 11.2479 | Brunelleschi's other church; bohemian square | LP |
| 13 | Giotto's Campanile | Central | 43.7729 | 11.2559 | 414-step climb beside the Duomo | TA |
| 14 | San Miniato al Monte | Oltrarno | 43.7594 | 11.2649 | 1018 Romanesque church above Piazzale | LP |
| 15 | Medici Chapels | San Lorenzo | 43.7752 | 11.2534 | Michelangelo tombs | LP |

### 2-Hour Driving Tour — "Hills + Chianti Teaser"
*Historic center is ZTL. Drive perimeter + hills only.*

1. **Piazzale Michelangelo** (43.7629, 11.2648) — start with panorama.
2. **Viale dei Colli** loop (~5 km) past San Miniato.
3. **Via Senese south → Galluzzo Certosa** (43.7343, 11.2418).
4. Return via **SS2 → Porta Romana** (~5 km).
5. **Viali di Circonvallazione around city** — Viale Machiavelli → Viale Pascoli → Porta San Gallo (~4 km).
6. **Fiesole hilltop road** (43.8070, 11.2920) (~6 km).
7. Etruscan amphitheater overlook.
8. Return via SR65 → Porta San Gallo (~6 km).

### 4-Hour Walking Tour — "Renaissance Core"
1. **Piazza del Duomo** (43.7731, 11.2560) — start.
2. **Baptistery Gates of Paradise** (43.7729, 11.2555).
3. **Campanile climb or Duomo dome climb** (43.7729, 11.2559).
4. **Piazza della Repubblica** (43.7712, 11.2539).
5. **Piazza della Signoria + Loggia dei Lanzi** (43.7696, 11.2558).
6. **Uffizi exterior/visit** (43.7678, 11.2553).
7. **Ponte Vecchio** (43.7680, 11.2530).
8. Cross to **Oltrarno — Pitti Palace + Boboli** (43.7650, 11.2496).
9. **Santo Spirito** square pause (43.7652, 11.2479).
10. ☕🥪 **All'Antico Vinaio** back across river (43.7702, 11.2568).
11. **Santa Croce** (43.7685, 11.2622).
12. End at **Mercato Centrale upstairs** (43.7769, 11.2531) — dinner.

---

# REST OF WORLD

---

## 41. Tokyo ✅ (v2)

### A. City summary

23-ward megacity where neon Shibuya, temple-lined Asakusa, and Edo-era garden temples coexist in perfect fractal order — Tokyo is the cleanest, safest, most efficient city most travelers will ever see.

- **Strongest for:** walking (multi-neighborhood cluster-based), food-heavy, local flavor / hidden gems (Shimokita, Yanaka, Kichijoji), photo-heavy.
- **Weak for:** driving (not advisable; taxis for point-to-point only); minimal-walking tours (the walking is the point).
- **Unique strength:** Tokyo neighborhoods function as self-contained 3-4h mini-tours — more than any other city, tours here map 1:1 to clusters.

### B. Gold-standard stop graph

**Structured attributes (key stops):**

| Stop | stop_type | iconicity | scenic | story | dwell | walking | best_time | cluster |
|---|---|---|---|---|---|---|---|---|
| Shibuya Scramble + Hachiko | icon | 10 | 6 | 9 | 15 | light | any | tky_shibuya |
| Shibuya Sky observation | viewpoint | 8 | 10 | 6 | 60 | light | golden_hour | tky_shibuya |
| Meiji Jingu Shrine | icon | 9 | 8 | 9 | 45 | moderate | morning | tky_harajuku |
| Senso-ji / Kaminarimon | icon | 10 | 8 | 10 | 45 | light | morning | tky_asakusa |
| Omoide Yokocho | neighborhood | 8 | 8 | 9 | 30 | light | night | tky_shinjuku |
| Golden Gai | neighborhood | 8 | 7 | 9 | 45 | light | night | tky_shinjuku |
| Tsukiji Outer Market | food | 8 | 6 | 9 | 60 | light | morning | tky_tsukiji |
| teamLab Planets | museum | 9 | 10 | 7 | 90 | light | any | tky_toyosu |
| Imperial Palace East Garden | park | 7 | 8 | 9 | 45 | moderate | any | tky_marunouchi |
| Ginza shopping corridor | neighborhood | 7 | 7 | 7 | 45 | light | any | tky_ginza |
| Tokyo Tower + Zojo-ji | icon | 8 | 8 | 8 | 45 | light | night | tky_minato |
| Shimokitazawa | neighborhood | 3 | 7 | 7 | 120 | light | any | shimokita |
| Yanaka Ginza | neighborhood | 3 | 7 | 8 | 45 | light | any | tky_yanaka |

**Clusters:** `tky_shibuya` · `tky_harajuku` · `tky_asakusa` · `tky_shinjuku` · `tky_tsukiji` · `tky_toyosu` · `tky_marunouchi` · `tky_ginza` · `tky_minato` · `shimokita` · `tky_yanaka`

### Signature moments

| Slot | Stop |
|---|---|
| Best skyline reveal | Shibuya Sky open-air rooftop at golden hour |
| Best sunset stop | Odaiba waterfront (Rainbow Bridge backdrop) |
| Best short wow | Shibuya Scramble from Starbucks 2F |
| Best scenic drive segment | Rainbow Bridge loop (taxi; driving not advised) |
| Best coffee/food pause | Bear Pond Espresso (Shimokita) or Blue Bottle Aoyama |
| Best local texture | Shimokitazawa or Yanaka Ginza |
| Best ending point | Omoide Yokocho at 7pm (lanterns, yakitori smoke) |
| Best worth-the-detour | teamLab Planets (requires timed-entry reservation) |

### C. Benchmark tours

#### Tour TKY-1 — "Shimokitazawa Drift" (3h walking) [GOLD]

See full benchmark with per-stop attributes and score breakdown in [gold-standard-tours.md — Tour 9](./gold-standard-tours.md#tour-9--shimokitazawa-drift). Target user: second-time Tokyo visitor wanting local Tokyo. Intent tags: `hidden_gems`, `local_flavor`, `food_heavy` (soft). **`tour_absolute` = 85.5 · hidden_gems fit = 97**.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Shibuya Scramble Crossing | Shibuya | 35.6595 | 139.7004 | World's busiest intersection; Hachiko + cinema icon | TA, GM, Social |
| 2 | Senso-ji Temple (Asakusa) | Asakusa | 35.7148 | 139.7967 | Tokyo's oldest temple; Kaminarimon lantern gate | TA, GM, LP |
| 3 | Meiji Jingu Shrine | Harajuku | 35.6764 | 139.6993 | Forested shrine to Emperor Meiji | TA, LP |
| 4 | Tsukiji Outer Market | Tsukiji | 35.6654 | 139.7707 | Sushi breakfast + street-food stalls | TA, LP, NYT36 |
| 5 | Tokyo Skytree | Sumida | 35.7101 | 139.8107 | 634-m tallest tower in Japan | TA |
| 6 | Akihabara Electric Town | Akihabara | 35.7023 | 139.7745 | Anime + retro games capital | TA, Social |
| 7 | Shinjuku Golden Gai + Omoide Yokocho | Shinjuku | 35.6940 | 139.7036 | 200 tiny post-war bars in two alleys | NYT36, Social |
| 8 | teamLab Planets / Borderless | Odaiba / Azabudai | 35.6265 | 139.7854 | Immersive-art museum; unmatched social pull | TA, Social |
| 9 | Shibuya Sky observation deck | Shibuya | 35.6586 | 139.7016 | Open-air rooftop 229m over Scramble | Social, Reddit |
| 10 | Imperial Palace East Garden | Marunouchi | 35.6852 | 139.7528 | Former Edo Castle grounds | TA |
| 11 | Ginza shopping district | Ginza | 35.6717 | 139.7649 | Tokyo's luxury corridor; Mitsukoshi dept store | TA, LP |
| 12 | Harajuku / Takeshita Street | Harajuku | 35.6709 | 139.7029 | Youth fashion + crepe lanes | TA, Social |
| 13 | Ueno Park + museums | Ueno | 35.7154 | 139.7735 | Cherry blossoms + zoo + 4 national museums | TA, LP |
| 14 | Shinjuku Gyoen National Garden | Shinjuku | 35.6852 | 139.7100 | 144-acre garden across 3 styles | LP |
| 15 | Tokyo Tower + Zojo-ji | Minato | 35.6586 | 139.7454 | Eiffel-inspired 1958 icon + temple foreground | TA |

#### Tour TKY-2 — "Imperial Loop + Rainbow Bridge" (2h taxi/driving)

Intent: `first_time_highlights`, `minimal_walking`, `scenic_sunset` (evening).

### 2-Hour Driving Tour — "Imperial Loop + Rainbow Bridge"
*Tokyo is a driver's maze; stick to expressways/landmarks. Taxi-hire recommended.*

1. **Tokyo Tower** (35.6586, 139.7454) — start.
2. **Hibiya Dori north → Imperial Palace exterior moat loop** (~3 km).
3. **Nihonbashi district** (35.6838, 139.7745).
4. **Ginza → Shimbashi** (~2 km).
5. **Rainbow Bridge onto Odaiba** (35.6363, 139.7630) (~6 km).
6. **Daiba Koen** + Statue of Liberty replica (35.6293, 139.7754).
7. Back over Rainbow Bridge.
8. **Roppongi Hills drive-by** (35.6605, 139.7290) (~5 km).
9. End at **Shibuya Scramble** (35.6595, 139.7004) (~3 km).

#### Tour TKY-3 — "Shibuya + Harajuku + Meiji" (4h walking)

*The canonical "Tokyo's greatest hits" walk — counterpoint to the hidden-gems gold. Connects three major clusters in one western-Tokyo arc.*

Intent: `first_time_highlights`, `photo_heavy`, `food_heavy` (at Shinjuku).

1. **Hachiko statue + Shibuya Scramble** (35.6595, 139.7004).
2. **Shibuya Sky** (35.6586, 139.7016) — timed entry.
3. Walk **Omotesando Hills Avenue** north (~1.5 km).
4. **Meiji Jingu Shrine** (35.6764, 139.6993).
5. **Takeshita Street Harajuku** (35.6709, 139.7029).
6. Crepe at **Marion Crepes** or **Blue Bottle Aoyama**.
7. Metro one stop or walk to **Shinjuku**.
8. **Shinjuku Gyoen Garden** (35.6852, 139.7100) — short stroll.
9. **Omoide Yokocho** (35.6937, 139.6996) — yakitori smoke lane.
10. **Ichiran Ramen Shinjuku** pause.
11. **Shinjuku Golden Gai** (35.6940, 139.7036) — pick one mini-bar.
12. End at **Kabukicho neon + Godzilla head** (35.6947, 139.7021).

### D. Scoring metadata

**TKY-1 (Shimokitazawa Drift):** `tour_absolute = 85.5` · iconic 4.5 · geographic 9.0 · time_realism 9.0 · narrative 8.5 · scenic 7.5 · variety 9.5 · usability 9.5. Primary intent `hidden_gems` = 97. **Final (pure_custom) = 92.4**. Full breakdown in [gold-standard-tours.md — Tour 9](./gold-standard-tours.md#tour-9--shimokitazawa-drift).

**TKY-2 (Imperial Loop + Rainbow Bridge):** `tour_absolute ≈ 78` · iconic 7.5 · geographic 8.5 · time_realism 8.0 · narrative 7.5 · scenic 8.0 · variety 7.0 · usability 7.0. Primary intent `minimal_walking` = 82. **Final (hybrid) = 79.6**.

**TKY-3 (Shibuya + Harajuku + Meiji):** `tour_absolute ≈ 90` · iconic 9.5 · geographic 8.5 · time_realism 8.5 · narrative 9.0 · scenic 8.5 · variety 9.5 · usability 8.5. Primary intent `first_time_highlights` = 94. **Final (hybrid) = 91.6**. Strong candidate for gold promotion on the "first-time Tokyo" archetype.

---

## 42. Kyoto 🔹

**Summary:** Japan's 1,000-year imperial capital — 1,600 Buddhist temples, 400 Shinto shrines, preserved wooden streets in Gion, and the most photogenic concentration of autumn leaves and cherry blossoms in the world. **Strong for:** walking, architecture_historic, photo-heavy (seasons), romantic. **Weak for:** scenic driving; summer heat; overcrowded mid-season icons.
**Signature moments:** short wow — Fushimi Inari torii gates at sunrise · food pause — Nishiki Market street food · local texture — Pontocho Alley evening · sunset — Kiyomizu-dera terrace · worth the detour — Arashiyama bamboo grove.
**Clusters:** `kyo_gion` · `kyo_higashiyama` · `kyo_arashiyama` · `kyo_fushimi` · `kyo_nishiki` · `kyo_northern-temples`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Fushimi Inari Taisha | Fushimi | 34.9671 | 135.7727 | 10,000 vermillion torii gates climbing mountain | TA, GM, Social |
| 2 | Kinkaku-ji (Golden Pavilion) | NW Kyoto | 35.0394 | 135.7292 | Gold-leafed temple over reflecting pond | TA, GM, LP |
| 3 | Arashiyama Bamboo Grove | Arashiyama | 35.0170 | 135.6712 | Sound-designated bamboo tunnel | TA, Social |
| 4 | Kiyomizu-dera | Higashiyama | 34.9949 | 135.7850 | Wooden temple on stilts + blossom view | TA, GM, LP |
| 5 | Gion district + Hanami-koji | Gion | 35.0034 | 135.7788 | Geiko (geisha) district; wood machiya | TA, LP, Social |
| 6 | Philosopher's Path | NE Kyoto | 35.0252 | 135.7933 | 2-km canal walk beneath cherry trees | TA, LP |
| 7 | Nishiki Market | Central | 35.0051 | 135.7651 | 400m "Kyoto's Kitchen" food alley | TA, NYT36 |
| 8 | Ginkaku-ji (Silver Pavilion) | NE Kyoto | 35.0269 | 135.7983 | Sand garden temple; end of Philosopher's Path | TA, LP |
| 9 | Nijo Castle | Central | 35.0142 | 135.7480 | Shogun's residence; nightingale floors | TA, LP |
| 10 | Ryoan-ji (rock garden) | NW Kyoto | 35.0344 | 135.7185 | World's most famous Zen rock garden | TA, LP |
| 11 | Tenryu-ji Temple | Arashiyama | 35.0158 | 135.6736 | UNESCO Zen temple beside bamboo | LP |
| 12 | Pontocho Alley | Central | 35.0067 | 135.7702 | Narrow lantern-lit riverside dining alley | TA, Social |
| 13 | Higashiyama old streets (Ninenzaka, Sannenzaka) | Higashiyama | 34.9975 | 135.7812 | Preserved Edo-era teahouse lanes | TA, Social |
| 14 | Kyoto Imperial Palace | Central | 35.0254 | 135.7621 | Former residence of Japanese emperors | LP |
| 15 | Yasaka Shrine + Maruyama Park | Gion | 35.0037 | 135.7786 | Sakura hotspot + weeping cherry tree | LP |

### 2-Hour Driving Tour — "North Temples Loop"
*Central Kyoto works with car; Arashiyama or Fushimi each need a half-day each — this loop hits the N-NW belt.*

1. **Kyoto Station** (34.9858, 135.7585) — start.
2. **Higashi Honganji exterior** (34.9910, 135.7583).
3. **Nijo Castle exterior** (35.0142, 135.7480) (~3 km).
4. **Kitano Tenmangu** (35.0314, 135.7353) (~3 km).
5. **Ryoan-ji** (35.0344, 135.7185) (~2 km).
6. **Kinkaku-ji (Golden Pavilion)** (35.0394, 135.7292) (~1.5 km).
7. **Kamogawa river east** past Kyoto Imperial Palace (35.0254, 135.7621) (~4 km).
8. End at **Ginkaku-ji (Silver)** (35.0269, 135.7983) (~4 km) or return downtown.

### 4-Hour Walking Tour — "Higashiyama + Gion + Pontocho"
1. **Kiyomizu-dera** (34.9949, 135.7850) — start uphill.
2. **Sannenzaka + Ninenzaka stone lanes** (34.9975, 135.7812) downhill.
3. **Yasaka Pagoda** (34.9987, 135.7783).
4. **Kodai-ji temple** (34.9999, 135.7814).
5. 🍵 **Matcha pause** at traditional tea shop on Nene-no-Michi.
6. **Maruyama Park + weeping cherry** (35.0037, 135.7786).
7. **Yasaka Shrine** (35.0037, 135.7786).
8. **Gion Hanami-koji Street** (35.0034, 135.7788).
9. **Shirakawa lane** (35.0073, 135.7753).
10. Cross Kamo River → **Pontocho Alley** (35.0067, 135.7702).
11. 🍱 Kaiseki or yakitori dinner in Pontocho.
12. End at **Kamogawa riverside strolling** (35.0090, 135.7691).

---

## 43. Sydney 🔹

**Summary:** The harbor-city of postcards — Opera House, Harbour Bridge, Bondi Beach, all within 30 minutes of downtown, with the world's most photogenic ferry commute. **Strong for:** scenic (harbor), first-time highlights, family, walking + ferry hybrid tours. **Weak for:** compact walking-only (spread-out attractions).
**Signature moments:** short wow — Opera House arrival by ferry · food pause — Bourke Street Bakery · local texture — Bondi to Coogee coastal walk · sunset — Mrs Macquarie's Chair · worth the detour — Blue Mountains day trip.
**Clusters:** `syd_cbd` · `syd_rocks` · `syd_circularquay` · `syd_bondi` · `syd_paddington` · `syd_manly`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Sydney Opera House | Bennelong Point | -33.8568 | 151.2153 | Jørn Utzon's 1973 shells | TA, GM, LP |
| 2 | Sydney Harbour Bridge | Harbour | -33.8523 | 151.2108 | Iron-arch icon; BridgeClimb | TA, GM, LP |
| 3 | Bondi Beach | Bondi | -33.8914 | 151.2766 | Crescent surf beach; Bondi-Coogee walk | TA, GM, LP |
| 4 | Bondi to Coogee Coastal Walk | East Coast | -33.9055 | 151.2597 | 6-km cliff-path | TA, Social |
| 5 | Royal Botanic Garden + Mrs Macquarie's Chair | CBD | -33.8632 | 151.2162 | Harbor-framing viewpoint | TA |
| 6 | The Rocks historic district | The Rocks | -33.8589 | 151.2086 | Original colonial sandstone quarter | TA |
| 7 | Darling Harbour + SEA LIFE | CBD | -33.8706 | 151.2005 | Family waterfront + aquarium | TA |
| 8 | Manly Ferry + Manly Beach | Ferry / Manly | -33.7970 | 151.2856 | Best ferry ride in Sydney | TA, LP |
| 9 | Taronga Zoo + skyline | Mosman | -33.8432 | 151.2411 | Harbor-facing zoo + chairlift view | TA |
| 10 | Queen Victoria Building | CBD | -33.8717 | 151.2069 | Romanesque shopping gallery | TA |
| 11 | Sydney Tower Eye | CBD | -33.8703 | 151.2090 | Tallest observation in city | TA |
| 12 | Watsons Bay + Gap Bluff | Eastern Suburbs | -33.8411 | 151.2792 | Ocean cliffs + Doyle's fish | LP |
| 13 | Blue Mountains Three Sisters (60 mi W) | Katoomba | -33.7320 | 150.3120 | Sandstone rock formation day trip | TA |
| 14 | Barangaroo Reserve + Crown Sydney | Barangaroo | -33.8599 | 151.2020 | New harbor park + tower | NYT36 |
| 15 | Surry Hills / Paddington / Newtown | Inner East | -33.8884 | 151.2150 | Terrace-house café districts | NYT36 |

### 2-Hour Driving Tour — "Harbour + Eastern Beaches"
1. **Mrs Macquarie's Point** (-33.8593, 151.2234) — start with Opera House + Bridge in one frame.
2. **Cahill Expressway past Circular Quay** (~1.5 km).
3. **Harbour Bridge** north to Milsons Point (-33.8478, 151.2118) (~1 km).
4. **Kirribilli → Cremorne Point lookout** (-33.8410, 151.2278) (~3 km).
5. South over bridge back.
6. **William St → Kings Cross → Bondi** (-33.8914, 151.2766) (~8 km).
7. **Coastal drive south — Tamarama, Bronte, Coogee** (-33.9198, 151.2585) (~5 km).
8. Back via **Anzac Pde / Oxford St → Centennial Park** (~6 km).
9. End at **Paddington Reservoir Gardens** (-33.8854, 151.2275).

### 4-Hour Walking Tour — "CBD Harbour Loop + Botanic"
1. **Sydney Opera House forecourt** (-33.8568, 151.2153) — start.
2. **Royal Botanic Garden path south** (~1 km).
3. **Mrs Macquarie's Chair** (-33.8620, 151.2229).
4. Back to **Art Gallery of NSW** exterior (-33.8688, 151.2171).
5. **Domain parkland** south.
6. **Hyde Park + ANZAC Memorial** (-33.8745, 151.2108).
7. **Queen Victoria Building** (-33.8717, 151.2069).
8. ☕ **Bourke Street Bakery or Strand Arcade** pause.
9. Down **George Street** to **The Rocks** (-33.8589, 151.2086).
10. **Rocks markets + MCA** (-33.8597, 151.2090).
11. **Circular Quay ferries** (-33.8614, 151.2105).
12. 🍤 Ferry + fish 'n' chips at **Manly Wharf** OR dinner at **Opera Bar** under the Opera House sails.

---

## 44. Melbourne 🔹

**Summary:** Australia's coffee-laneway capital — Hidden graffiti alleys, Victorian arcades, MCG cricket cathedral, and ocean-side Great Ocean Road launching point. **Strong for:** walking (laneway-based), food-heavy (coffee + brunch), local flavor, architecture (Victorian arcades). **Weak for:** major-icon tourism.
**Signature moments:** short wow — Hosier Lane street art · food pause — Pellegrini's espresso or Chin Chin · local texture — Queen Victoria Market · worth the detour — Great Ocean Road.
**Clusters:** `mel_cbd` · `mel_southbank` · `mel_fitzroy` · `mel_stkilda` · `mel_docklands` · `mel_greatoceanroad`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Hosier Lane street art | CBD | -37.8168 | 144.9691 | Melbourne's graffiti showcase | TA, Social |
| 2 | Federation Square | CBD | -37.8180 | 144.9690 | Civic square + ACMI museum | TA |
| 3 | Queen Victoria Market | CBD | -37.8076 | 144.9568 | 1878 market; Night Market in summer | TA, GM |
| 4 | Royal Botanic Gardens | South Yarra | -37.8304 | 144.9796 | 94-acre gardens + Shrine views | TA |
| 5 | St Kilda + Luna Park | St Kilda | -37.8675 | 144.9755 | Beach + vintage amusement park | TA |
| 6 | Melbourne Cricket Ground (MCG) | Yarra Park | -37.8200 | 144.9834 | 100k-seat cricket mecca | TA |
| 7 | Great Ocean Road (90 mi SW) | Torquay start | -38.3305 | 144.3253 | Twelve Apostles + coastal drive | TA, LP |
| 8 | Brighton Bathing Boxes | Brighton | -37.9116 | 144.9836 | 82 painted beach huts | Social |
| 9 | National Gallery of Victoria | CBD | -37.8226 | 144.9689 | Southern Hemisphere's largest art museum | LP |
| 10 | Eureka Skydeck | Southbank | -37.8213 | 144.9644 | 88-floor Edge glass cube | TA |
| 11 | Block + Royal Arcade | CBD | -37.8139 | 144.9645 | 1892 Parisian-style arcades | TA |
| 12 | Degraves Street + Centre Place laneways | CBD | -37.8157 | 144.9651 | Coffee-laneway microculture | NYT36, Social |
| 13 | Fitzroy + Brunswick Street | Fitzroy | -37.7984 | 144.9786 | Bohemian cafés + vintage | NYT36 |
| 14 | State Library Victoria | CBD | -37.8099 | 144.9653 | Gorgeous domed reading room | Social |
| 15 | Shrine of Remembrance | South Yarra | -37.8305 | 144.9731 | WWI memorial with city view | LP |

### 2-Hour Driving Tour — "Yarra + Beach Loop"
1. **Federation Square** (-37.8180, 144.9690) — start.
2. **Birrarung Marr along Yarra south bank** (~1.5 km).
3. **Alexandra Ave south → Royal Botanic Gardens** (-37.8304, 144.9796).
4. **Fawkner Park → St Kilda Rd south** (~5 km).
5. **St Kilda Pier + Luna Park** (-37.8675, 144.9755).
6. **Beach Rd south → Brighton Bathing Boxes** (-37.9116, 144.9836) (~6 km).
7. Return via **Dandenong Rd north → Chapel St** (~8 km).
8. Back to CBD via **St Kilda Rd → Southbank Eureka** (-37.8213, 144.9644) (~4 km).

### 4-Hour Walking Tour — "CBD Laneways + Arcades"
1. **Flinders Street Station** (-37.8183, 144.9671) — start.
2. **Degraves Street coffee laneway** (-37.8157, 144.9651).
3. **Centre Place** (-37.8159, 144.9660).
4. **Block Arcade** (-37.8139, 144.9645) — Hopetoun Tea Rooms.
5. **Royal Arcade + Gog & Magog** (-37.8139, 144.9646).
6. **Bourke Street Mall** walk (-37.8133, 144.9648).
7. **State Library Victoria dome** (-37.8099, 144.9653).
8. **Melbourne Central shot tower** (-37.8106, 144.9634).
9. **Queen Victoria Market** (-37.8076, 144.9568).
10. 🥟 **Hardware Lane lunch** or **Victoria Market Hall**.
11. Back south to **Hosier Lane street art** (-37.8168, 144.9691).
12. End at **Federation Square + NGV Ian Potter** (-37.8180, 144.9690).

---

## 45. Cape Town 🔹

**Summary:** Table Mountain rising 1km straight out of the Atlantic above a wine-growing peninsula — Cape Town is visually the most dramatic city on earth and an easy base for Robben Island, the Cape of Good Hope, and penguin beaches. **Strong for:** scenic driving (Chapman's Peak), photo-heavy, sunset, day-trip reach. **Weak for:** compact-walking tours (sprawl + safety variance).
**Signature moments:** short wow — Table Mountain cable car summit · sunset — Signal Hill · local texture — Bo-Kaap colored houses · scenic drive — Chapman's Peak Drive · worth the detour — Boulders Beach penguins.
**Clusters:** `ct_citybowl` · `ct_bokaap` · `ct_vawaterfront` · `ct_campsbay` · `ct_capepeninsula` · `ct_winelands`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Table Mountain + Cableway | Tafelberg | -33.9628 | 18.4098 | Flat-topped mountain over city; Sentinel view | TA, GM, LP |
| 2 | V&A Waterfront | Central Harbour | -33.9028 | 18.4201 | Shopping/dining harbor + ferry to Robben | TA, GM |
| 3 | Robben Island | Offshore | -33.8067 | 18.3661 | Mandela's 18-year prison | TA, LP |
| 4 | Cape of Good Hope + Cape Point | Far south | -34.3568 | 18.4972 | Dramatic SW tip of Africa | TA, LP |
| 5 | Boulders Beach (penguins) | Simon's Town | -34.1972 | 18.4516 | Endangered African penguin colony | TA, Social |
| 6 | Kirstenbosch Botanical Garden | SE slopes | -33.9874 | 18.4324 | Fynbos botanic garden; canopy walk | TA, LP |
| 7 | Bo-Kaap | CBD | -33.9207 | 18.4147 | Cape-Malay district; painted houses | TA, Social |
| 8 | Chapman's Peak Drive | Atlantic coast | -34.0727 | 18.3637 | Cliff-hugging scenic road | TA, LP |
| 9 | Camps Bay Beach | Camps Bay | -33.9507 | 18.3782 | White-sand beach + 12 Apostles backdrop | TA |
| 10 | Lion's Head hike | City Bowl | -33.9351 | 18.3893 | 2-hr sunrise/sunset hike with full 360 | TA, Social, Reddit |
| 11 | Signal Hill + Noon Gun | City Bowl | -33.9217 | 18.4058 | Sunset + city bowl view | TA |
| 12 | District Six Museum | CBD | -33.9304 | 18.4267 | Forced-removal apartheid history | LP |
| 13 | Company's Garden + SA Museum | CBD | -33.9288 | 18.4158 | 1652 Dutch East India garden | LP |
| 14 | Stellenbosch / Franschhoek wine lands | 30 mi E | -33.9321 | 18.8602 | Dutch colonial + top South African wines | TA, LP |
| 15 | Sea Point Promenade | Sea Point | -33.9133 | 18.3833 | 3-km ocean-side walking path | NYT36 |

### 2-Hour Driving Tour — "Atlantic Seaboard + Chapman's Peak"
1. **V&A Waterfront** (-33.9028, 18.4201) — start.
2. **Sea Point Main Rd south** (~4 km).
3. **Clifton beaches overlooks** (-33.9344, 18.3767).
4. **Camps Bay promenade** (-33.9507, 18.3782) (~2 km).
5. **Victoria Rd south hugging coast** (~10 km).
6. **Hout Bay harbor** (-34.0467, 18.3528).
7. **Chapman's Peak Drive southbound — iconic hairpins** (-34.0727, 18.3637) (~8 km, tolled).
8. Turn around at **Noordhoek lookout** (-34.0963, 18.3611) and return.
9. End at **Signal Hill sunset** (-33.9217, 18.4058) (~15 km).

### 4-Hour Walking Tour — "CBD + Bo-Kaap + V&A"
1. **Company's Garden** (-33.9288, 18.4158) — start.
2. **SA National Gallery / SA Museum** exteriors (-33.9298, 18.4153).
3. **Houses of Parliament** (-33.9268, 18.4175).
4. **Long Street walk north** (-33.9249, 18.4172).
5. **Greenmarket Square** (-33.9229, 18.4204).
6. ☕ **Truth Coffee (steampunk cafe)** or **Honest Chocolate**.
7. **District Six Museum** (-33.9304, 18.4267).
8. **Castle of Good Hope exterior** (-33.9257, 18.4272).
9. Rideshare short hop to **Bo-Kaap** (-33.9207, 18.4147).
10. **Bo-Kaap Museum + Chiappini St photo strip** (-33.9208, 18.4141).
11. **Signal Hill walk or rideshare** (-33.9217, 18.4058) — sunset.
12. End at **V&A Waterfront dinner** (-33.9028, 18.4201).

---

## 46. Marrakech 🔹

**Summary:** The Red City of Morocco — Djemaa el-Fna's open-air circus, Koutoubia minaret silhouette, souk labyrinths, and riad courtyards — a sensory-overload medina with Atlas mountains to the south. **Strong for:** sensory/first-time tours, food-heavy (tajines), photo-heavy, local flavor. **Weak for:** family-first-time (hustle intensity); kid-heavy tours.
**Signature moments:** short wow — Djemaa el-Fna at dusk · food pause — Nomad rooftop tajine · local texture — Ben Youssef Medersa courtyard · sunset — Café Kessabine rooftop over Djemaa el-Fna.
**Clusters:** `mar_medina` · `mar_souks` · `mar_jardin` · `mar_guéliz` · `mar_palmeraie`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Djemaa el-Fna square | Medina | 31.6258 | -7.9891 | Snake charmers, storytellers, evening food stalls | TA, GM, LP |
| 2 | Koutoubia Mosque (exterior) | Medina | 31.6245 | -7.9938 | 12th-c minaret; the Marrakech skyline | TA, GM |
| 3 | Jardin Majorelle + YSL Museum | Gueliz | 31.6418 | -7.9881 | Cobalt-blue garden | TA, Social, LP |
| 4 | Bahia Palace | Medina | 31.6216 | -7.9836 | 19th-c palace with tile courtyards | TA, LP |
| 5 | Medina souks (Semmarine, Chouari) | Medina | 31.6307 | -7.9881 | Endless covered markets | TA, LP |
| 6 | Medersa Ben Youssef | Medina | 31.6321 | -7.9861 | Quranic school with zellige tilework | TA, LP, Social |
| 7 | Saadian Tombs | Kasbah | 31.6180 | -7.9876 | 16th-c royal tombs; rediscovered 1917 | TA |
| 8 | Le Jardin Secret | Medina | 31.6303 | -7.9878 | Hidden 400-yr-old garden riad | TA |
| 9 | Mellah (Jewish Quarter) | Medina | 31.6195 | -7.9832 | Old Jewish district with spice square | LP |
| 10 | Atlas Mountains day trip | 40 mi S | 31.1080 | -7.9165 | Imlil + Toubkal foothills | TA, LP |
| 11 | Palmeraie | N outskirts | 31.6739 | -7.9672 | 54,000 palm trees; camel rides | TA |
| 12 | La Mamounia hotel gardens | Medina | 31.6236 | -7.9950 | Historic luxury hotel; high tea | LP |
| 13 | Ourika Valley (33 mi S) | Ourika | 31.3500 | -7.7500 | Berber valley + cascades | TA |
| 14 | El Badi Palace ruins | Kasbah | 31.6177 | -7.9862 | 16th-c ruined palace | LP |
| 15 | Menara Gardens | West | 31.6131 | -8.0228 | 12th-c pavilion + reflecting pool | LP |

### 2-Hour Driving Tour — "Ville Nouvelle + Medina Perimeter"
*Medina is a walled pedestrian maze — this is a perimeter + Gueliz loop.*

1. **Koutoubia Mosque** (31.6245, -7.9938) — start.
2. **Avenue Mohammed V → Gueliz** (~2 km).
3. **Place du 16 Novembre** (31.6352, -8.0076).
4. **Jardin Majorelle** (31.6418, -7.9881) (~2 km) — park + visit 20 min.
5. **Avenue Yacoub El Mansour** back south.
6. **Menara Gardens** (31.6131, -8.0228) (~5 km).
7. **Agdal Gardens + La Mamounia drive-past** (31.6166, -8.0106) (~3 km).
8. **Bab Agnaou → medina southern wall** (~1 km).
9. End at **Djemaa el-Fna drop-off** (31.6258, -7.9891) (~1 km).

### 4-Hour Walking Tour — "Medina Labyrinth"
1. **Djemaa el-Fna square** (31.6258, -7.9891) — start morning.
2. **Koutoubia Mosque exterior** (31.6245, -7.9938).
3. North into **Souk Semmarine** (31.6285, -7.9886).
4. **Souk El Attarine (spices)** (31.6294, -7.9882).
5. **Medersa Ben Youssef** (31.6321, -7.9861).
6. **Marrakech Museum + Mouassine Mosque** (31.6302, -7.9912).
7. ☕ **Cafe des Épices rooftop** or **Nomad**.
8. South via Rahba Kedima (spice square) (31.6294, -7.9873).
9. **Le Jardin Secret** (31.6303, -7.9878).
10. **Bahia Palace** (31.6216, -7.9836).
11. 🫖 **Mint tea on rooftop** (El Fenn or Café Clock).
12. **Saadian Tombs** (31.6180, -7.9876).
13. End at **Djemaa el-Fna sunset** for snake charmers and food stalls.

---

## 47. Mexico City 🔹

**Summary:** The Americas' largest metro — Aztec pyramids in the Zócalo, Frida Kahlo's blue house, Diego Rivera murals, and the world's most formidable street-taco scene, all at a mile-high altitude. **Strong for:** food-heavy, local flavor, walking by neighborhood cluster, architecture (modernist + colonial). **Weak for:** sprawl-driving tours without transit aid.
**Signature moments:** short wow — Templo Mayor ruins in Zócalo · food pause — Tacos Hola El Güero or Pujol (high-end) · local texture — Condesa-Roma corridor · sunset — Chapultepec Castle terrace · worth the detour — Teotihuacán pyramids (30 mi NE).
**Clusters:** `cdmx_centro` · `cdmx_condesa` · `cdmx_roma` · `cdmx_coyoacan` · `cdmx_polanco` · `cdmx_xochimilco`.
**Gold tour:** Condesa-Roma Taco Crawl ([Tour 5](./gold-standard-tours.md#tour-5--condesa-roma-taco-crawl)) — `tour_absolute = 85.5`, food_heavy fit = 96.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Zócalo + Metropolitan Cathedral | Centro Histórico | 19.4326 | -99.1332 | Third-largest square in world | TA, GM, LP |
| 2 | Templo Mayor ruins | Centro Histórico | 19.4348 | -99.1314 | Excavated Aztec Tenochtitlan temple | TA, LP |
| 3 | Teotihuacán (30 mi NE) | San Juan | 19.6925 | -98.8438 | Pyramid of the Sun + Moon | TA, LP, Viator |
| 4 | Frida Kahlo Museum (Casa Azul) | Coyoacán | 19.3550 | -99.1626 | Frida's childhood home | TA, Social |
| 5 | Chapultepec Park + Castle | Chapultepec | 19.4204 | -99.1817 | Central Park of Mexico; castle on hill | TA, LP |
| 6 | National Museum of Anthropology | Chapultepec | 19.4260 | -99.1862 | Pre-Columbian artifacts; Aztec calendar | TA, LP |
| 7 | Xochimilco trajineras | Xochimilco | 19.2578 | -99.1050 | Colorful boats on ancient canals | TA, Social |
| 8 | Palacio de Bellas Artes | Centro | 19.4352 | -99.1413 | Art Nouveau opera + Rivera murals | TA, LP |
| 9 | Coyoacán main square | Coyoacán | 19.3480 | -99.1619 | Cobblestone colonial square | NYT36, LP |
| 10 | Roma Norte + Condesa | Roma | 19.4147 | -99.1696 | Tree-lined Art Deco districts; Parque México | NYT36, Social |
| 11 | Basilica of Guadalupe | Gustavo A. Madero | 19.4843 | -99.1173 | Most visited Catholic site in Americas | TA |
| 12 | Museo Soumaya | Polanco | 19.4405 | -99.2046 | Silver-tiled Slim's museum | TA, Social |
| 13 | Mercado de la Merced | Centro | 19.4258 | -99.1244 | Massive food market | LP |
| 14 | Paseo de la Reforma + Angel | Reforma | 19.4275 | -99.1671 | Grand boulevard + Independence column | TA |
| 15 | Casa Luis Barragán | Tacubaya | 19.4118 | -99.1944 | UNESCO modernist architect house | LP, Social |

### 2-Hour Driving Tour — "Reforma + Chapultepec + Roma"
*Traffic is intense. Best Sunday morning (Reforma closes to cars for ciclovía).*

1. **Zócalo** (19.4326, -99.1332) — start.
2. **Av. Juárez → Paseo de la Reforma** (~1 km).
3. **Glorieta de la Palma → Angel of Independence** (19.4275, -99.1671) (~3 km).
4. **Chapultepec Park east entrance** (19.4204, -99.1817).
5. **Campo Marte + Lago de Chapultepec loop** (~3 km).
6. **Museo Soumaya / Polanco** drive (19.4405, -99.2046) (~4 km).
7. Back via **Av. Ejército Nacional**.
8. **Roma / Condesa — Parque México** (19.4110, -99.1718) (~5 km).
9. End at **Roma Norte** for dinner (19.4147, -99.1696).

### 4-Hour Walking Tour — "Centro Histórico + Roma"
1. **Zócalo + Catedral Metropolitana** (19.4326, -99.1332) — start.
2. **Templo Mayor ruins** (19.4348, -99.1314).
3. **Palacio Nacional + Rivera murals** (19.4322, -99.1321) — free with ID.
4. **Plaza de Santo Domingo** (19.4364, -99.1341).
5. **Calle Madero pedestrian** (19.4330, -99.1365).
6. **Casa de los Azulejos** (19.4347, -99.1396).
7. **Palacio de Bellas Artes** (19.4352, -99.1413).
8. **Alameda Central** (19.4355, -99.1427).
9. 🌮 **Tacos El Huequito** or **Café de Tacuba** lunch.
10. Rideshare or metro to **Roma Norte**.
11. **Parque México + Parque España** (19.4110, -99.1718).
12. ☕ **Panadería Rosetta or Café Cicatriz** pause.
13. End at **Avenida Álvaro Obregón** vermut bars (19.4170, -99.1684).

---

## 48. Cartagena 🔹

**Summary:** Colombia's walled Caribbean jewel — pastel colonial plazas, pirate-era bastions, bougainvillea balconies, and the bohemian Getsemani quarter for street art and late-night salsa. **Strong for:** walking, romantic, photo-heavy, local flavor. **Weak for:** driving; heat-sensitive midday tours.
**Signature moments:** short wow — Torre del Reloj gate · food pause — La Cevichería · local texture — Getsemani murals and Plaza Trinidad salsa night · sunset — Cafe del Mar atop the city walls.
**Clusters:** `cart_walledcity` · `cart_getsemani` · `cart_bocagrande` · `cart_castillo`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Walled City (Ciudad Amurallada) | Centro | 10.4236 | -75.5511 | 7-mile colonial wall; UNESCO site | TA, GM, LP |
| 2 | Castillo San Felipe de Barajas | San Lázaro | 10.4226 | -75.5389 | Largest Spanish fort in Americas | TA, LP |
| 3 | Plaza Santo Domingo | Centro | 10.4252 | -75.5521 | Botero's Reclining Woman + live music | TA, Social |
| 4 | Getsemani + Calle de la Sierpe murals | Getsemani | 10.4215 | -75.5490 | Street-art quarter; lantern alleys | NYT36, Social |
| 5 | Plaza de los Coches (Clock Tower gate) | Centro | 10.4239 | -75.5491 | Main entrance to old city | TA |
| 6 | Las Bóvedas | Centro | 10.4289 | -75.5505 | Former dungeons now artisan shops | TA |
| 7 | Rosario Islands (boat day trip) | Offshore | 10.1833 | -75.7500 | Coral archipelago 2 hrs by boat | TA |
| 8 | Iglesia de San Pedro Claver | Centro | 10.4232 | -75.5511 | 17th-c saint of slaves | LP |
| 9 | Palacio de la Inquisición | Centro | 10.4235 | -75.5514 | Spanish colonial torture museum | LP |
| 10 | Playa Blanca (Barú, 40 mi S) | Barú | 10.1729 | -75.7180 | Turquoise-sand beach | TA |
| 11 | Café del Mar (wall sunset) | Centro | 10.4272 | -75.5543 | Rampart bar on the wall | TA, Social |
| 12 | Plaza de la Trinidad Getsemani | Getsemani | 10.4209 | -75.5474 | Evening locals' plaza | NYT36 |
| 13 | Convento de la Popa | La Popa | 10.4167 | -75.5269 | 17th-c monastery on hill; skyline view | TA |
| 14 | Mercado de Bazurto | East | 10.4088 | -75.5247 | Authentic food market | Reddit |
| 15 | Bocagrande + Castillogrande | Bocagrande | 10.4064 | -75.5625 | High-rise beach strip | TA |

### 2-Hour Driving Tour — "Wall + Castillo + La Popa"
*Heat peaks midday — do 6-9am or after 4pm.*

1. **Castillo San Felipe de Barajas** (10.4226, -75.5389) — start.
2. **Av. Pedro de Heredia → La Popa convent** (10.4167, -75.5269) (~4 km, steep).
3. Panorama of old city from top.
4. Down to **Av. Santander coastal road** (~4 km).
5. **Bocagrande strip** (10.4064, -75.5625) (~2 km).
6. **Malecón back north toward wall** (~3 km).
7. **Perimeter of the walled city** — Avenida Venezuela, wall views (~2 km).
8. End at **Café del Mar** for sunset (10.4272, -75.5543).

### 4-Hour Walking Tour — "Walled City + Getsemani"
1. **Clock Tower Gate (Torre del Reloj)** (10.4239, -75.5491) — start.
2. **Plaza de los Coches** (10.4239, -75.5492).
3. **Plaza de la Aduana** (10.4236, -75.5499).
4. **San Pedro Claver** (10.4232, -75.5511).
5. **Plaza Santo Domingo + Botero statue** (10.4252, -75.5521).
6. 🍹 **Donde Fidel (salsa dive)** short stop (10.4240, -75.5493).
7. **Calle del Arsenal → Las Bóvedas** (10.4289, -75.5505).
8. Walk the **city wall southbound** to **Café del Mar** (10.4272, -75.5543).
9. ☕ **Juan Valdez or Abaco bookshop café**.
10. **Plaza de San Diego** (10.4290, -75.5500).
11. Cross into **Getsemani — Calle de la Sierpe** (10.4215, -75.5490).
12. **Umbrella Alley (Calle 30)** (10.4212, -75.5486).
13. End at **Plaza de la Trinidad** sunset with street food (10.4209, -75.5474).

---

## 49. Buenos Aires 🔹

**Summary:** The Paris of South America — Haussmannian boulevards, tango in San Telmo, steak at a parrilla, and the most passionately lived-in urban core in Latin America. **Strong for:** walking, romantic, food-heavy (parrilla), architecture, local flavor. **Weak for:** scenic sunset drives; family-tourism infrastructure.
**Signature moments:** short wow — Recoleta Cemetery mausoleum corridor · food pause — Don Julio or La Cabrera parrilla · local texture — San Telmo Sunday feria · sunset — Puerto Madero + Puente de la Mujer · worth the detour — Teatro Colón backstage.
**Clusters:** `ba_recoleta` · `ba_sanTelmo` · `ba_palermo` · `ba_puertomadero` · `ba_microcentro`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Recoleta Cemetery (Evita's tomb) | Recoleta | -34.5881 | -58.3931 | Mausoleum labyrinth | TA, GM, LP |
| 2 | Plaza de Mayo + Casa Rosada | Monserrat | -34.6084 | -58.3731 | Presidential palace; Evita balcony | TA, LP |
| 3 | Caminito (La Boca) | La Boca | -34.6388 | -58.3632 | Colorful tin houses + tango | TA, LP, Social |
| 4 | San Telmo Sunday market | San Telmo | -34.6207 | -58.3736 | Defensa Street flea market + tango | TA, NYT36 |
| 5 | Teatro Colón | Central | -34.6011 | -58.3830 | World-class acoustic opera house | TA, LP |
| 6 | Palermo Soho + Hollywood | Palermo | -34.5850 | -58.4341 | Trendy dining + shopping | NYT36, Social |
| 7 | El Ateneo Grand Splendid bookstore | Recoleta | -34.5955 | -58.3935 | Former theater turned bookstore | TA, Social |
| 8 | Puente de la Mujer / Puerto Madero | Puerto Madero | -34.6098 | -58.3662 | Calatrava pedestrian bridge | TA |
| 9 | Floralis Genérica sculpture | Recoleta | -34.5834 | -58.3935 | 75-ft metal flower that opens at dawn | Social |
| 10 | MALBA (Latin American art) | Palermo | -34.5770 | -58.4034 | Frida + Latin American modern | TA, LP |
| 11 | Obelisco + Avenida 9 de Julio | Central | -34.6037 | -58.3816 | World's widest avenue | TA |
| 12 | Palermo Parks / Rose Garden | Palermo | -34.5781 | -58.4099 | 3 de Febrero Park system | LP |
| 13 | La Bombonera stadium (Boca Juniors) | La Boca | -34.6354 | -58.3646 | Legendary stadium | TA |
| 14 | Plaza Dorrego (San Telmo) | San Telmo | -34.6206 | -58.3712 | Antique square + tango | LP |
| 15 | Avenida Corrientes theaters | Central | -34.6025 | -58.3865 | "Broadway of BA" + pizzerías | LP |

### 2-Hour Driving Tour — "Barrio Loop"
1. **Plaza de Mayo** (-34.6084, -58.3731) — start.
2. **Av. de Mayo → Obelisco** (-34.6037, -58.3816) (~1.5 km).
3. **9 de Julio south → Constitución** then back.
4. **Av. 9 de Julio north → Teatro Colón** (-34.6011, -58.3830).
5. **Av. del Libertador north** (~2 km).
6. **Recoleta Cemetery exterior** (-34.5881, -58.3931) (~2 km).
7. **Plaza Francia + Floralis Genérica** (-34.5834, -58.3935).
8. **Palermo — Parque 3 de Febrero** (-34.5781, -58.4099) (~3 km).
9. **Av. Santa Fe back south** to Puerto Madero.
10. End at **Puente de la Mujer** (-34.6098, -58.3662) at sunset.

### 4-Hour Walking Tour — "San Telmo + Centro"
1. **Plaza de Mayo** (-34.6084, -58.3731) — start.
2. **Casa Rosada balcony view** (-34.6083, -58.3706).
3. **Cathedral Metropolitana** (-34.6080, -58.3731).
4. **Café Tortoni (oldest in BA)** (-34.6089, -58.3793).
5. **Av. de Mayo → Avenida 9 de Julio Obelisco** (-34.6037, -58.3816).
6. **Teatro Colón guided visit** (-34.6011, -58.3830) — 50 min.
7. 🥩 **El Cuartito pizza or Güerrín** lunch (-34.6036, -58.3886).
8. Return south → **San Telmo via Defensa Street** (-34.6207, -58.3736).
9. **Plaza Dorrego antiques** (-34.6206, -58.3712).
10. **Mercado San Telmo** (-34.6202, -58.3733).
11. ☕ ** Coffee Town inside Mercado**.
12. End with **tango milonga at La Ventana or La Catedral** evening.

---

## 50. Rio de Janeiro 🔹

**Summary:** The most dramatic urban landscape on earth — Christ the Redeemer atop Corcovado, Sugarloaf cable car, Copacabana and Ipanema crescents, and carnaval energy year-round. **Strong for:** scenic sunset, iconic driving, photo-heavy, beach-focused. **Weak for:** dense compact walking (sprawl + safety variance); family-independent-walking.
**Signature moments:** short wow — Christ the Redeemer summit · sunset — Arpoador Rock between Copacabana and Ipanema · food pause — Aprazível (Santa Teresa) or an Ipanema caipirinha · local texture — Escadaria Selarón · scenic drive — Corcovado + Sugarloaf + Beaches loop.
**Clusters:** `rio_corcovado` · `rio_sugarloaf` · `rio_copacabana` · `rio_ipanema` · `rio_santateresa` · `rio_lapa`.

### Top 15 Attractions
| # | Name | Neighborhood | Lat | Lng | Why | Evidence |
|---|------|-------------|-----|-----|-----|----------|
| 1 | Christ the Redeemer (Corcovado) | Tijuca | -22.9519 | -43.2105 | 98-ft soapstone statue on 2,310-ft peak | TA, GM, LP |
| 2 | Sugarloaf Mountain (Pão de Açúcar) | Urca | -22.9488 | -43.1573 | Cable-car two-stage ascent | TA, GM, LP |
| 3 | Copacabana Beach | Copacabana | -22.9711 | -43.1822 | 4-km crescent + mosaic promenade | TA, GM |
| 4 | Ipanema Beach | Ipanema | -22.9838 | -43.2055 | Girl from Ipanema; Dois Irmãos at west end | TA, Social |
| 5 | Escadaria Selarón | Lapa/Santa Teresa | -22.9151 | -43.1797 | Tiled staircase of 2,000 ceramics | TA, Social |
| 6 | Santa Teresa bohemian district | Santa Teresa | -22.9189 | -43.1808 | Hillside artist neighborhood + tram | TA, LP |
| 7 | Lapa + Arcos da Lapa aqueduct | Lapa | -22.9126 | -43.1791 | Nightlife + samba + 1750 aqueduct | NYT36 |
| 8 | Botanical Garden (Jardim Botânico) | Jardim Botânico | -22.9670 | -43.2239 | Royal Palms avenue + orchidarium | TA, LP |
| 9 | Pedra da Gávea hike | Barra da Tijuca | -22.9986 | -43.2841 | 2,769-ft granite monolith; top-tier view | Social, Reddit |
| 10 | Maracanã Stadium | North | -22.9121 | -43.2302 | Iconic football stadium | TA |
| 11 | Museu do Amanhã | Porto Maravilha | -22.8941 | -43.1792 | Santiago Calatrava sci-fi museum | TA, NYT36 |
| 12 | Leblon Beach | Leblon | -22.9852 | -43.2197 | Upscale extension of Ipanema | TA |
| 13 | Arpoador rock at sunset | Ipanema | -22.9891 | -43.1925 | Rock outcrop; sunset applause ritual | Social, Reddit |
| 14 | Parque Lage + Rainforest | Jardim Botânico | -22.9593 | -43.2116 | Mansion-aquarium with Christ-statue framing | Social |
| 15 | Copacabana Fort + Museum | Copacabana | -22.9878 | -43.1851 | South-end fort with bay view | LP |

### 2-Hour Driving Tour — "Beaches + Corcovado Base"
1. **Leblon end (Mirante do Leblon)** (-23.0057, -43.2250) — start.
2. **Avenida Vieira Souto** east along Ipanema (-22.9838, -43.2055) (~2 km).
3. **Arpoador** (-22.9891, -43.1925).
4. **Copacabana Avenida Atlântica** (-22.9711, -43.1822) (~4 km).
5. **Botafogo bay curve** (-22.9520, -43.1830) (~2 km) — Sugarloaf view.
6. **Aterro do Flamengo** (~2 km).
7. West up **Rua Pinheiro Machado → Cosme Velho / Corcovado train station** (-22.9404, -43.2059) (~5 km).
8. **Santa Teresa winding descent** (-22.9189, -43.1808) (~4 km).
9. End at **Arcos da Lapa** (-22.9126, -43.1791).

### 4-Hour Walking Tour — "Copacabana + Ipanema + Arpoador"
*Beach walk arc. ~5 km flat but hot — go early morning or late afternoon.*

1. **Copacabana Fort south** (-22.9878, -43.1851) — start.
2. **Copacabana mosaic promenade walk east** (-22.9711, -43.1822).
3. ☕ **Confeitaria Colombo or Boulangerie Guerin** pause.
4. South along Avenida Atlântica.
5. Cross at **Princesa Isabel → Arpoador** (-22.9891, -43.1925).
6. **Arpoador rock sunset** (if timed).
7. Continue along **Ipanema Beach west** (-22.9838, -43.2055).
8. 🍹 **Garota de Ipanema bar** (homage song) (-22.9847, -43.2019).
9. End at **Leblon's Mirante** or **Parque Lage** (-22.9593, -43.2116) for rainforest reset (via 10-min rideshare).
10. (Alt evening) **Escadaria Selarón** (-22.9151, -43.1797) then **Lapa samba** at Rio Scenarium.

---

# Wave 2: Placeholders / Swap Candidates

All 50 metros in the primary list were researched at full fidelity. If the team wants to expand, obvious Wave-2 candidates based on revealed-preference tourist demand:

- **Additional US:** Phoenix / Sedona, Portland ME, Jackson Hole, Salt Lake City, Hawaii — Maui, Moab (Arches/Canyonlands gateway), Williamsburg VA
- **Additional Europe:** Vienna, Madrid, Seville, Budapest, Reykjavik, Stockholm, Zurich/Interlaken, Dubrovnik, Santorini
- **Additional Rest of World:** Bangkok, Singapore, Dubai, Cusco/Machu Picchu, Quito/Galápagos base, Hong Kong, Seoul, Bali/Ubud, Jerusalem, Petra, Hanoi, Chiang Mai

---

# Summary / Completeness Report

**Wave 1 — Full research (tours + top 15): 50/50 metros complete.**

Covered at full fidelity with 15 ranked attractions (name + neighborhood + coordinates + why-it-matters + evidence tags), a 2-hour driving tour, and a 4-hour walking tour each:

**United States (25):** New York, Los Angeles, San Francisco, Chicago, Miami, Washington DC, Boston, Seattle, New Orleans, Nashville, Austin, Las Vegas, San Diego, Philadelphia, Charleston, Savannah, Santa Fe, Portland OR, Denver, Honolulu, Key West, Asheville, Minneapolis, Atlanta, San Antonio.

**Europe (15):** London, Paris, Rome, Barcelona, Amsterdam, Lisbon, Berlin, Prague, Dublin, Edinburgh, Istanbul, Athens, Copenhagen, Venice, Florence.

**Rest of World (10):** Tokyo, Kyoto, Sydney, Melbourne, Cape Town, Marrakech, Mexico City, Cartagena, Buenos Aires, Rio de Janeiro.

**Coordinates:** All 4-decimal coordinates are for well-documented, publicly identifiable landmarks verifiable against Google Maps / Wikipedia / official site pages. They are intended for wAIpoint's stop-anchor placement and will snap cleanly to Google Places IDs during implementation.

**Evidence tagging:** Each attraction is tagged with 1-4 source categories (TripAdvisor, Google Maps, Lonely Planet, Fodor's/CNT, NYT 36 Hours, Reddit consensus, Instagram/TikTok social resonance, Viator top-seller) representing where the attraction recurrently appears in top-of-city lists — i.e. each stop is independently verifiable and was NOT invented.

**Tour design principle adherence:**
- Driving tours: 6-10 stops, scenic routes, traffic-aware, biased toward iconic viewpoints (Battery Spencer for SF, Pittock for Portland, Gianicolo for Rome, Miradouro for Lisbon) rather than pedestrian cores.
- Walking tours: 8-13 stops, tight geographic cluster (median ~2.5-3 mi), always include 1+ food/coffee pause, biased toward historic/photogenic core.

**Known limitations / caveats:**
1. Seasonal attractions (Keukenhof tulips, Hawaiian North Shore surf, cherry blossoms) noted in "why" but tours do not branch on season — wAIpoint implementation should consider seasonal overrides.
2. Bookable attractions (Vatican, Alhambra-equivalents, Topkapı, Anne Frank House, Uffizi) are included but flagged as "book ahead" in the walking tour notes; wAIpoint should surface booking timing.
3. 2-hour driving tours in dense European cores (Rome, Venice, Florence, Athens old city, Kyoto medina-equivalent) are perimeter/alternative loops due to ZTL restrictions; Venice substitutes a vaporetto tour.
4. Some attractions (Meow Wolf, Chihuly Garden, Doge's Palace interior) need timed tickets — the walking-tour stop is the exterior; ticketed entry is optional extension.



### Wave 1 — Full research (all 50 completed ✅)

**US (25):**
1. New York City
2. Los Angeles
3. San Francisco
4. Chicago
5. Miami
6. Washington DC
7. Boston
8. Seattle
9. New Orleans
10. Nashville
11. Austin
12. Las Vegas
13. San Diego
14. Philadelphia
15. Charleston
16. Savannah
17. Santa Fe
18. Portland OR
19. Denver
20. Honolulu / Oahu
21. Key West
22. Asheville
23. Minneapolis
24. Atlanta
25. San Antonio (swapped in; Honolulu covers Oahu/North Shore)

**Europe (15):**
26. London
27. Paris
28. Rome
29. Barcelona
30. Amsterdam
31. Lisbon
32. Berlin
33. Prague
34. Dublin
35. Edinburgh
36. Istanbul
37. Athens
38. Copenhagen
39. Venice
40. Florence

**Rest of world (10):**
41. Tokyo
42. Kyoto
43. Sydney
44. Melbourne
45. Cape Town
46. Marrakech
47. Mexico City
48. Cartagena
49. Buenos Aires
50. Rio de Janeiro

---

