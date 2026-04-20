// Shared TypeScript interfaces for the v2.17 tour scoring engine.
//
// Mirrors tour-scoring-spec.md §6. Every scorer produces one of these;
// every persistence layer reads/writes these. Adding a new dimension means
// updating BOTH the interface here AND the migration — the compile error
// will remind you.

// ── Stop level ───────────────────────────────────────────────────────────────

/**
 * Ten 0-10 dimensions per tour-scoring-spec.md §2. Persisted alongside each
 * stop's score record in `stop_scores`.
 */
export interface StopScore {
  stop_id: string;
  sequence_order: number;

  iconicity: number;
  scenic_payoff: number;
  story_richness: number;
  dwell_efficiency: number;
  friction: number;
  route_fit: number;
  time_of_day_fit: number;
  family_fit: number;
  accessibility: number;
  wow_per_minute: number;

  /** Weighted composite 0-10. See computeStopComposite(). */
  composite: number;

  /** Per-dimension explanatory notes for the explainer layer. */
  rationale?: Record<string, string>;
}

// ── Layer A: absolute tour quality ───────────────────────────────────────────

/**
 * Seven Layer A dimensions from §3. Composite is 0-100 and is the
 * "how good is this tour on its own terms" number that gates featured.
 */
export interface TourAbsoluteScore {
  iconic_value: number;           // 0-10
  geographic_coherence: number;   // 0-10
  time_realism: number;           // 0-10
  narrative_flow: number;         // 0-10
  scenic_payoff: number;          // 0-10
  variety_balance: number;        // 0-10
  practical_usability: number;    // 0-10

  /** 0-100 — weighted composite used by product to rank and gate. */
  composite: number;

  weights: TourAbsoluteWeights;
  rationale?: Record<string, string>;
}

export interface TourAbsoluteWeights {
  iconic_value: number;
  geographic_coherence: number;
  time_realism: number;
  narrative_flow: number;
  scenic_payoff: number;
  variety_balance: number;
  practical_usability: number;
}

/** Defaults per tour-scoring-spec.md §3. Sum = 1.0. */
export const DEFAULT_ABSOLUTE_WEIGHTS: TourAbsoluteWeights = {
  iconic_value: 0.20,
  geographic_coherence: 0.20,
  time_realism: 0.15,
  narrative_flow: 0.15,
  scenic_payoff: 0.15,
  variety_balance: 0.075,
  practical_usability: 0.075,
};

// ── Layer B: intent fit ──────────────────────────────────────────────────────

/**
 * The intent vocabulary. Free-form strings persist, but everything the
 * shipping product handles today is in this union so the compiler catches
 * typos in prompt parsers and explainer lookups.
 */
export type TourIntent =
  | 'first_time_highlights'
  | 'hidden_gems'
  | 'sunset'
  | 'romantic'
  | 'family_kids'
  | 'architecture'
  | 'food'
  | 'local_authenticity'
  | 'scenic_drive'
  | 'minimal_walking'
  | 'history'
  | 'nightlife'
  | 'quick_two_hours'
  | string;  // escape hatch for novel intents

export interface TourIntentFitScore {
  intent: TourIntent;

  /** 0-100 — how well this tour matches the named intent. */
  fit_score: number;

  /**
   * Which Layer A dimensions (or stop attributes) drove this intent fit.
   * Consumed by the explainer: "scored 94 on hidden_gems because the route
   * avoided the 3 most-iconic stops and emphasized local_authenticity."
   */
  contributing_dimensions?: Array<{
    dimension: string;
    weight: number;
    effect: 'positive' | 'negative' | 'neutral';
  }>;

  rationale?: Record<string, string>;
}

// ── Final blend ──────────────────────────────────────────────────────────────

export type ProductMode = 'pure_curation' | 'pure_custom' | 'hybrid_default' | 'calibration';

/**
 * The single 0-100 number the product displays, plus everything the
 * explainer needs to verbalize it. Always pair `final_score` with
 * `explanation` when rendering to users.
 */
export interface TourFinalScore {
  tour_id: string;
  final_score: number;              // 0-100
  absolute: TourAbsoluteScore;
  intent_fits: TourIntentFitScore[];
  product_mode: ProductMode;

  /** Weight on absolute vs intent blend. */
  blend_config: {
    absolute_weight: number;    // default 0.6
    intent_weight: number;      // default 0.4
  };

  /** One-sentence human-friendly summary, emitted by the explainer. */
  explanation?: string;
  scored_at: string;                // ISO8601
}

// ── Explainer output ─────────────────────────────────────────────────────────

/**
 * Structured tradeoff language for multi-candidate comparisons. The app
 * shows strings from this object verbatim, so keep them short, specific,
 * and never mention the numeric dimension names.
 */
export interface TourExplanation {
  headline: string;            // e.g. "Most iconic route."
  bullets: string[];           // short sentence each, max 3
  tradeoff_vs?: {              // when comparing against another candidate
    other_tour_id: string;
    this_wins_on: string[];    // phrases: "sunset payoff", "less traffic"
    other_wins_on: string[];
  };
}

// ── Candidate comparison ─────────────────────────────────────────────────────

/**
 * Output of the generator when N>1 candidates are produced. The reranker
 * picks the top one; the others stay in `candidate_tours` for analytics.
 */
export interface CandidateRanking {
  winner_tour_id: string;
  rankings: Array<{
    tour_id: string;
    final_score: number;
    explanation: TourExplanation;
  }>;
  rerank_reason: string;      // one sentence: why winner beat the others
}
