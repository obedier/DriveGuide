import { GoogleGenerativeAI } from '@google/generative-ai';
import { env } from '../../config/env.js';
import type { TourTheme, StopCategory } from '../../models/types.js';

const genAI = new GoogleGenerativeAI(env.geminiApiKey);

interface GeminiTourStop {
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

interface GeminiTourResponse {
  title: string;
  description: string;
  story_arc_summary: string;
  stops: GeminiTourStop[];
  between_stop_narrations: string[];
  intro_narration: string;
  outro_narration: string;
}

export async function generateTourContent(
  locationName: string,
  formattedAddress: string,
  _centerLat: number,
  _centerLng: number,
  durationMinutes: number,
  themes: TourTheme[],
  nearbyPlaces: Array<{ name: string; latitude: number; longitude: number; types: string[]; rating?: number; vicinity?: string }>,
  language: string = 'en',
): Promise<GeminiTourResponse> {
  const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash' });

  const stopCount = getStopCount(durationMinutes);
  const themesStr = themes.length > 0 ? themes.join(', ') : 'general highlights, hidden gems, local culture';

  const placesContext = nearbyPlaces.slice(0, 30).map((p) =>
    `- ${p.name} (${p.latitude}, ${p.longitude}) — ${p.types.slice(0, 3).join(', ')}${p.rating ? `, rating: ${p.rating}` : ''}`
  ).join('\n');

  const prompt = `You are a brilliant, charismatic local tour guide who has lived in ${locationName} for 20 years. You know every hidden corner, the best stories, the insider secrets, and the history that makes this place special. You're not a textbook — you're the friend everyone wishes they had when visiting.

TASK: Create a ${durationMinutes}-minute driving tour of ${locationName} (${formattedAddress}).

THEMES: ${themesStr}

NEARBY PLACES (use these as candidates, but you may also suggest hidden gems not on this list):
${placesContext}

REQUIREMENTS:
- Select exactly ${stopCount} stops that create a compelling narrative arc (beginning, middle, climax, resolution)
- Mix iconic highlights (60%) with hidden gems (40%)
- Every narration must feel like a knowledgeable local talking to a friend — personal, opinionated, with insider tips
- Include specific visual cues ("look to your left", "notice the blue building")
- Mention the best time to visit, photo opportunities, and where to eat nearby
- Each "between stops" narration should describe what the driver is seeing as they drive through neighborhoods
- Optional stops should be genuinely tempting (great restaurant, scenic viewpoint)
- Stops must be geographically close enough to visit within ${durationMinutes} minutes including driving

RESPOND IN VALID JSON ONLY (no markdown, no code fences):
{
  "title": "A catchy, memorable tour title",
  "description": "2-3 sentence tour description that makes people excited to go",
  "story_arc_summary": "Brief description of the narrative journey",
  "intro_narration": "60-90 second welcome narration — set the scene, build excitement, tell them what they're about to experience (200-300 words)",
  "stops": [
    {
      "name": "Stop name",
      "description": "One-sentence description",
      "category": "landmark|restaurant|viewpoint|hidden-gem|photo-op|park|museum|neighborhood",
      "latitude": 25.7617,
      "longitude": -80.1918,
      "recommended_stay_minutes": 5,
      "is_optional": false,
      "approach_narration": "What to say as driver approaches this stop (100-150 words). Include visual cues and build anticipation.",
      "at_stop_narration": "The main narration at the stop (200-400 words). Rich history, stories, insider tips, what to look for.",
      "departure_narration": "Transitional narration as driver leaves (50-100 words). Tease what's coming next."
    }
  ],
  "between_stop_narrations": [
    "Narration for the drive between stop 1 and stop 2 (100-200 words). Describe neighborhoods, point out things along the way."
  ],
  "outro_narration": "Closing narration (100-150 words). Recap highlights, thank them, suggest what to explore next."
}

Language: ${language}
Ensure all coordinates are accurate for ${locationName}. Do NOT invent places that don't exist.`;

  const result = await model.generateContent(prompt);
  const text = result.response.text().trim();

  // Extract JSON from response — handle code fences, thinking prefixes, etc.
  const jsonStr = extractJson(text);

  try {
    return JSON.parse(jsonStr) as GeminiTourResponse;
  } catch {
    throw new Error(`Failed to parse Gemini response as JSON: ${jsonStr.slice(0, 200)}`);
  }
}

function extractJson(text: string): string {
  // Try 1: Find JSON block in code fences
  const fenceMatch = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/);
  if (fenceMatch) return fenceMatch[1].trim();

  // Try 2: Find the first { and last } to extract the JSON object
  const firstBrace = text.indexOf('{');
  const lastBrace = text.lastIndexOf('}');
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    return text.slice(firstBrace, lastBrace + 1);
  }

  // Try 3: Return as-is
  return text;
}

function getStopCount(durationMinutes: number): number {
  if (durationMinutes <= 30) return 3;
  if (durationMinutes <= 60) return 5;
  if (durationMinutes <= 120) return 7;
  if (durationMinutes <= 180) return 9;
  if (durationMinutes <= 240) return 11;
  return 13;
}
