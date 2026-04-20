# wAIpoint 3.0 — Blueprint

**Theme.** "Scoring-driven tour engine." Every tour — curated, user-shared, or AI-generated — runs through the same scoring framework. Featured tours are just the exemplars that the engine emits at the top of the distribution.

**Source of truth.** The strategy already exists:

- `docs/tour-scoring-spec.md` — Layer A (7 absolute dimensions) + Layer B (intent fit), TypeScript interfaces, calibration rules.
- `docs/gold-standard-tours.md` — 10 designed benchmark tours with full score breakdowns (5 US: LA, SF, Chicago, NYC, DC, plus Miami already built).
- `docs/featured-tours-research.md` — top-50 metro stop attributes + signature moments.

This blueprint operationalizes those specs; it does NOT re-design them.

---

## Phase A — Scoring engine runtime (backend)

**Goal.** Make every tour scoreable, cache scores in the DB, expose them on the API, and let the generator use scores to rerank candidates.

**New backend modules:**

| Module | Responsibility |
|---|---|
| `services/scoring/stop-scorer.ts` | Scores a single stop on the 10 dimensions from §2 of the spec. Hybrid: rule-based for `friction`, `route_fit`, `time_of_day_fit`, `accessibility`; Gemini-based for `iconicity`, `story_richness`, `scenic_payoff` with prompt-cached per-stop caching. |
| `services/scoring/tour-absolute.ts` | Computes Layer A's 7 dimensions: iconic_value, geographic_coherence, time_realism, narrative_flow, scenic_payoff, variety_balance, practical_usability. |
| `services/scoring/intent-fit.ts` | Scores Layer B for declared intents (hidden_gems, sunset, family, architecture, etc.). |
| `services/scoring/blend.ts` | Final blend per product_mode (curation / custom / hybrid). |
| `services/scoring/explainer.ts` | Takes a score breakdown and emits a user-facing explanation ("route is more iconic but has more traffic"). |
| `migrations/008_tour_scores.sql` | Three tables: `stop_scores`, `tour_absolute_scores`, `tour_intent_fit_scores` — append-only with `scored_at` timestamp. |
| `routes/scoring.ts` | `GET /v1/tours/:id/score` — returns the latest score bundle. |

**Generator integration:**
- `generateTour()` produces N=3 candidate tours (parallel Gemini calls at temperature 0.8 with different seed themes).
- Each candidate runs through the scorer.
- Rerank by `blend(absolute, intent_fit)` for the user's stated intent.
- Return best; persist all 3 score records for analytics.
- Explainer attaches `score_breakdown` + one-sentence rationale to the API response.

**Calibration gate:**
- Miami's existing 2 tours must score ≥85 absolute — they're the calibration baseline.
- Weight tuning script: `scripts/calibrate-scoring.ts` runs against Miami + the 9 new featured tours once they're built, iterates weights until targets hit. Results committed as `scoring-weights.json`.

**Tests:**
- Unit tests per module (pure math for blend, geographic coherence).
- Integration test: score Miami driving tour, assert ≥85 absolute on all 7 Layer A dimensions combined.
- Regression: un-scored "weak" tour (fabricated) must score <60.

---

## Phase B — 9 US gold-standard featured tours

**Cities (final):** Los Angeles, San Francisco, Chicago, New York City, Washington DC, Boston, Seattle, New Orleans, Austin.

**Rationale for the 9.** Covers the top 10 US tourism metros from the research doc (minus Miami which is done, minus Vegas which lags on "drive to sunset" / story-richness). Mix of archetypes:
- Driving: LA (Mulholland sunset), SF (Bay loop), Seattle (Pike-Waterfront), New Orleans (River Road), Austin (Hill Country)
- Walking: NYC (Midtown-Village), Chicago (river architecture), DC (Mall), Boston (Freedom Trail)

**Per city, 2 tours** (1 driving + 1 walking, same as Miami), using each city's entry in `featured-tours-research.md` as the stop graph + signature moments.

**Generation pipeline per tour:**
1. Seed from research doc tour outline → `generateFeaturedTourContent()` (existing).
2. Score via new engine.
3. If absolute < 85: regenerate with targeted feedback ("your route_smoothness was 6 because stops 3 and 4 are out of geographic sequence — reorder").
4. Max 3 iteration attempts. If still <85, flag for human review + skip (no silent failures).
5. Score ≥85 → synthesize audio (Google TTS Journey-D) → persist → mark `is_featured = 1`.

**Cost estimate.** 9 cities × 2 tours × ~$0.77 Miami baseline = ~$14 one-time (Gemini + TTS + Places photos). Plus scoring iterations: estimate 1.3× average multiplier = ~$18 total.

**Seed flow:** re-use `backend/scripts/seed-featured-tours.ts` pattern, extended with scoring gate + per-city batches.

---

## Phase C — Custom tour generation using the scoring engine

**What changes for users:** custom-generated tours now come back with a visible "quality score" + short explanation. Internally, the generator picks the best of N candidates instead of shipping the first one.

**Client-facing:**
- `TourPreview` and `Tour` responses include `score_breakdown` (7 Layer A dimensions + composite + intent fit + one-sentence explanation).
- New component on iOS `PreviewCard` and `TourDetailView`: a compact score chip ("87 · Scenic ★★★★☆") that expands into the full breakdown.
- Gemini-authored explanation surface: "Most iconic stops kept · one landmark swapped for a better sunset finish."
- A / B offering: user sees 2 candidates side-by-side when their intent is clear (hidden_gems, sunset, family); picks one; the other is logged for reranking feedback.

**Generation internals:**
- `generatePreview()` → emits 3 candidates → scores each → blends against request intent → returns top. Other 2 live in `candidate_tours` table for analytics.
- Intent parsing from themes + custom_prompt: hidden-gems, scenic, family, food, architecture, history, nightlife. Parser lives in `services/scoring/intent-parser.ts`.
- Feedback loop: if the user completes the tour, dismisses it, or rates it, write a `tour_feedback` row; a nightly weight-tuning job adjusts intent-fit weights based on completion rates.

---

## Execution order

| Step | What | Deps | Parallelizable |
|---|---|---|---|
| A1 | Scoring-engine migration + types | — | — |
| A2 | Rule-based scorers (friction, route_fit, time_realism, geographic_coherence) | A1 | ✓ with A3 |
| A3 | Gemini-based scorers (iconicity, story_richness, scenic_payoff, narrative_flow) | A1 | ✓ with A2 |
| A4 | Blend + explainer + API route | A2 + A3 | — |
| A5 | Unit + integration tests + Miami calibration | A4 | — |
| B1 | Seed script extensions: scoring gate + iteration loop | A5 | — |
| B2 | Generate + score + seed 9 cities × 2 tours | B1 | ✓ parallel per city (worktrees) |
| B3 | Weight calibration: tune against Miami + 9 new | B2 | — |
| C1 | Intent parser | A5 | — |
| C2 | Candidate generation + reranker in `generatePreview` | C1 + A4 | — |
| C3 | `score_breakdown` in API + iOS Tour model | C2 | — |
| C4 | iOS score chip + A/B picker UI | C3 | — |
| D1 | End-to-end QA + on-device test | all | — |
| D2 | TestFlight + ASC submission (3.0) | D1 | — |

---

## Decisions I've already made (to avoid bikeshedding)

1. **Version:** 3.0. This is a major engine change plus new content, not a polish release.
2. **Cities (9):** LA, SF, Chicago, NYC, DC, Boston, Seattle, New Orleans, Austin. No Nashville (Austin covers South), no Vegas (lower narrative density).
3. **2 tours per city** (driving + walking), matching Miami's structure → 18 new tours + 2 existing Miami = 20 featured.
4. **Score gate: ≥85 absolute** on Layer A composite for featured tours. Regenerate up to 3 times with targeted feedback, then flag for manual review if still below.
5. **Iteration budget:** ~$20 total GCP spend. If any tour hits 3 retries, stop and surface for human review (don't spiral cost).
6. **Candidate count:** N=3 for custom tours. More than that costs multiplicatively on Gemini.
7. **iOS score UI:** compact chip by default, tap-to-expand for the full breakdown. Don't flood the user.
8. **Featured tour scoring loop** runs once per city then freezes; annual refresh is a separate job.

---

## Two things I want confirmation on before I start coding

1. **Is 3.0 the right marketing version?** Alternative: 2.17 (incremental) — which downplays the user-visible surface of the scoring UI. I'm proposing 3.0 because "AI tours that explain why they're good" is a category-level positioning shift.

2. **Should the A/B candidate picker ship on day 1?** It's the most interesting UX outgrowth of the scoring engine, but it doubles the generation cost per request (user sees 2 tours, we discard 1). Three options:
   - (a) Ship A/B on day 1 — demonstrates the engine, max user delight, 2× cost per generation.
   - (b) Ship single-best on day 1, add A/B in 3.1 — safer, watches cost, can tune blending weights against real user selections before exposing the 2-candidate UI.
   - (c) Ship A/B as a subscriber-only feature — free users get best-of-3, paid users get to pick from 2 candidates. Interesting monetization hook.

My lean: **(b) single-best on day 1**. Score chip + explanation still ship; A/B is the sequel. Want me to proceed on that assumption, or pick (a) or (c)?

Once you answer those two, I'll flip to Phase A1 and start coding.
