// Bridge narration — on-demand dynamic intro played when a user starts a
// tour but is still far from its first stop. Keeps them entertained during
// the drive/walk to the trailhead with tour context + arrival framing,
// THEN hands off to the pre-written segment 0 when they're close enough.
//
// Shape: POST /v1/tours/:id/bridge gets called by iOS on tour start if the
// user is >400m from stop 0 (car) or >150m (walk/bike). Returns text + a
// ready-to-play audio URL so the iOS client can hit play without waiting
// on any further round-trips.

import { GoogleGenerativeAI } from '@google/generative-ai';
import { env } from '../../config/env.js';
import { synthesizeOrCache } from '../audio/tts.js';
import { createHash } from 'crypto';

const genAI = new GoogleGenerativeAI(env.geminiApiKey);

export interface BridgeRequest {
  tourTitle: string;
  tourDescription: string;
  tourThemes: string[];
  transportMode: string;
  firstStopName: string;
  firstStopNeighborhood?: string;
  firstStopHookLine?: string;
  /// Straight-line distance in km from user to first stop.
  distanceKm: number;
  /// Rough minutes to get there, used in the prompt so Gemini can time
  /// the narration appropriately.
  etaMinutes: number;
  language: string;
  /// "opener" = the first bridge played on tour start. "follow_up" = a
  /// mid-drive refresher with different content. Controls the prompt
  /// scaffolding and the handoff line.
  kind?: 'opener' | 'follow_up';
  /// First-phrase signatures of previously-played bridges on this trip.
  /// Used to steer Gemini away from repeating the same opening device.
  previousOpeners?: string[];
}

export interface BridgeResult {
  narrationText: string;
  audioUrl: string;
  contentHash: string;
  durationSeconds: number;
}

const BRIDGE_STYLE = `
STYLE — this is a "drive-to" bridge narration:
- Warm, energetic, upbeat — the user is about to start an exciting tour.
- Acknowledge the short travel to the trailhead, set expectations, and build anticipation.
- Do NOT open with "Welcome", "Alright", "Hey", "Hello", or any greeting cliché.
- Do NOT fabricate specific facts about the user's current street or neighborhood — you don't know where they are.
- Reference the tour's themes and what makes the first stop worth the drive.
- End with a clear handoff: "I'll be quiet for a bit while you drive — I'll pick things back up the moment we're close."
`;

export async function generateBridgeNarration(req: BridgeRequest): Promise<BridgeResult> {
  const kind = req.kind ?? 'opener';
  const wordTarget = Math.max(60, Math.min(Math.round(req.etaMinutes * 25), 220));

  const kindPrompt = kind === 'opener'
    ? `TASK: The OPENER bridge — this is the first thing the user hears after tapping start.
Structure:
1. An opening that acknowledges the drive and hints at what's coming without giving it away.
2. One or two sentences of context — why this tour, why this first stop, what makes it worth it.
3. A handoff line telling the user the tour will pick back up when they arrive.`
    : `TASK: A FOLLOW-UP bridge — the user has been driving for a few minutes and the opener already set the stage. Do NOT repeat the opener's framing. Instead:
- Pick a DIFFERENT angle from the opener (e.g., a pop-culture tie, a surprising stat, a hidden-history nugget, a sensory tease).
- Keep it self-contained — no "as I was saying" references.
- Do NOT reintroduce the tour or restate the first-stop name with the same framing.
- Still end with a handoff line.`;

  const priorOpenersBlock = req.previousOpeners && req.previousOpeners.length > 0
    ? `\nPREVIOUSLY-USED OPENINGS on this same trip (avoid similar phrasing or structural device):\n${req.previousOpeners.slice(-6).map((o) => `- "${o}"`).join('\n')}\n`
    : '';

  const prompt = `You are writing a short "drive-to" bridge narration for wAIpoint, a private audio tour-guide app.

CONTEXT
- Tour: "${req.tourTitle}"
- Description: ${req.tourDescription}
- Themes: ${req.tourThemes.join(', ') || 'general'}
- Transport: ${req.transportMode}
- First stop: ${req.firstStopName}${req.firstStopNeighborhood ? ` (${req.firstStopNeighborhood})` : ''}
${req.firstStopHookLine ? `- First stop hook: ${req.firstStopHookLine}` : ''}
- User is approximately ${req.distanceKm.toFixed(1)} km away (~${req.etaMinutes} min by ${req.transportMode}).

${BRIDGE_STYLE}
${priorOpenersBlock}

${kindPrompt}

Return JUST the narration text — no JSON, no labels, no quotation marks around it.
Length target: ~${wordTarget} words (scales with ETA).`;

  const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });
  const res = await model.generateContent(prompt);
  const narrationText = res.response.text().trim();

  // Stable hash — same user+tour combination returns the cached audio on
  // subsequent calls (e.g., if the iOS client retries). Includes kind + an
  // opener-count bucket so follow-ups don't collide with the opener.
  const keyInput = `bridge:${kind}:${req.tourTitle}:${req.firstStopName}:${(req.previousOpeners ?? []).length}:${Math.round(req.distanceKm * 10)}:${narrationText.length}`;
  const contentHash = createHash('sha256').update(keyInput).digest('hex');

  const audio = await synthesizeOrCache(
    narrationText,
    contentHash,
    req.language || 'en',
    'en-US-Journey-D',
  );

  return {
    narrationText,
    audioUrl: audio.public_url,
    contentHash,
    durationSeconds: audio.duration_seconds,
  };
}
