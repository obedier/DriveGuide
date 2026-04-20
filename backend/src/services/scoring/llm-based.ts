// Gemini-backed scorers for the dimensions that need world knowledge:
// iconicity, story_richness, scenic_payoff (stop-level) + iconic_value
// and narrative_flow (tour-level).
//
// Design:
//   - Prompt returns strict JSON. We parse + validate every field.
//   - Per-stop scores are memoized by (stop name + city hint) so the same
//     stop in different tours doesn't pay multiple Gemini calls.
//   - Every scorer has a rule-based fallback (iconicity_hint / LP tags /
//     category) so the system degrades gracefully when Gemini is down or
//     quota is exceeded.
//
// Why not measure scenic_payoff from photo pixel analysis? Because the
// signal we actually want — "will a human traveler feel awe here?" — is
// a cultural judgment that an LLM calibrated against exemplar prompts
// approximates better than any CV pipeline at this stage of the product.

import { GoogleGenerativeAI } from '@google/generative-ai';
import { LRUCache } from 'lru-cache';
import { env } from '../../config/env.js';
import type { ScorableStop, ScorableTour } from './rule-based.js';

const genAI = new GoogleGenerativeAI(env.geminiApiKey);

// Cached per (stop-name + city-hint) — identity is "what's being scored",
// not "what tour is it in". Same stop, different tours = same iconicity.
interface StopQualityScore {
  iconicity: number;
  scenic_payoff: number;
  story_richness: number;
  rationale: Record<string, string>;
}

const stopCache = new LRUCache<string, StopQualityScore>({
  max: 5000,
  ttl: 7 * 24 * 60 * 60 * 1000,  // 7 days — these ratings don't move fast
});

function cacheKey(stop: ScorableStop, city: string | undefined): string {
  return `${(city ?? '').toLowerCase()}|${stop.name.toLowerCase()}`;
}

// ── Stop-level: iconicity, scenic_payoff, story_richness ─────────────────────

/**
 * Score one stop's three qualitative dimensions in a single Gemini call.
 * Returns rule-based fallbacks on any error so a flaky LLM never blocks
 * tour generation.
 */
export async function scoreStopQuality(
  stop: ScorableStop,
  cityHint?: string,
): Promise<StopQualityScore> {
  const key = cacheKey(stop, cityHint);
  const cached = stopCache.get(key);
  if (cached) return cached;

  const prompt = `You are scoring a tour stop on three dimensions for wAIpoint, a travel app.

STOP: ${stop.name}${cityHint ? ` (${cityHint})` : ''}
CATEGORY: ${stop.category}
Coordinates: ${stop.latitude.toFixed(4)}, ${stop.longitude.toFixed(4)}

Score 0-10 on each:

1. iconicity — How globally recognizable / bucket-list is this place?
   Calibration anchors:
   - 10: Eiffel Tower, Times Square, Grand Canyon
   - 8: Space Needle, French Quarter, Alcatraz
   - 6: Griffith Observatory, Freedom Trail, Pike Place
   - 4: Notable local park or neighborhood plaza
   - 2: A nice-but-obscure local spot
   - 0: A random street corner

2. scenic_payoff — Visual "wow" a visitor experiences.
   - 10: Grand Canyon rim at sunset; Golden Gate from Battery Spencer
   - 8: Iconic skyline view; dramatic coastal vista
   - 6: Pretty urban park, photogenic architecture
   - 4: Pleasant but unremarkable
   - 2: Has limited visual appeal
   - 0: Ugly or nothing to look at

3. story_richness — Density of narratable history/pop-culture/architecture for
   a 2-3 minute audio segment.
   - 10: Colosseum, Independence Hall (centuries of stories per square meter)
   - 8: Art Deco Welcome Center, Walt Disney Concert Hall
   - 6: Classic diner with a 50-year history
   - 4: Notable but single-story
   - 2: Minor local significance
   - 0: No story to tell

Return STRICT JSON, no markdown fence, no preamble:
{
  "iconicity": <number 0-10>,
  "scenic_payoff": <number 0-10>,
  "story_richness": <number 0-10>,
  "rationale": {
    "iconicity": "<≤20 word justification>",
    "scenic_payoff": "<≤20 word justification>",
    "story_richness": "<≤20 word justification>"
  }
}`;

  try {
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });
    const res = await model.generateContent(prompt);
    const text = res.response.text().trim();
    const json = extractJson(text);
    const parsed = JSON.parse(json) as StopQualityScore;
    const result: StopQualityScore = {
      iconicity: clamp(parsed.iconicity, 0, 10),
      scenic_payoff: clamp(parsed.scenic_payoff, 0, 10),
      story_richness: clamp(parsed.story_richness, 0, 10),
      rationale: parsed.rationale ?? {},
    };
    stopCache.set(key, result);
    return result;
  } catch (err) {
    console.error(`[scoring.llm-based] scoreStopQuality fallback for "${stop.name}":`, (err as Error).message);
    return fallbackStopQuality(stop);
  }
}

/**
 * Rule-based fallback: uses authorial hints if present, otherwise derives
 * from category. Never throws.
 */
function fallbackStopQuality(stop: ScorableStop): StopQualityScore {
  const categoryDefaults: Record<string, { iconicity: number; scenic: number; story: number }> = {
    landmark:  { iconicity: 7, scenic: 7, story: 8 },
    viewpoint: { iconicity: 5, scenic: 9, story: 4 },
    museum:    { iconicity: 6, scenic: 5, story: 9 },
    park:      { iconicity: 5, scenic: 7, story: 4 },
    food:      { iconicity: 4, scenic: 5, story: 5 },
    neighborhood: { iconicity: 5, scenic: 5, story: 6 },
    waterfront: { iconicity: 6, scenic: 8, story: 5 },
  };
  const d = categoryDefaults[stop.category] ?? { iconicity: 5, scenic: 5, story: 5 };
  return {
    iconicity: stop.iconicity_hint ?? d.iconicity,
    scenic_payoff: stop.scenic_hint ?? d.scenic,
    story_richness: stop.story_hint ?? d.story,
    rationale: {
      iconicity: stop.iconicity_hint !== undefined
        ? `Authorial hint (${stop.iconicity_hint}/10)`
        : `Fallback by category '${stop.category}'`,
      scenic_payoff: 'Fallback — Gemini unavailable',
      story_richness: 'Fallback — Gemini unavailable',
    },
  };
}

// ── Tour-level: iconic_value, narrative_flow, scenic_payoff ──────────────────

export interface TourQualityScore {
  iconic_value: number;
  narrative_flow: number;
  scenic_payoff: number;
  rationale: Record<string, string>;
}

/**
 * iconic_value and scenic_payoff are roll-ups from stop scores, but
 * narrative_flow needs Gemini because it's about how the tour ARC reads
 * when told in order (not just the sum of stop story-richnesses).
 */
export async function scoreTourQuality(
  tour: ScorableTour,
  stopScores: Array<{ stop: ScorableStop; quality: StopQualityScore }>,
): Promise<TourQualityScore> {
  // Roll-ups: top-3 stops drive the "iconic_value" feeling (one knockout
  // landmark can carry a tour), while scenic is a mean.
  const sortedByIcon = [...stopScores].sort((a, b) => b.quality.iconicity - a.quality.iconicity);
  const topIconic = sortedByIcon.slice(0, 3).map((s) => s.quality.iconicity);
  const iconicValue = clamp(mean(topIconic) * 0.8 + mean(stopScores.map((s) => s.quality.iconicity)) * 0.2, 0, 10);
  const scenicPayoff = clamp(mean(stopScores.map((s) => s.quality.scenic_payoff)), 0, 10);

  // narrative_flow — ask Gemini to read the sequence as a story.
  let narrativeFlow: number;
  let narrativeRationale: string;
  try {
    const stopList = tour.stops.map((s, i) =>
      `${i + 1}. ${s.name} (${s.category})`).join('\n');
    const prompt = `Score the NARRATIVE FLOW of this tour on 0-10.

Narrative flow is how well the stop sequence reads as a unified story when an audio guide ties them together. Not just "are these stops good"; rather "do they build a memorable arc?".

TOUR: "${tour.title}"
DESCRIPTION: ${tour.description}
THEME: ${(tour.themes ?? []).join(', ')}
STOP SEQUENCE:
${stopList}

Calibration:
- 10: Every stop elevates the last; clear narrative arc from opener to climax to resolution (e.g. Mulholland → Griffith → Sunset Strip → Pacific coast)
- 7: Solid grouping with a thematic spine, minor tonal gaps
- 5: Stops are individually good but feel like a list
- 3: Jarring contrasts, no thread
- 0: Random assortment, no story possible

Return JSON ONLY:
{ "score": <0-10>, "rationale": "<≤30 word explanation>" }`;
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });
    const res = await model.generateContent(prompt);
    const parsed = JSON.parse(extractJson(res.response.text())) as { score: number; rationale: string };
    narrativeFlow = clamp(parsed.score, 0, 10);
    narrativeRationale = parsed.rationale;
  } catch (err) {
    console.error('[scoring.llm-based] narrative_flow fallback:', (err as Error).message);
    // Fallback: if the top-3 story-richness is high and the stops share
    // a theme, narrative is probably at least passable.
    narrativeFlow = clamp(mean(stopScores.map((s) => s.quality.story_richness)) * 0.9, 0, 10);
    narrativeRationale = 'Fallback from story_richness mean';
  }

  return {
    iconic_value: iconicValue,
    narrative_flow: narrativeFlow,
    scenic_payoff: scenicPayoff,
    rationale: {
      iconic_value: `Top-3 iconicity mean=${mean(topIconic).toFixed(1)}`,
      narrative_flow: narrativeRationale,
      scenic_payoff: `Mean across ${stopScores.length} stops`,
    },
  };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function clamp(n: number, lo: number, hi: number): number {
  if (Number.isNaN(n)) return lo;
  return Math.max(lo, Math.min(hi, n));
}

function mean(xs: number[]): number {
  if (xs.length === 0) return 0;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

function extractJson(text: string): string {
  const fenced = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/);
  let raw = fenced ? fenced[1].trim() : text;
  const first = raw.indexOf('{');
  const last = raw.lastIndexOf('}');
  if (first !== -1 && last > first) raw = raw.slice(first, last + 1);
  return raw.replace(/,(\s*[}\]])/g, '$1');
}

// ── Cache utilities for tests ────────────────────────────────────────────────

export function clearStopQualityCacheForTesting(): void {
  stopCache.clear();
}

export function stopQualityCacheSizeForTesting(): number {
  return stopCache.size;
}
