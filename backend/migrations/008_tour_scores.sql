-- 008_tour_scores: append-only persistence for the v2.17 scoring engine.
--
-- Three tables mirror the three levels in tour-scoring-spec.md:
--   1. stop_scores          — per-stop 10-dimension scores (computed per-tour
--                              since `route_fit` and `time_of_day_fit` depend
--                              on tour context).
--   2. tour_absolute_scores — Layer A: 7 absolute-quality dimensions + composite.
--   3. tour_intent_fit_scores — Layer B: one row per (tour, intent) pair.
--
-- All rows are append-only with a `scored_at` timestamp. When a tour is
-- re-scored (e.g. weight tuning, regeneration, A/B candidate selection),
-- we write new rows and leave prior rows intact for analytics + rollback.
-- Callers should always read `ORDER BY scored_at DESC LIMIT 1` for latest.

CREATE TABLE IF NOT EXISTS stop_scores (
  id TEXT PRIMARY KEY,
  tour_id TEXT NOT NULL,
  stop_id TEXT NOT NULL,
  sequence_order INTEGER NOT NULL,

  -- 10 dimensions from tour-scoring-spec.md §2, each 0-10 (REAL).
  iconicity REAL NOT NULL,
  scenic_payoff REAL NOT NULL,
  story_richness REAL NOT NULL,
  dwell_efficiency REAL NOT NULL,
  friction REAL NOT NULL,
  route_fit REAL NOT NULL,
  time_of_day_fit REAL NOT NULL,
  family_fit REAL NOT NULL,
  accessibility REAL NOT NULL,
  wow_per_minute REAL NOT NULL,

  -- Weighted composite (0-10) for quick ranking.
  composite REAL NOT NULL,

  -- Free-form JSON: per-dimension scorer notes ("iconicity=9 because
  -- TripAdvisor top-10 + LP + Wikipedia 12k words"). Used by the
  -- explainer to verbalize scores.
  rationale_json TEXT,

  scored_at TEXT NOT NULL DEFAULT (datetime('now')),

  FOREIGN KEY (tour_id) REFERENCES tours(id) ON DELETE CASCADE,
  FOREIGN KEY (stop_id) REFERENCES tour_stops(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_stop_scores_tour_latest
  ON stop_scores(tour_id, scored_at DESC);

CREATE TABLE IF NOT EXISTS tour_absolute_scores (
  id TEXT PRIMARY KEY,
  tour_id TEXT NOT NULL,

  -- Layer A dimensions from §3, each 0-10.
  iconic_value REAL NOT NULL,
  geographic_coherence REAL NOT NULL,
  time_realism REAL NOT NULL,
  narrative_flow REAL NOT NULL,
  scenic_payoff REAL NOT NULL,
  variety_balance REAL NOT NULL,
  practical_usability REAL NOT NULL,

  -- Composite 0-100. Weighted per spec (20/20/15/15/15/7.5/7.5).
  composite REAL NOT NULL,

  -- The weights actually used for this score (weight-tuning writes
  -- new rows with updated weights). JSON of {iconic_value: 0.2, ...}.
  weights_json TEXT NOT NULL,
  rationale_json TEXT,

  scored_at TEXT NOT NULL DEFAULT (datetime('now')),

  FOREIGN KEY (tour_id) REFERENCES tours(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tour_absolute_scores_tour_latest
  ON tour_absolute_scores(tour_id, scored_at DESC);

-- Featured-tour gate: a tour ships to is_featured=1 only when its latest
-- absolute composite is ≥ 85. Queryable index for calibration dashboards.
CREATE INDEX IF NOT EXISTS idx_tour_absolute_scores_featured_gate
  ON tour_absolute_scores(composite)
  WHERE composite >= 85;

CREATE TABLE IF NOT EXISTS tour_intent_fit_scores (
  id TEXT PRIMARY KEY,
  tour_id TEXT NOT NULL,

  -- Intent tag (e.g. 'hidden_gems', 'sunset', 'family', 'architecture').
  -- Free-form so product can add new intents without a migration.
  intent TEXT NOT NULL,

  -- 0-100 fit score — how well this tour matches the named intent.
  fit_score REAL NOT NULL,

  -- Which Layer A dimensions contributed most to this intent fit.
  -- Used by the explainer to verbalize ("scored high on hidden_gems
  -- because route avoided the 3 most-iconic stops and emphasized
  -- local_authenticity").
  contributing_dimensions_json TEXT,
  rationale_json TEXT,

  scored_at TEXT NOT NULL DEFAULT (datetime('now')),

  FOREIGN KEY (tour_id) REFERENCES tours(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tour_intent_fit_scores_tour_intent
  ON tour_intent_fit_scores(tour_id, intent, scored_at DESC);

-- Weight tuning ledger — each row is one calibration run against the
-- gold-standard set. Lets us roll back if a weight change regresses
-- benchmark scores below their targets (all 10 gold tours must score ≥85
-- absolute; hidden-gems Shimokita must score ≥95 intent_fit).
CREATE TABLE IF NOT EXISTS scoring_weight_history (
  id TEXT PRIMARY KEY,
  weights_json TEXT NOT NULL,
  calibration_summary_json TEXT NOT NULL,   -- {gold_tour_id: composite_score, ...}
  mean_gold_composite REAL NOT NULL,
  min_gold_composite REAL NOT NULL,
  applied_at TEXT NOT NULL DEFAULT (datetime('now')),
  applied_by TEXT  -- actor: 'calibration-script' | 'manual-tune' | etc.
);

CREATE INDEX IF NOT EXISTS idx_scoring_weight_history_applied_at
  ON scoring_weight_history(applied_at DESC);
