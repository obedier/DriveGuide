/**
 * Boat Tour Engine — Dedicated Gemini integration for waterway tours
 *
 * Uses Gemini function calling to query Google Places for verified waterfront
 * locations with docking access. Enforces vessel constraints, quality filtering,
 * and maritime navigation realism.
 */

import { GoogleGenerativeAI, type Tool } from '@google/generative-ai';
import { env } from '../../config/env.js';

const genAI = new GoogleGenerativeAI(env.geminiApiKey);

// ─── Types ───

export interface VesselParams {
  draft_ft: number;       // hull draft in feet (default 5)
  length_ft: number;      // LOA in feet (default 40)
  air_draft_ft: number;   // height above waterline in feet (default 7)
}

export interface BoatTourStop {
  name: string;
  latitude: number;
  longitude: number;
  description: string;
  category: string;
  docking_type: 'slip' | 'linear' | 'anchor' | 'mooring_ball' | 'cruise-by';
  max_vessel_length_ft: number;
  min_water_depth_ft: number;
  rating: number;
  why_premium: string;
  recommended_stay_minutes: number;
  approach_narration: string;
  at_stop_narration: string;
  departure_narration: string;
}

export interface BoatTourResult {
  title: string;
  description: string;
  story_arc_summary: string;
  intro_narration: string;
  outro_narration: string;
  stops: BoatTourStop[];
  between_stop_narrations: string[];
}

// ─── Default vessel params ───

const DEFAULT_VESSEL: VesselParams = {
  draft_ft: 5,
  length_ft: 40,
  air_draft_ft: 7,
};

// ─── System Prompt ───

function buildBoatSystemPrompt(vessel: VesselParams): string {
  return `You are an expert maritime tour guide and captain with 25+ years navigating South Florida waterways. You know every marina, anchorage, waterfront restaurant, and hidden cove. You are also a strict safety officer.

## YOUR ROLE
Create the BEST possible boat tour — the kind a premium yacht charter captain would recommend to impress VIP guests. You know Fort Lauderdale's waterways intimately.

## TWO TYPES OF STOPS

### TYPE 1: DOCK STOPS (tie up and explore)
Where the boat physically docks so passengers can step ashore:
- Marina slips, restaurant face docks, waterfront park docks
- Must have physical docking for the vessel size
- These are restaurants, marinas, waterfront venues

### TYPE 2: CRUISE-BY STOPS (slow down and narrate)
Where the boat slows to idle speed so passengers can admire from the water:
- Millionaire mansions, mega-yachts, historic landmarks visible from the water
- Port Everglades cruise ships, Las Olas Isles canals, Harbor Beach estates
- Sandbars, inlets, scenic channels
- NO docking required — the boat stays in the channel

**MIX RATIO: 40% dock stops, 60% cruise-by stops.** This creates the best tour — passengers want to SEE the famous sights from the water, not just eat at restaurants.

## MUST-INCLUDE ICONIC STOPS (for Fort Lauderdale area)
If the tour is in the Fort Lauderdale area, you MUST include at least 3 of these iconic waterway landmarks:
- **Millionaire's Row / Las Olas Isles** — cruise the canals past mega-mansions and superyachts
- **Port Everglades** — cruise ships, naval vessels, the main shipping channel
- **Bahia Mar Marina** — legendary marina, former home of Travis McGee novels
- **New River / Riverwalk** — historic waterway through downtown
- **Stranahan House** — oldest structure in Fort Lauderdale, viewed from the New River
- **Fort Lauderdale Sandbar** — the famous gathering spot at the inlet
- **Harbor Beach estates** — billionaire waterfront homes
- **Hugh Taylor Birch State Park** — natural beauty from the ICW side

## VESSEL CONSTRAINTS
- **Hull draft**: ${vessel.draft_ft} feet — approach waters must be deeper than this
- **LOA**: ${vessel.length_ft} feet — dock stops must accommodate this length
- **Air draft**: ${vessel.air_draft_ft} feet — fixed bridges must clear this height

Filter out stops requiring passage under fixed bridges too low, or shallow waters.

## QUALITY
- Restaurants/venues should be well-rated (verify via function calls)
- Prioritize stops that are locally famous, unique, or have a compelling story
- Every captain in Fort Lauderdale would recommend these spots

### RULE 4 — NAVIGATION REALISM
- Stops must follow a logical geographic sequence along navigable waterways
- Use ICW (Intracoastal Waterway), rivers, canals, harbor channels — NEVER roads
- Account for no-wake zones: 5 mph (idle speed) in marked zones, marinas, and within 300ft of shore
- Open water: 25-30 mph cruising speed
- DO NOT calculate exact travel times — just sequence stops logically. Our backend will compute actual times.

### RULE 5 — START & END LOCATIONS
The user will specify start and end locations. These are IMMUTABLE:
- First stop in your output MUST be the exact start location
- Last stop in your output MUST be the exact end location
- NEVER change start/end to optimize the route
- If time is tight, remove MIDDLE stops — never alter start/end

### RULE 6 — NARRATION STYLE
You are speaking to someone ON A BOAT. Your narration must:
- Use nautical references: "starboard side", "port side", "as we cruise past", "dead ahead"
- Describe what's visible FROM THE WATER: mansions, yachts, bridges, birds, marine life
- Include local boating lore, maritime history, and captain's insider tips
- Never mention driving, parking, or walking to a location
- Reference water features: channels, cuts, inlets, sandbars, shoals, tidal flow

## FUNCTION CALLING
You have access to a function 'search_waterfront_places' to find real, verified waterfront venues. USE IT for every stop to verify the location exists, has good ratings, and is genuinely waterfront. Do not rely on your training data alone.

## OUTPUT FORMAT
Return a valid JSON object (no markdown fences). Coordinates must be ON THE WATER or at the dock/waterfront edge.`;
}

// ─── Function declarations for Gemini ───

const placeSearchTool: Tool = {
  functionDeclarations: [{
    name: 'search_waterfront_places',
    description: 'Search for waterfront places near a location. Returns real Google Places data with ratings, coordinates, and types. Use this to verify that recommended stops actually exist and are genuinely waterfront.',
    parameters: {
      type: 'OBJECT' as const,
      properties: {
        latitude: { type: 'NUMBER' as const, description: 'Center latitude for search' },
        longitude: { type: 'NUMBER' as const, description: 'Center longitude for search' },
        query: { type: 'STRING' as const, description: 'Search query, e.g. "waterfront restaurant with dock" or "marina" or "yacht club"' },
        radius_meters: { type: 'NUMBER' as const, description: 'Search radius in meters (default 3000)' },
      },
      required: ['latitude', 'longitude', 'query'],
    } as never,
  }],
} as Tool;

// ─── Function call handler ───

async function handleFunctionCall(
  name: string,
  args: Record<string, unknown>,
): Promise<string> {
  if (name === 'search_waterfront_places') {
    const lat = args.latitude as number;
    const lng = args.longitude as number;
    const query = args.query as string;
    const radius = (args.radius_meters as number) || 3000;

    // Use Google Places text search for more specific queries
    const url = `https://maps.googleapis.com/maps/api/place/textsearch/json?query=${encodeURIComponent(query)}&location=${lat},${lng}&radius=${radius}&key=${env.googleMapsKey}`;
    const res = await fetch(url);
    const data = await res.json() as {
      results: Array<{
        name: string;
        geometry: { location: { lat: number; lng: number } };
        rating?: number;
        user_ratings_total?: number;
        formatted_address?: string;
        types?: string[];
        business_status?: string;
      }>;
    };

    const results = (data.results || [])
      .filter((p) => p.business_status !== 'CLOSED_PERMANENTLY')
      .slice(0, 8)
      .map((p) => ({
        name: p.name,
        latitude: p.geometry.location.lat,
        longitude: p.geometry.location.lng,
        rating: p.rating ?? 0,
        total_reviews: p.user_ratings_total ?? 0,
        address: p.formatted_address ?? '',
        types: (p.types ?? []).slice(0, 5),
      }));

    return JSON.stringify(results);
  }

  return JSON.stringify({ error: 'Unknown function' });
}

// ─── Main generator ───

export async function generateBoatTour(
  locationName: string,
  formattedAddress: string,
  _centerLat: number,
  _centerLng: number,
  durationMinutes: number,
  startLocation: string | null,
  endLocation: string | null,
  customPrompt: string | null,
  vessel: VesselParams = DEFAULT_VESSEL,
): Promise<BoatTourResult> {
  const model = genAI.getGenerativeModel({
    model: 'gemini-2.5-flash',
    systemInstruction: buildBoatSystemPrompt(vessel),
    tools: [placeSearchTool],
  });

  const stopCount = getBoatStopCount(durationMinutes);
  const startNote = startLocation ? `START LOCATION (immutable): "${startLocation}"` : `START: Nearest public marina/dock to ${locationName}`;
  const endNote = endLocation ? `END LOCATION (immutable): "${endLocation}"` : `END: Return to start location (round trip)`;
  const customNote = customPrompt ? `\nSPECIAL REQUESTS: ${customPrompt}` : '';

  const userPrompt = `Create a ${durationMinutes}-minute boat tour in the ${locationName} area (${formattedAddress}).

${startNote}
${endNote}
${customNote}

VESSEL: ${vessel.length_ft}ft LOA, ${vessel.draft_ft}ft draft, ${vessel.air_draft_ft}ft air draft

Select ${stopCount} stops total (including start and end).

IMPORTANT: Use the search_waterfront_places function to find and verify REAL waterfront venues with docking access. Search for marinas, waterfront restaurants with docks, yacht clubs, and waterside parks with boat access.

Return valid JSON only (no code fences):
{
  "title": "Catchy nautical tour title",
  "description": "2-3 sentence description from a captain's perspective",
  "story_arc_summary": "Brief narrative arc of the waterway journey",
  "intro_narration": "Welcome aboard narration (200-300 words). Set the scene on the water.",
  "stops": [
    {
      "name": "Location name",
      "latitude": 26.1234,
      "longitude": -80.1234,
      "description": "One sentence",
      "category": "marina|waterfront-restaurant|yacht-club|anchorage|waterfront-park|landmark-from-water",
      "docking_type": "slip|linear|anchor|mooring_ball|cruise-by",
      "max_vessel_length_ft": 60,
      "min_water_depth_ft": 8,
      "rating": 4.7,
      "why_premium": "Why this stop is worth visiting by boat",
      "recommended_stay_minutes": 15,
      "approach_narration": "What captain sees approaching by water (100-150 words)",
      "at_stop_narration": "Main narration at this stop (200-400 words)",
      "departure_narration": "Transitional narration departing by water (50-100 words)"
    }
  ],
  "between_stop_narrations": ["Narration for waterway passage between stops (100-200 words each)"],
  "outro_narration": "Closing narration as you return to dock (100-150 words)"
}`;

  // Start chat with function calling
  const chat = model.startChat();
  let response = await chat.sendMessage(userPrompt);

  // Handle function calls (Gemini may call search_waterfront_places multiple times)
  let iterations = 0;
  const MAX_ITERATIONS = 10;

  while (response.response.candidates?.[0]?.content?.parts?.some(p => 'functionCall' in p) && iterations < MAX_ITERATIONS) {
    iterations++;
    const functionCalls = response.response.candidates[0].content.parts.filter(p => 'functionCall' in p);

    const functionResponses = [];
    for (const part of functionCalls) {
      const fc = (part as { functionCall: { name: string; args: Record<string, unknown> } }).functionCall;
      console.log(`[BoatEngine] Function call #${iterations}: ${fc.name}(${JSON.stringify(fc.args).slice(0, 100)})`);
      const result = await handleFunctionCall(fc.name, fc.args);
      functionResponses.push({
        functionResponse: { name: fc.name, response: { result } },
      });
    }

    response = await chat.sendMessage(functionResponses);
  }

  // Extract final text response
  const text = response.response.text().trim();
  const jsonStr = extractJson(text);

  try {
    return JSON.parse(jsonStr) as BoatTourResult;
  } catch {
    throw new Error(`Failed to parse boat tour JSON: ${jsonStr.slice(0, 300)}`);
  }
}

// ─── Maritime distance calculation ───

export function calculateMaritimeSegments(
  stops: Array<{ latitude: number; longitude: number }>,
): Array<{ distance_nm: number; estimated_minutes: number }> {
  const segments = [];
  for (let i = 1; i < stops.length; i++) {
    const distNm = haversineNm(
      stops[i - 1].latitude, stops[i - 1].longitude,
      stops[i].latitude, stops[i].longitude,
    );

    // Estimate time: assume mix of no-wake (5mph) and open water (25mph)
    // Short legs (<1nm) are mostly no-wake, longer legs are mostly open water
    const avgSpeedKnots = distNm < 1 ? 5 : distNm < 3 ? 12 : 20;
    const minutes = Math.ceil((distNm / avgSpeedKnots) * 60);

    segments.push({ distance_nm: Math.round(distNm * 100) / 100, estimated_minutes: minutes });
  }
  return segments;
}

function haversineNm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 3440.065;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function getBoatStopCount(durationMinutes: number): number {
  if (durationMinutes <= 60) return 4;
  if (durationMinutes <= 120) return 6;
  if (durationMinutes <= 180) return 8;
  return 10;
}

function extractJson(text: string): string {
  const fenceMatch = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/);
  if (fenceMatch) return fenceMatch[1].trim();
  const firstBrace = text.indexOf('{');
  const lastBrace = text.lastIndexOf('}');
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    return text.slice(firstBrace, lastBrace + 1);
  }
  return text;
}
