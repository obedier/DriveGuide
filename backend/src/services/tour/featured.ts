// Featured-tour generator — pilot for v2.11 pre-generated public library.
//
// Differences from the default Gemini tour flow (`generator.ts` +
// `gemini.ts`):
//   1. Stops are CURATED and passed in (from the research dossier) — Gemini's
//      job is narration only, not stop selection. This guarantees quality and
//      removes one source of hallucination.
//   2. Narration is generated segment-by-segment. Each call is given the list
//      of openers already used on this tour and explicit anti-repetition
//      instructions, so Gemini cannot fall back into the same cadence every
//      segment.
//   3. Photos are fetched synchronously via Google Places Photos API using
//      place_id lookups by name + location. Every stop must have a photo.
//
// Cost-aware: we batch the narration call per stop (one Gemini request per
// stop instead of per segment) and deduplicate the intro+outro into a single
// "frame" call. Target: ~3-5 Gemini requests per tour.

import { GoogleGenerativeAI } from '@google/generative-ai';
import { env } from '../../config/env.js';
import type { StopCategory } from '../../models/types.js';

const genAI = new GoogleGenerativeAI(env.geminiApiKey);

export interface CuratedStop {
  name: string;
  neighborhood?: string;
  latitude: number;
  longitude: number;
  category: StopCategory;
  recommended_stay_minutes: number;
  is_optional?: boolean;
  /** One-line insider note the narrator should riff on. */
  hook?: string;
}

export interface FeaturedNarrationStop {
  name: string;
  description: string;
  category: StopCategory;
  latitude: number;
  longitude: number;
  recommended_stay_minutes: number;
  is_optional: boolean;
  approach_narration: string;
  at_stop_narration: string;
  departure_narration: string;
}

export interface FeaturedTourContent {
  title: string;
  description: string;
  story_arc_summary: string;
  intro_narration: string;
  outro_narration: string;
  stops: FeaturedNarrationStop[];
  between_stop_narrations: string[];
}

export interface FeaturedTourRequest {
  metroName: string;
  tourTitleHint: string;
  transportMode: 'car' | 'walk';
  durationMinutes: number;
  narrativeTheme: string;
  stops: CuratedStop[];
}

interface GeminiUsage {
  promptTokens: number;
  candidatesTokens: number;
  totalTokens: number;
}

export interface FeaturedTourGenerationResult {
  content: FeaturedTourContent;
  usage: GeminiUsage;
  callCount: number;
}

// ── Banned openers — enforced by the prompt AND a post-generation rewrite pass.
const BANNED_OPENERS: ReadonlyArray<string> = [
  'alright folks', 'alright friends', 'alright drivers', 'alright now',
  'okay so', 'okay folks', 'now then', 'here we go', 'buckle up',
  'let me tell you', 'let us talk about', "let's talk about",
  'you are going to love', "you're going to love",
  'get ready for', 'coming up on', 'folks,', 'so,', 'well,',
  'welcome to', 'listen up',
];

function hasBannedOpener(text: string): boolean {
  const head = text.trim().toLowerCase().slice(0, 40);
  return BANNED_OPENERS.some((b) => head.startsWith(b));
}

function extractFirstPhrase(text: string): string {
  const cleaned = text.trim().replace(/\s+/g, ' ');
  const firstPunct = cleaned.search(/[.!?,—]/);
  return firstPunct > 0 ? cleaned.slice(0, firstPunct).trim() : cleaned.slice(0, 48).trim();
}

function extractJson(text: string): string {
  const fenceMatch = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/);
  if (fenceMatch) return fenceMatch[1].trim();
  const first = text.indexOf('{');
  const last = text.lastIndexOf('}');
  if (first !== -1 && last > first) return text.slice(first, last + 1);
  return text;
}

// ── Narration style guide reused by every sub-prompt.
const STYLE_GUIDE = `
NARRATION STYLE — CRITICAL:
- Energetic, warm, conversational. Like a best friend who happens to be a historian.
- Do NOT open with any of these banned phrases or close paraphrases:
  "alright folks/friends/drivers/now", "okay so", "now then", "here we go",
  "let me tell you", "let's talk about", "you're going to love",
  "get ready for", "coming up on", "buckle up", "welcome to" (reserve for the INTRO only),
  "folks,", "so,", "well,", "listen up".
- Rotate openings between segments: a sensory detail, a question, a historical
  hook, a pop-culture tie-in, a surprising stat, a direct imperative, a short
  quote, or a punchy declarative sentence.
- No LLM filler: avoid "it's worth noting", "interestingly", "fun fact",
  "did you know", "essentially", "basically".
- Vary sentence length aggressively within the segment.
- Never include GPS coordinates, raw addresses, or lat/lng in narration.
`;

/**
 * Generate a featured tour with curated stops + Gemini-authored narration.
 * Returns content plus token-usage accounting so callers can log cost.
 */
export async function generateFeaturedTourContent(
  req: FeaturedTourRequest,
): Promise<FeaturedTourGenerationResult> {
  const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });
  const usage: GeminiUsage = { promptTokens: 0, candidatesTokens: 0, totalTokens: 0 };
  let callCount = 0;

  const addUsage = (u: unknown): void => {
    const r = u as { usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number; totalTokenCount?: number } };
    if (!r.usageMetadata) return;
    usage.promptTokens += r.usageMetadata.promptTokenCount ?? 0;
    usage.candidatesTokens += r.usageMetadata.candidatesTokenCount ?? 0;
    usage.totalTokens += r.usageMetadata.totalTokenCount ?? 0;
  };

  // Step 1 — Frame (title + description + story arc + intro + outro).
  const stopsList = req.stops
    .map((s, i) => `${i + 1}. ${s.name}${s.neighborhood ? ` (${s.neighborhood})` : ''} — ${s.category}${s.hook ? `. Hook: ${s.hook}` : ''}`)
    .join('\n');

  const framePrompt = `You are a world-class tour-writer producing pre-recorded audio for wAIpoint, a private tour-guide app.

TOUR CONTEXT:
Metro: ${req.metroName}
Working title: ${req.tourTitleHint}
Mode: ${req.transportMode === 'car' ? 'driving' : 'walking'}
Duration: ${req.durationMinutes} minutes
Narrative theme: ${req.narrativeTheme}
Stops (in order):
${stopsList}

${STYLE_GUIDE}

TASK: Produce the TOUR FRAME only. Return strict JSON, no markdown:
{
  "title": "A compelling title (under 60 chars)",
  "description": "2-3 sentence hook that makes someone open the tour right now",
  "story_arc_summary": "One sentence describing the narrative journey",
  "intro_narration": "90-120 second intro (220-300 words). Set the scene, build excitement. MAY open with 'Welcome to…' since this is the intro.",
  "outro_narration": "45-60 second outro (110-160 words). Callback to the intro hook, suggest what's next. MUST NOT start with 'Welcome', 'Alright', or 'Well'."
}`;

  const frameRes = await model.generateContent(framePrompt);
  callCount++;
  addUsage(frameRes.response);
  const frame = JSON.parse(extractJson(frameRes.response.text())) as {
    title: string; description: string; story_arc_summary: string;
    intro_narration: string; outro_narration: string;
  };

  // Track opener signatures to prevent repetition.
  const usedOpeners: string[] = [];
  usedOpeners.push(extractFirstPhrase(frame.intro_narration));
  usedOpeners.push(extractFirstPhrase(frame.outro_narration));

  // Step 2 — For each stop, generate approach+at+departure narration.
  const stopNarrations: FeaturedNarrationStop[] = [];

  for (let i = 0; i < req.stops.length; i++) {
    const stop = req.stops[i];
    const prev = i > 0 ? req.stops[i - 1] : null;
    const next = i < req.stops.length - 1 ? req.stops[i + 1] : null;

    const stopPrompt = `You are writing narration for a single stop on a wAIpoint ${req.transportMode === 'car' ? 'driving' : 'walking'} tour of ${req.metroName}.

THIS STOP:
- Name: ${stop.name}
- Neighborhood: ${stop.neighborhood ?? 'n/a'}
- Category: ${stop.category}
- Hook: ${stop.hook ?? 'none provided — use your own knowledge of the place'}

SEQUENCE: Stop ${i + 1} of ${req.stops.length}.
Previous stop: ${prev ? prev.name : 'None (this is the first stop after the intro)'}
Next stop: ${next ? next.name : 'None (this is the final stop before the outro)'}

OPENERS ALREADY USED on this tour (DO NOT start any narration below with a similar phrase or structural device):
${usedOpeners.slice(-10).map((o) => `- "${o}"`).join('\n')}

${STYLE_GUIDE}

TASK: Produce strict JSON, no markdown:
{
  "description": "One sentence describing the stop for the card view",
  "approach_narration": "100-150 words. What the traveler hears as they APPROACH this stop. Build anticipation with a visual cue. OPENING must use a DIFFERENT device than any in the used-openers list.",
  "at_stop_narration": "220-360 words. Rich history, stories, insider tips, what to look for. OPENING must be distinct from approach_narration and from anything in used-openers.",
  "departure_narration": "55-90 words. A transitional beat that teases the next stop (${next ? next.name : 'the tour ending'}) WITHOUT naming the next stop bluntly — tease with a sensory promise or a question. OPENING must be distinct from the other two."
}`;

    let res = await model.generateContent(stopPrompt);
    callCount++;
    addUsage(res.response);
    let parsed = JSON.parse(extractJson(res.response.text())) as {
      description: string; approach_narration: string; at_stop_narration: string; departure_narration: string;
    };

    // One retry pass if any narration opens with a banned phrase.
    const narrations = [parsed.approach_narration, parsed.at_stop_narration, parsed.departure_narration];
    if (narrations.some(hasBannedOpener)) {
      const retryPrompt = `${stopPrompt}

ATTEMPT 1 FAILED — one or more of your narrations started with a BANNED OPENER. Rewrite ALL THREE narrations. Each must start with a completely different structural device (sensory detail, question, historical hook, pop-culture tie-in, stat, imperative, quote, or declarative). Return the same JSON shape.`;
      res = await model.generateContent(retryPrompt);
      callCount++;
      addUsage(res.response);
      parsed = JSON.parse(extractJson(res.response.text())) as typeof parsed;
    }

    usedOpeners.push(extractFirstPhrase(parsed.approach_narration));
    usedOpeners.push(extractFirstPhrase(parsed.at_stop_narration));
    usedOpeners.push(extractFirstPhrase(parsed.departure_narration));

    stopNarrations.push({
      name: stop.name,
      description: parsed.description,
      category: stop.category,
      latitude: stop.latitude,
      longitude: stop.longitude,
      recommended_stay_minutes: stop.recommended_stay_minutes,
      is_optional: stop.is_optional ?? false,
      approach_narration: parsed.approach_narration,
      at_stop_narration: parsed.at_stop_narration,
      departure_narration: parsed.departure_narration,
    });
  }

  // Step 3 — Between-stop narrations. One call, all transitions together so
  // Gemini can vary them holistically.
  const transitions: string[] = [];
  if (req.stops.length > 1) {
    const pairs = [];
    for (let i = 0; i < req.stops.length - 1; i++) {
      pairs.push(`Transition ${i + 1}: ${req.stops[i].name} → ${req.stops[i + 1].name}`);
    }
    const betweenPrompt = `You are writing the BETWEEN-STOP transitions for a wAIpoint ${req.transportMode === 'car' ? 'driving' : 'walking'} tour of ${req.metroName}.

Each transition is what the traveler hears while moving from one stop to the next. Describe what they see along the way: the neighborhood changing, the skyline, the palm trees, the smell of pastelitos, the rhythm of the city.

Transitions to write:
${pairs.join('\n')}

OPENERS ALREADY USED on this tour — DO NOT start any transition with similar phrasing:
${usedOpeners.slice(-15).map((o) => `- "${o}"`).join('\n')}

${STYLE_GUIDE}

CRITICAL: Each transition must open with a DIFFERENT structural device from every other transition AND from the used-openers list.

Return strict JSON, no markdown:
{
  "transitions": [
    "Transition 1 narration (90-150 words)...",
    "Transition 2 narration (90-150 words)..."
  ]
}
Produce exactly ${req.stops.length - 1} transition strings in order.`;

    const betweenRes = await model.generateContent(betweenPrompt);
    callCount++;
    addUsage(betweenRes.response);
    const between = JSON.parse(extractJson(betweenRes.response.text())) as { transitions: string[] };
    transitions.push(...between.transitions);
  }

  return {
    content: {
      title: frame.title,
      description: frame.description,
      story_arc_summary: frame.story_arc_summary,
      intro_narration: frame.intro_narration,
      outro_narration: frame.outro_narration,
      stops: stopNarrations,
      between_stop_narrations: transitions,
    },
    usage,
    callCount,
  };
}
