# wAIpoint Tour Scoring Spec

**Purpose.** This is the machine-usable scoring framework for every wAIpoint tour — curated, user-generated, and AI-generated alike. It defines (a) how we score individual stops, (b) how we score whole tours, (c) how we blend absolute quality with user-intent fit, and (d) the persisted JSON schema that the backend and the generation engine both read and write.

**Design goals.**

1. **One model for all tours.** Curated "featured" tours and on-the-fly custom tours use the same schema and the same scoring functions. Curated tours are not a different kind of object — they are just very high-scoring ones. This keeps the quality bar portable.
2. **Explain, don't just rank.** Every score must decompose into dimensions the app can verbalize to users ("this version is less famous but has a better sunset finish"). Generation quality depends on this.
3. **Decouple "good" from "right for you."** A hidden-gems tour that skips the most famous landmark is not bad — it is on-intent. Absolute quality and intent fit are two separate layers, blended at the final-score step.
4. **Drive generation, not just display.** The scoring engine is used to generate N candidates, rerank them against intent, balance constraints, explain tradeoffs, and iteratively refine. It is the core of the generator, not a postscript.

---

## Table of contents

1. [Scoring architecture overview](#1-scoring-architecture-overview)
2. [Stop-level scoring](#2-stop-level-scoring)
3. [Tour-level scoring — Layer A (absolute quality)](#3-tour-level-scoring--layer-a-absolute-quality)
4. [Tour-level scoring — Layer B (intent fit)](#4-tour-level-scoring--layer-b-intent-fit)
5. [Final blend + product-mode overrides](#5-final-blend--product-mode-overrides)
6. [Persisted JSON schema](#6-persisted-json-schema)
7. [Calibration — gold-standard set and weight tuning](#7-calibration--gold-standard-set-and-weight-tuning)
8. [Scoring-to-generation feedback loop](#8-scoring-to-generation-feedback-loop)

---

## 1. Scoring architecture overview

Every tour gets three score objects persisted alongside the tour:

- `stop_scores[]` — one entry per stop, 0-10 on each dimension, plus a weighted composite.
- `tour_absolute` — Layer A, the seven dimensions of *absolute* tour quality with suggested starting weights and a composite 0-100 score.
- `tour_intent_fit` — Layer B, intent overlays (hidden gems, sunset, romantic, etc.). A tour has one or more intent tags; each tagged intent gets its own 0-100 fit score.

The **final displayed score** = `blend(tour_absolute, tour_intent_fit, product_mode)`, described in §5.

```
       ┌────────────────────────────────┐
 stops │ iconicity  scenic  story  ...  │ ──► stop composite
       └────────────────────────────────┘
                      │
                      ▼
       ┌────────────────────────────────┐
 tour  │ Layer A: 7 absolute dimensions │ ──► tour_absolute (0-100)
       │ Layer B: intent-fit overlays   │ ──► tour_intent_fit[intent] (0-100)
       └────────────────────────────────┘
                      │
                      ▼
                 final_score
             (product-mode blended)
```

**Score ranges.** All dimension scores are 0-10 (float). Composite tour scores are 0-100. Everything is float; round for display only.

**Never destructive.** Scores are computed from persisted attributes. Never mutate a stop or tour object when rescoring; write a new score record with a timestamp. See §6.

---

## 2. Stop-level scoring

Every stop in a tour is scored on ten dimensions. Each is 0-10 and is stored alongside the stop attributes (see featured-tours-research.md for stop-attribute schema).

| Dimension | Definition | Signal sources |
|---|---|---|
| `iconicity` | How recognizable / bucket-list this stop is worldwide. 10 = Eiffel Tower, Grand Canyon. 3 = nice neighborhood plaza. | TripAdvisor rank, LP inclusion, social hashtag volume, global-search volume |
| `scenic_payoff` | Visual "wow" delivered per visit. 10 = unobstructed Golden Gate from Battery Spencer. 3 = average city block. | Photo value, reviewer sentiment, structured scenic tags |
| `story_richness` | Density of narratable meaning — history, pop-culture, architecture, local lore — that an audio guide can turn into a 2-3 minute segment. | Wikipedia depth, editorial inclusion (NYT36, LP), anchor-event count |
| `dwell_efficiency` | "Wow per minute." How fast a visitor gets the payoff. 10 = pull up, see it, photo, go. 3 = requires 45-min commitment for payoff. | Inverse of dwell time, tourist flow data |
| `friction` | **Inverse** score: 10 = effortless, 0 = hard to reach, park, or access. Encodes access_friction + parking_friction + walking_burden. | Parking availability, road access, walking distance from dropoff |
| `route_fit` | How well this stop fits *this particular tour's* route — geographic and thematic. Context-dependent: recomputed per tour. | Cluster_id match, adjacency to prior/next stop, detour cost |
| `time_of_day_fit` | Match between the stop's `best_time_of_day` and when this tour visits it. Golden-hour stop at golden hour = 10; same stop at midday = 5. | `best_time_of_day` vs tour schedule |
| `family_fit` | Suitability for kids / mixed-age group. Encodes family_friendliness attribute adjusted for tour intent. | Family_friendliness attribute, stroller access, kid appeal |
| `accessibility` | Wheelchair/mobility accessibility. Independent of family_fit. | accessibility_notes, step counts, terrain |
| `wow_per_minute` | The *emotional* version of dwell_efficiency. Same idea but weights awe, surprise, and memorability, not just visual payoff. | Reviewer peak-emotion cues, photo-value × iconicity normalized by dwell |

**Stop composite.** A single 0-10 number for quick ranking, weighted by the tour's intent. Default (no intent) weights:

```
stop_composite =
  0.22 × iconicity
+ 0.18 × scenic_payoff
+ 0.12 × story_richness
+ 0.10 × wow_per_minute
+ 0.10 × route_fit
+ 0.08 × dwell_efficiency
+ 0.08 × time_of_day_fit
+ 0.06 × friction          (already inverted — higher = less friction)
+ 0.03 × family_fit
+ 0.03 × accessibility
```

Weights shift by intent. For `kid_friendly`, family_fit jumps to 0.15 and iconicity drops to 0.15. For `hidden_gems`, iconicity inverts so very-famous stops are slightly penalized. Full intent-weight table lives in §4.

**Context-dependence warning.** `route_fit`, `time_of_day_fit`, and sometimes `friction` are not absolute properties of the stop — they depend on this tour. Persist them per-tour-per-stop, not per-stop.

---

## 3. Tour-level scoring — Layer A (absolute quality)

Layer A measures *craft*: how good is this tour as a tour, independent of whether it matches any particular user's intent? A Layer A score near 90 should mean "this is the kind of tour a great local guide would run." A score under 60 means "this doesn't hold together."

Seven dimensions, with starting weights. All 0-10, composite 0-100.

| # | Dimension | Weight | What it measures | How it's computed |
|---|---|---|---|---|
| 1 | **Iconic value** | 20% | Average iconicity of stops, with a bonus for having at least one "ten" and a penalty for being all famous-but-shallow. | `mean(iconicity) + 0.5 × max_iconicity_bonus − redundancy_penalty` |
| 2 | **Geographic coherence** | 20% | Does the tour form a clean route, or zig-zag? Uses total distance, detour ratio, and cluster consistency. | `1 − (detour_ratio − 1)`, clamped 0-10; penalize backtracks heavily |
| 3 | **Time realism** | 15% | Does the tour actually fit its stated duration? Includes travel + dwell + buffer + reservation realities. | `min(1, target_duration / realistic_duration) × 10` |
| 4 | **Narrative flow** | 15% | Does the sequence build — setup, development, crescendo? Or is it random order of greatest hits? | Arc detection: opening-wow present, mid-variety, strong finish |
| 5 | **Scenic payoff** | 15% | Weighted sum of scenic_payoff across stops, weighted by dwell; penalizes "all photos indoors" tours unless intent calls for it. | `Σ(scenic_payoff × dwell_weight)` |
| 6 | **Variety balance** | 7.5% | Mix of stop_types (icon, viewpoint, neighborhood, museum, food, park, waterfront...). Too many of one type = low. | Shannon-entropy-style diversity score over stop_type |
| 7 | **Practical usability** | 7.5% | Aggregate friction: parking, walking, reservations, opening hours, weather sensitivity. | Weighted average of friction dimensions, inverted |

Total absolute score (0-100):

```
tour_absolute =
  20 × iconic_value
+ 20 × geographic_coherence
+ 15 × time_realism
+ 15 × narrative_flow
+ 15 × scenic_payoff
+ 7.5 × variety_balance
+ 7.5 × practical_usability
```

(Each dimension is 0-1 when multiplied by these weights; multiply by 100 when stored as 0-10 values. Equivalent either way — pick one convention and stay with it. We store each dimension 0-10 and the composite 0-100.)

### Extended tour-level dimensions (signal-only, not in weighted composite)

These dimensions roll up *into* the seven above, but are persisted separately for debugging and for the generator's candidate-reranking step. They do **not** double-count — they are decompositions of the seven.

| Dimension | Rolls into | Notes |
|---|---|---|
| `route_smoothness` | geographic_coherence | Turns, reroutes, awkward crossings |
| `total_friction` | practical_usability | Aggregate of per-stop friction |
| `pacing` | narrative_flow + time_realism | Time between wow moments; avoids front/back-loading |
| `coverage_quality` | iconic_value + variety_balance | How well it represents the city's "must-sees" given intent |
| `variety` | variety_balance | Same measure, exposed for UI |
| `ending_quality` | narrative_flow + scenic_payoff | Is the last stop a strong finish? |
| `emotional_arc` | narrative_flow | Detected setup-climax-resolution curve |
| `duration_realism` | time_realism | Same measure, exposed for UI |

---

## 4. Tour-level scoring — Layer B (intent fit)

Intent fit overlays Layer A. A tour may be tagged with one or more intents; each intent is scored 0-100 separately.

### Supported intents and their fit logic

| Intent | What the user asked for | How we score fit |
|---|---|---|
| `first_time_highlights` | "Show me the best of this city, first visit." | Rewards coverage of canonical top-10; penalizes obscure stops |
| `hidden_gems` | "Skip the tourist traps." | **Rewards lower iconicity** and local_authenticity; penalizes top-5 icons unless they're essential for route logic |
| `architecture` | "I love buildings." | Weights story_richness on architecture stops; bonuses for period coherence |
| `kid_friendly` | "With a 6-year-old." | Family_fit is 30%+; walking_burden > moderate is a hard penalty |
| `scenic_sunset` | "Golden-hour drive." | Time_of_day_fit is 30%+; ending_quality must align with sunset; scenic_payoff weighted up |
| `minimal_walking` | "Drive most of it." | Walking_burden is inverted into the score; stop count optimized for car access |
| `local_flavor` | "Where locals actually go." | Local_authenticity weights up; chain-franchise food stops are penalized |
| `food_heavy` | "Food tour." | Stop_type food + variety of cuisine; dwell_time budget reallocated toward food stops |
| `romantic` | "Date night." | Ambient quality, lighting, intimacy; day_night_suitability must match; avoids family-theme stops |
| `architecture_modern` / `architecture_historic` | Subtype | Period filter on architecture bonus |
| `photo_heavy` | "I want the shots." | Photo_value weighted up; time_of_day_fit weighted up; rewards golden-hour segments |
| `efficient_short` | "Under 2 hours." | Duration_realism and pacing get higher weight; coverage is reduced |

### Intent fit formula (generic shape)

For each intent, define a weighted sum over stop-level and tour-level dimensions:

```
intent_fit(intent) =
  Σ (w_dim × dim_score)   for that intent's weight table
```

Rules:

- **Don't punish off-intent fame.** A hidden-gems tour should not lose points for missing the Eiffel Tower. The hidden_gems intent explicitly inverts or zeroes the iconicity weight.
- **Don't double-punish.** If a tour matches no intent, use absolute-only mode (§5). Don't score it against every intent and average — that would punish everything.
- **Intent combinations.** A tour tagged `romantic + scenic_sunset` is scored against both; final intent_fit is the min or mean depending on product-mode. Min avoids "wins one, fails the other" cases.

### Example — kid_friendly intent-weight table

```
family_fit:           0.30
walking_burden_inv:   0.20
dwell_efficiency:     0.15
variety:              0.10
iconicity:            0.10
scenic_payoff:        0.08
accessibility:        0.04
friction_inv:         0.03
```

### Example — hidden_gems intent-weight table

```
local_authenticity:   0.28
iconicity_inverted:   0.20     (famous stops DECREASE score)
story_richness:       0.15
stop_type_diversity:  0.12
scenic_payoff:        0.10
narrative_flow:       0.08
practical_usability:  0.07
```

### Example — scenic_sunset intent-weight table

```
time_of_day_fit:      0.30     (golden-hour alignment)
scenic_payoff:        0.25
ending_quality:       0.15     (sunset finish required)
geographic_coherence: 0.10
photo_value:          0.10
wow_per_minute:       0.05
practical_usability:  0.05
```

---

## 5. Final blend + product-mode overrides

The final score shown to users (and used for reranking) depends on `product_mode`.

| Product mode | Blend formula | Use case |
|---|---|---|
| `pure_curation` | `tour_absolute` only | Editorial featured tours in the free catalog |
| `pure_custom` | `0.40 × tour_absolute + 0.60 × intent_fit` | User explicitly typed a request; intent dominates |
| `hybrid_default` | `0.60 × tour_absolute + 0.40 × intent_fit` | Default for "recommend me a tour" with some signal |
| `calibration` | `tour_absolute` only | Running the scorer against the 10 gold-standard benchmarks |

**Gatekeeping.** Even in `pure_custom`, a tour below `tour_absolute < 55` is hidden from the user; craft gates intent. No amount of "matches your request" salvages a tour that's geographically incoherent or time-unrealistic.

**Multi-intent tours.**

```
intent_fit_overall = mean_or_min(intent_fit[each tag])
                   = min() when intents are hard constraints
                                 (e.g. "kid_friendly" is a safety floor)
                   = mean() when intents are style preferences
```

Tag each intent `hard` or `soft` in the intent taxonomy. Hard intents use min; soft use mean.

---

## 6. Persisted JSON schema

All scores are persisted as structured JSON alongside the tour object. TypeScript-style interface below — straightforward to map to Codable, SQL, or Protobuf.

```ts
// Stop-attribute schema (lives on the stop itself, not the score record)
interface StopAttributes {
  id: string;
  name: string;
  city: string;
  lat: number;
  lng: number;
  stop_type: "icon" | "viewpoint" | "neighborhood" | "museum" | "food"
           | "park" | "scenic_drive" | "waterfront" | "other";
  iconicity_score: number;                 // 0-10 absolute
  scenic_payoff_score: number;             // 0-10 absolute
  story_significance_score: number;        // 0-10 absolute
  tourist_popularity_score: number;        // 0-10 absolute
  local_authenticity_score: number;        // 0-10 absolute
  dwell_time_minutes_estimate: number;
  access_friction: "low" | "medium" | "high";
  parking_friction: "low" | "medium" | "high" | "not_applicable";
  walking_burden: "none" | "light" | "moderate" | "heavy";
  family_friendliness: number;             // 0-10
  weather_sensitivity: "none" | "moderate" | "high";
  best_time_of_day: "morning" | "midday" | "afternoon"
                  | "golden_hour" | "night" | "any";
  day_night_suitability: "day_only" | "both" | "night_only";
  reservation_risk: "none" | "low" | "high";
  crowding_risk: "low" | "medium" | "high";
  accessibility_notes: string;
  photo_value: number;                     // 0-10
  wow_per_minute: number;                  // 0-10
  cluster_id: string;
  adjacent_compatible_stops: string[];     // ids
}

// Per-stop, per-tour dynamic scores
interface StopScore {
  stop_id: string;
  tour_id: string;
  // Absolute (copied from StopAttributes; denormalized for fast read)
  iconicity: number;
  scenic_payoff: number;
  story_richness: number;
  // Context-dependent
  dwell_efficiency: number;
  friction: number;                        // inverted: 10 = effortless
  route_fit: number;                       // this tour's geography
  time_of_day_fit: number;                 // this tour's schedule
  family_fit: number;
  accessibility: number;
  wow_per_minute: number;
  // Composite
  stop_composite: number;                  // 0-10
  computed_at: string;                     // ISO8601
}

// Layer A — absolute tour quality
interface TourAbsoluteScore {
  tour_id: string;
  iconic_value: number;                    // 0-10
  geographic_coherence: number;            // 0-10
  time_realism: number;                    // 0-10
  narrative_flow: number;                  // 0-10
  scenic_payoff: number;                   // 0-10
  variety_balance: number;                 // 0-10
  practical_usability: number;             // 0-10
  composite: number;                       // 0-100
  weights_version: string;                 // track which weight set produced this
  computed_at: string;
  // Signal-only
  route_smoothness: number;
  total_friction: number;
  pacing: number;
  coverage_quality: number;
  ending_quality: number;
  emotional_arc: number;
  duration_realism: number;
}

// Layer B — intent fit
type IntentTag =
  | "first_time_highlights" | "hidden_gems" | "architecture"
  | "kid_friendly" | "scenic_sunset" | "minimal_walking"
  | "local_flavor" | "food_heavy" | "romantic"
  | "architecture_modern" | "architecture_historic"
  | "photo_heavy" | "efficient_short";

interface IntentFitScore {
  tour_id: string;
  intent: IntentTag;
  is_hard: boolean;                        // hard intents use min() in blend
  composite: number;                       // 0-100
  subscores: Record<string, number>;       // keyed by dimension name
  computed_at: string;
}

// Final blended score
interface TourFinalScore {
  tour_id: string;
  product_mode: "pure_curation" | "pure_custom"
              | "hybrid_default" | "calibration";
  intent_tags: IntentTag[];
  tour_absolute_ref: string;               // points to TourAbsoluteScore
  intent_fit_refs: string[];               // points to IntentFitScore
  intent_fit_rollup: number;               // 0-100 (min or mean per §5)
  final_score: number;                     // 0-100
  gate_passed: boolean;                    // false if absolute < 55
  explanations: TourExplanation[];
  computed_at: string;
  weights_version: string;
}

// Human-readable explanations the UI can surface
interface TourExplanation {
  kind: "strength" | "tradeoff" | "suggestion" | "warning";
  dimension: string;
  text: string;
  // e.g. { kind: "tradeoff", dimension: "iconic_value",
  //        text: "Skips the Vatican but gives you a Trastevere sunset" }
}
```

**Storage tips for the backend engineer.**

- `StopAttributes` lives in a `stops` table, one row per city-stop. Mostly static; curator-editable.
- `StopScore` is per-tour and gets recomputed whenever the tour is recomputed. Keep a history by `computed_at` for weight-tuning debugging; latest row wins.
- `TourAbsoluteScore` and `IntentFitScore` are likewise historied. `weights_version` lets us retune without losing comparability.
- `TourFinalScore` is the read-model. Index on `(city, product_mode, final_score DESC)` for feed queries.

---

## 7. Calibration — gold-standard set and weight tuning

The 10 gold-standard tours in [gold-standard-tours.md](./gold-standard-tours.md) are the **calibration set** for this scoring spec. They are tuned, hand-picked exemplars. The weights above are starting weights — they are explicitly expected to be tuned against this set.

### Calibration targets

| Check | Target |
|---|---|
| All 10 gold tours score `tour_absolute ≥ 85` | Required |
| At least 7 of 10 score `tour_absolute ≥ 90` | Strong target |
| No gold tour scores below its primary intent_fit `90` | Required |
| Random AI-generated tours score, on average, `tour_absolute 55-75` | Healthy spread |
| Deliberately bad tours (zigzag route, all-indoor, time-impossible) score below 45 | Required |

### Weight-tuning loop

1. Score all 10 gold tours and store `tour_absolute` + per-intent `intent_fit`.
2. Score N=100 AI-generated candidate tours against varied intents; score N=10 deliberately bad tours.
3. If gold tours do not meet targets:
   - Raise weights on whichever Layer A dimension the gold tour is *winning* on but is being under-counted (often `narrative_flow` or `scenic_payoff`).
   - Lower weights on dimensions where bad tours score surprisingly well (often `iconic_value` — fame can mask poor routing).
4. Re-score, re-check. Bump `weights_version`, keep old scores for comparison.
5. Repeat until the target table passes.

Do this once at launch and then monthly as new tours accumulate.

### What gold tours lock in

A gold tour is a contract:

- This stop sequence, in this city, at this duration, for this intent, is the quality bar.
- An AI-generated tour for the same intent in the same city that scores near or above the gold tour is shippable.
- An AI-generated tour that scores 15+ points below the gold tour for the same intent gets iteratively refined (see §8) before shipping to the user.

---

## 8. Scoring-to-generation feedback loop

The scoring engine is not a grader — it is the heart of the generator. Here's how generation actually uses it.

### 8.1 Candidate generation

For a given user request, generate `N` candidate tours (typical N = 5-20). Candidates differ on:

- Stop set (drop/add one or two stops)
- Stop sequence
- Time of visit per stop
- Optional detour segments
- Duration budget allocation

### 8.2 Reranking by intent fit

Score each candidate on Layer A *and* against the user's inferred intent tags. Rerank by `final_score` per §5.

```
candidates.sort_by(c => c.final_score).reverse()
top_candidate = candidates.first_that(c => c.gate_passed)
```

### 8.3 Constraint-balanced selection

Sometimes we want the tour that maximizes one thing subject to a floor on another. Examples:

- "Minimize friction subject to iconic_value ≥ 7." (mobility-constrained tourist)
- "Maximize scenic_payoff subject to duration_realism ≥ 8." (tight schedule, wants the views)
- "Maximize hidden_gems intent_fit subject to narrative_flow ≥ 7." (skip the famous stuff but keep the tour coherent)

This is just filter-then-rank over the candidate set.

### 8.4 Tradeoff explanation

Every shown tour carries an `explanations[]` array. The UI surfaces up to three. Examples the system must be able to produce:

- **Strength**: "This ends at Battery Spencer for golden hour — the best sunset stop in SF."
- **Tradeoff**: "This route is more iconic but has more traffic. The alternative trades the Bean for a less crowded riverwalk."
- **Tradeoff**: "This version is less famous but better matches your request for hidden gems."
- **Suggestion**: "Swap Pier 39 for Fort Mason and your scenic_payoff goes up 0.8."
- **Warning**: "Vizcaya closes at 4:30pm — consider starting an hour earlier."
- **Tradeoff**: "This route gives up the Vatican to create a much stronger Trastevere sunset finish."

These are generated from the score breakdown — the dimension that changed the most between the selected candidate and the nearest alternative is the explanation.

### 8.5 Iterative refinement

When the top candidate is acceptable but not great (say, `final_score` in 65-75), automatically run one refinement pass:

- Identify the lowest-scoring dimension.
- Propose local edits: swap one stop, reorder, shift time.
- Re-score. Keep if it moves up; revert if not.

Show the user two versions (V1 and V2) when refinement made a meaningful delta (> 5 points). Let the user pick. Log which one they pick — this is training data.

### 8.6 Feedback loop from real users

Persist per-tour: completion rate, skip-per-stop rate, favorite rate, session duration, time spent vs. planned.

- Completion rate lower than benchmark → reweight `time_realism` up.
- High skip rate on a specific stop type → reduce the weight of that stop_type's variety bonus.
- Strong favorite rate on sunset-finishing tours → raise `ending_quality` weight.

Update `weights_version` quarterly. Keep old scores intact for A/B comparison.

---

## 9. Open questions / things to wire later

- **Real-time signals.** Weather, traffic, closures — these should modify stop scores at *request time*, not at tour-creation time. Add a `real_time_score` field when we wire it in.
- **Personalization.** Per-user taste embedding (learned from favorites) that biases intent-fit weights. Not in v1.
- **Social proof.** "Users like you rated this 4.8" — a social score that blends with the algorithmic score. Not in v1.
- **Route realism beyond distance.** Current `geographic_coherence` is distance-based. V2 should use real routing-API ETAs with traffic.
- **Audio-length fit.** Each stop needs 2-3 min of narratable audio. `story_richness` is a proxy; a direct "audio_length_feasibility" score is better.

---

**Version:** v1 · starting weights · calibration pending.
**Depends on:** [featured-tours-research.md](./featured-tours-research.md) (stop-attribute source), [gold-standard-tours.md](./gold-standard-tours.md) (calibration set).
