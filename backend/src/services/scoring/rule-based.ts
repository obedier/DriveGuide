// Rule-based scorers — the Layer A and stop-level dimensions that can be
// computed from the tour's own geometry without calling an LLM. Keeping
// these separate from Gemini-based scorers makes them cheap, fast, and
// deterministic. Every function is pure: same inputs → same output.

import type { StopScore, TourAbsoluteScore } from './types.js';

// Minimal shape the scorers need. Matches the fields from `tour_stops`.
export interface ScorableStop {
  id: string;
  sequence_order: number;
  name: string;
  category: string;
  latitude: number;
  longitude: number;
  recommended_stay_minutes: number;
  /** Optional structured attributes from featured-tours-research.md. */
  iconicity_hint?: number;     // 0-10, authorial hint when available
  scenic_hint?: number;
  story_hint?: number;
  best_time_of_day?: string;
  family_friendliness?: number;
  access_friction?: 'low' | 'medium' | 'high';
  parking_friction?: 'low' | 'medium' | 'high' | 'not_applicable';
  walking_burden?: 'none' | 'light' | 'moderate' | 'heavy';
  accessibility_notes?: string;
  cluster_id?: string;
}

export interface ScorableTour {
  id: string;
  title: string;
  description: string;
  duration_minutes: number;
  transport_mode: 'car' | 'walk' | 'bike' | 'boat';
  themes?: string[];
  scheduled_time_of_day?: string;   // 'morning' | 'afternoon' | 'golden_hour' | etc.
  stops: ScorableStop[];
}

// ── Geographic helpers ───────────────────────────────────────────────────────

const EARTH_KM = 6371;

/** Haversine distance in km between two points. */
export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_KM * Math.asin(Math.sqrt(a));
}

// ── Stop-level scorers ───────────────────────────────────────────────────────

/**
 * 0-10. Lower = more friction (harder to reach, park, walk to).
 * Built from access/parking/walking triplet; normalized so 10 = frictionless,
 * 0 = hellish.
 */
export function scoreFriction(stop: ScorableStop): number {
  const weight = { low: 10, medium: 6, high: 2, not_applicable: 9, none: 10, light: 9, moderate: 6, heavy: 2 };
  const acc = weight[stop.access_friction ?? 'low'];
  const park = weight[stop.parking_friction ?? 'not_applicable'];
  const walk = weight[stop.walking_burden ?? 'none'];
  // Unweighted mean keeps the model simple; tune later via weight history.
  return Math.max(0, Math.min(10, (acc + park + walk) / 3));
}

/**
 * 0-10. Does this stop fit the tour's route? Penalties for:
 *   - Geographic backtracking (stop N farther from N-2 than N-1 was)
 *   - Cluster fragmentation (jumping between cluster_ids mid-tour)
 */
export function scoreRouteFit(stop: ScorableStop, tour: ScorableTour, index: number): number {
  const stops = tour.stops;
  if (stops.length < 2) return 10;   // single-stop tours always "fit"

  let score = 10;

  // Backtrack penalty: distance to prev > distance to next suggests
  // out-of-order placement. Caps at -3 per offense.
  if (index > 0 && index < stops.length - 1) {
    const prev = stops[index - 1];
    const next = stops[index + 1];
    const prevNext = haversineKm(prev.latitude, prev.longitude, next.latitude, next.longitude);
    const prevHere = haversineKm(prev.latitude, prev.longitude, stop.latitude, stop.longitude);
    const hereNext = haversineKm(stop.latitude, stop.longitude, next.latitude, next.longitude);
    const detour = (prevHere + hereNext) - prevNext;
    if (detour > prevNext * 0.5) score -= 3;          // detour > 50% of direct path
    else if (detour > prevNext * 0.2) score -= 1.5;
  }

  // Cluster cohesion: if two neighbors belong to different clusters AND
  // this stop bridges them, we've lost 1 point of cohesion.
  if (stop.cluster_id && index > 0 && index < stops.length - 1) {
    const prevCluster = stops[index - 1].cluster_id;
    const nextCluster = stops[index + 1].cluster_id;
    if (prevCluster && nextCluster && prevCluster !== nextCluster && stop.cluster_id === nextCluster) {
      score -= 1;
    }
  }

  return Math.max(0, Math.min(10, score));
}

/**
 * 0-10. How well this stop's `best_time_of_day` matches the tour's
 * scheduled time. No schedule = neutral 7.
 */
export function scoreTimeOfDayFit(stop: ScorableStop, tour: ScorableTour): number {
  if (!stop.best_time_of_day || !tour.scheduled_time_of_day) return 7;
  if (stop.best_time_of_day === 'any') return 9;
  if (stop.best_time_of_day === tour.scheduled_time_of_day) return 10;
  // "golden_hour" vs "afternoon" — close enough.
  const adjacent = new Set([
    ['morning', 'midday'], ['midday', 'afternoon'],
    ['afternoon', 'golden_hour'], ['golden_hour', 'night'],
  ].flatMap(([a, b]) => [`${a}|${b}`, `${b}|${a}`]));
  if (adjacent.has(`${stop.best_time_of_day}|${tour.scheduled_time_of_day}`)) return 6;
  return 3;
}

/**
 * 0-10. Higher = better "wow-per-minute". Capped by iconicity_hint so we
 * don't reward a tiny payoff at a no-name plaza.
 */
export function scoreDwellEfficiency(stop: ScorableStop): number {
  const iconicity = stop.iconicity_hint ?? 5;
  const minutes = Math.max(1, stop.recommended_stay_minutes);
  // Inverse of minutes, scaled by iconicity. 5 min at iconicity 10 = ~10.
  const raw = (iconicity * 5) / minutes;
  return Math.max(0, Math.min(10, raw));
}

export function scoreAccessibility(stop: ScorableStop): number {
  // No structured accessibility signal yet — fall back to friction as a
  // weak proxy. When the backend adds wheelchair_accessible etc. columns,
  // swap this in.
  return scoreFriction(stop);
}

export function scoreFamilyFit(stop: ScorableStop): number {
  const base = stop.family_friendliness ?? 5;
  return Math.max(0, Math.min(10, base));
}

// ── Tour-level (Layer A) scorers ─────────────────────────────────────────────

/**
 * 0-10. Perfect = tight-clustered, minimal backtracking, cluster cohesion.
 *
 * Heuristic: total-path-length / min-spanning-path-length. Closer to 1.0 = 10.
 * Above 1.5 = 4. Above 2.0 = 1.
 */
export function scoreGeographicCoherence(tour: ScorableTour): number {
  const stops = tour.stops;
  if (stops.length < 2) return 10;

  const actualPath = stops.reduce((sum, s, i) =>
    i === 0 ? 0 : sum + haversineKm(stops[i-1].latitude, stops[i-1].longitude, s.latitude, s.longitude),
    0);

  // Proxy for min spanning path: sort stops by lat then lng, sum pairwise
  // distances. Not a true nearest-neighbor but catches egregious zig-zags.
  const sorted = [...stops].sort((a, b) =>
    a.latitude !== b.latitude ? a.latitude - b.latitude : a.longitude - b.longitude);
  const sortedPath = sorted.reduce((sum, s, i) =>
    i === 0 ? 0 : sum + haversineKm(sorted[i-1].latitude, sorted[i-1].longitude, s.latitude, s.longitude),
    0);

  if (sortedPath === 0) return 10;
  const ratio = actualPath / sortedPath;
  if (ratio <= 1.1) return 10;
  if (ratio <= 1.3) return 8;
  if (ratio <= 1.5) return 6;
  if (ratio <= 2.0) return 4;
  return 1;
}

/**
 * 0-10. Does the declared duration match the sum of stop dwell times +
 * transit? Penalize tours that claim 2 hours but schedule 4 hours of
 * stops, or vice versa.
 */
export function scoreTimeRealism(tour: ScorableTour): number {
  const stops = tour.stops;
  if (stops.length === 0) return 5;

  const dwellMin = stops.reduce((sum, s) => sum + s.recommended_stay_minutes, 0);

  // Transit time: rough distance-based estimate.
  const speedKph = tour.transport_mode === 'walk' ? 5 :
                   tour.transport_mode === 'bike' ? 16 :
                   tour.transport_mode === 'boat' ? 20 : 40;
  let transitKm = 0;
  for (let i = 1; i < stops.length; i++) {
    transitKm += haversineKm(stops[i-1].latitude, stops[i-1].longitude,
                             stops[i].latitude, stops[i].longitude);
  }
  const transitMin = (transitKm / speedKph) * 60;

  const estimatedMin = dwellMin + transitMin;
  const declaredMin = tour.duration_minutes;
  if (declaredMin <= 0) return 3;

  const ratio = estimatedMin / declaredMin;
  // 0.85-1.15 = perfect (10). Each 10% drift past = -2.
  if (ratio >= 0.85 && ratio <= 1.15) return 10;
  if (ratio >= 0.7 && ratio <= 1.3) return 7;
  if (ratio >= 0.5 && ratio <= 1.5) return 4;
  return 1;
}

/**
 * 0-10. Diversity of stop categories. All-museums = 3. Mix of landmark /
 * food / viewpoint / neighborhood = 10.
 */
export function scoreVarietyBalance(tour: ScorableTour): number {
  if (tour.stops.length === 0) return 0;
  const categories = new Set(tour.stops.map((s) => s.category || 'other'));
  // Rough: 1 category = 2, 2 = 5, 3 = 8, 4+ = 10.
  const n = categories.size;
  if (n >= 4) return 10;
  if (n === 3) return 8;
  if (n === 2) return 5;
  return 2;
}

/**
 * 0-10. Practical usability: driving-allowed routes (no ZTL), no
 * reservation blockers, transport mode matches stop accessibility.
 *
 * Current heuristic: penalize 1 pt per stop with high access_friction,
 * clamp at 4.
 */
export function scorePracticalUsability(tour: ScorableTour): number {
  const blockers = tour.stops.filter((s) => s.access_friction === 'high').length;
  return Math.max(4, 10 - blockers);
}

/**
 * Weighted composite 0-10 for a stop per tour-scoring-spec.md §2.
 */
export function computeStopComposite(score: Omit<StopScore, 'composite' | 'stop_id' | 'sequence_order'>): number {
  return (
    0.22 * score.iconicity +
    0.18 * score.scenic_payoff +
    0.15 * score.story_richness +
    0.10 * score.dwell_efficiency +
    0.10 * score.friction +
    0.10 * score.route_fit +
    0.05 * score.time_of_day_fit +
    0.04 * score.family_fit +
    0.03 * score.accessibility +
    0.03 * score.wow_per_minute
  );
}

/**
 * Weighted composite 0-100 for Layer A.
 */
export function computeAbsoluteComposite(
  score: Omit<TourAbsoluteScore, 'composite' | 'weights' | 'rationale'>,
  weights: TourAbsoluteScore['weights']
): number {
  const raw =
    weights.iconic_value * score.iconic_value +
    weights.geographic_coherence * score.geographic_coherence +
    weights.time_realism * score.time_realism +
    weights.narrative_flow * score.narrative_flow +
    weights.scenic_payoff * score.scenic_payoff +
    weights.variety_balance * score.variety_balance +
    weights.practical_usability * score.practical_usability;
  return Math.max(0, Math.min(100, raw * 10));   // raw is 0-10, multiply by 10 for 0-100 scale
}
