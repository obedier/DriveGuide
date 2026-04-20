// Turns a scored tour into a one-sentence human-friendly explanation that
// the iOS client renders under the score chip. Never names a dimension by
// its internal identifier ("narrative_flow"); always translates to the
// tester-facing vocabulary we picked in tour-scoring-spec.md.
//
// Scope: deterministic string-building, no LLM. The raw data is the tour's
// score bundle. The explainer is cheap enough to call on every API read
// and keeps the language consistent across the product.

import type { TourAbsoluteScore, TourIntentFitScore, TourExplanation } from './types.js';

/**
 * Short headline + 1-2 bullets. Good enough for the score chip.
 */
export function explainTour(
  absolute: TourAbsoluteScore,
  intentFits: TourIntentFitScore[],
): TourExplanation {
  const dims = absolute;
  type DimKey = keyof typeof dimensionCopy;
  const ranked: Array<{ key: DimKey; score: number }> = (
    [
      ['iconic_value', dims.iconic_value],
      ['geographic_coherence', dims.geographic_coherence],
      ['time_realism', dims.time_realism],
      ['narrative_flow', dims.narrative_flow],
      ['scenic_payoff', dims.scenic_payoff],
      ['variety_balance', dims.variety_balance],
      ['practical_usability', dims.practical_usability],
    ] as const
  ).map(([key, score]) => ({ key, score })).sort((a, b) => b.score - a.score);

  const top = ranked.slice(0, 2);
  const bottom = ranked.slice(-1)[0];

  const headline = headlineFor(absolute.composite, top);
  const bullets: string[] = [];
  for (const d of top) {
    bullets.push(dimensionCopy[d.key].strong);
  }
  if (bottom.score < 6) {
    bullets.push(dimensionCopy[bottom.key].weak);
  }
  // Top matching intent gets a dedicated bullet so the user can see why
  // this tour is "their kind of tour."
  const topIntent = [...intentFits].sort((a, b) => b.fit_score - a.fit_score)[0];
  if (topIntent && topIntent.fit_score >= 75 && intentCopy[topIntent.intent]) {
    bullets.push(intentCopy[topIntent.intent]);
  }

  return {
    headline,
    bullets: bullets.slice(0, 3),
  };
}

function headlineFor(
  composite: number,
  top: Array<{ key: keyof typeof dimensionCopy; score: number }>,
): string {
  if (composite >= 90) return `Gold-standard tour.`;
  if (composite >= 80) return `Strong tour — ${dimensionCopy[top[0].key].headline}.`;
  if (composite >= 65) return `Solid tour — ${dimensionCopy[top[0].key].headline}.`;
  if (composite >= 50) return `Decent tour with tradeoffs.`;
  return `Rough tour — may be hard to follow.`;
}

/**
 * Vocabulary per Layer A dimension. Keep each string short; the chip UI
 * is tight.
 */
const dimensionCopy: Record<
  'iconic_value' | 'geographic_coherence' | 'time_realism' |
  'narrative_flow' | 'scenic_payoff' | 'variety_balance' | 'practical_usability',
  { strong: string; weak: string; headline: string }
> = {
  iconic_value: {
    strong: 'Hits the must-see landmarks.',
    weak: 'Skips most of the city\'s famous stops.',
    headline: 'iconic route',
  },
  geographic_coherence: {
    strong: 'Tight, logical route with no backtracking.',
    weak: 'Route zig-zags and loses time.',
    headline: 'tight routing',
  },
  time_realism: {
    strong: 'The duration matches what you\'ll actually do.',
    weak: 'You\'ll likely run over or have empty time.',
    headline: 'realistic timing',
  },
  narrative_flow: {
    strong: 'Tells a coherent story stop to stop.',
    weak: 'Feels like a checklist, not a story.',
    headline: 'strong storytelling',
  },
  scenic_payoff: {
    strong: 'Big visual payoffs along the way.',
    weak: 'Light on scenic moments.',
    headline: 'scenic views',
  },
  variety_balance: {
    strong: 'Mix of landmarks, views, and neighborhood texture.',
    weak: 'Leans heavily on one kind of stop.',
    headline: 'varied mix',
  },
  practical_usability: {
    strong: 'Easy to actually execute — parking, access, flow.',
    weak: 'A few stops have access or parking friction.',
    headline: 'easy to execute',
  },
};

/**
 * Nice-to-read copy per intent tag. Missing entry = skip the intent
 * bullet in the explanation.
 */
const intentCopy: Record<string, string> = {
  first_time_highlights: 'Great if it\'s your first visit.',
  hidden_gems: 'Favors hidden gems over famous spots.',
  sunset: 'Timed around golden hour.',
  romantic: 'Great for a date night.',
  family_kids: 'Designed to keep kids engaged.',
  architecture: 'Architecture-heavy, for design nerds.',
  food: 'Food stops are the spine of the route.',
  local_authenticity: 'Local flavor over tourist trail.',
  scenic_drive: 'Built for the drive, not the stops.',
  minimal_walking: 'Low walking, easy access throughout.',
  history: 'History-rich at every stop.',
  nightlife: 'Evening and nightlife pacing.',
  quick_two_hours: 'Maximum payoff in two hours.',
};

/**
 * Compare two scored tours and tell the user which one wins on what.
 * Used by the N-candidate picker (2.17.1+) but the same function powers
 * any "alternate version" UI.
 */
export function explainTradeoff(
  mineAbsolute: TourAbsoluteScore,
  mineIntents: TourIntentFitScore[],
  otherAbsolute: TourAbsoluteScore,
  otherIntents: TourIntentFitScore[],
): { thisWinsOn: string[]; otherWinsOn: string[] } {
  const thisWins: string[] = [];
  const otherWins: string[] = [];

  type DimKey = keyof typeof dimensionCopy;
  const dims: DimKey[] = [
    'iconic_value', 'geographic_coherence', 'time_realism',
    'narrative_flow', 'scenic_payoff', 'variety_balance', 'practical_usability',
  ];

  for (const k of dims) {
    const mine = mineAbsolute[k];
    const other = otherAbsolute[k];
    if (mine - other >= 1.5) thisWins.push(dimensionCopy[k].headline);
    else if (other - mine >= 1.5) otherWins.push(dimensionCopy[k].headline);
  }

  // Intents: if they declared hidden_gems and this tour scored noticeably higher.
  const mineByIntent = new Map(mineIntents.map((i) => [i.intent, i.fit_score]));
  const otherByIntent = new Map(otherIntents.map((i) => [i.intent, i.fit_score]));
  for (const [intent, mine] of mineByIntent) {
    const other = otherByIntent.get(intent);
    if (other !== undefined && mine - other >= 10 && intentCopy[intent]) {
      thisWins.push(`better fit for "${intent.replaceAll('_', ' ')}"`);
    } else if (other !== undefined && other - mine >= 10 && intentCopy[intent]) {
      otherWins.push(`better fit for "${intent.replaceAll('_', ' ')}"`);
    }
  }

  return { thisWinsOn: thisWins.slice(0, 3), otherWinsOn: otherWins.slice(0, 3) };
}
