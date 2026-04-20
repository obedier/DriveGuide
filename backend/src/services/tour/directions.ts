// Google Directions API helper for real drive/walk ETAs. Preferred over
// Haversine distance for bridge narration since it accounts for roads,
// traffic, and realistic travel time.
//
// Fails gracefully — returns `null` when the API is unreachable, over
// quota, or returns an error status. The caller falls back to Haversine.

import { env } from '../../config/env.js';

export interface DirectionsEtaRequest {
  originLat: number;
  originLng: number;
  destLat: number;
  destLng: number;
  transportMode: string;
}

/**
 * Returns the real driving/walking/cycling ETA in minutes, or null on any
 * error. Uses the Google Directions API with the project's shared key.
 */
export async function fetchDirectionsEta(req: DirectionsEtaRequest): Promise<number | null> {
  const key = env.googleMapsKey;
  if (!key) return null;

  const mode = directionsModeFor(req.transportMode);
  const params = new URLSearchParams({
    origin: `${req.originLat},${req.originLng}`,
    destination: `${req.destLat},${req.destLng}`,
    mode,
    departure_time: 'now',  // lets Directions account for current traffic
    key,
  });
  const url = `https://maps.googleapis.com/maps/api/directions/json?${params.toString()}`;

  try {
    const res = await fetch(url, { method: 'GET' });
    if (!res.ok) return null;
    const body = await res.json() as {
      status: string;
      routes?: Array<{ legs?: Array<{
        duration?: { value: number };
        duration_in_traffic?: { value: number };
      }> }>;
    };
    if (body.status !== 'OK') return null;
    const leg = body.routes?.[0]?.legs?.[0];
    if (!leg) return null;
    // duration_in_traffic is populated for driving with departure_time; else fall back to duration.
    const seconds = leg.duration_in_traffic?.value ?? leg.duration?.value;
    if (typeof seconds !== 'number' || seconds <= 0) return null;
    return Math.max(1, Math.round(seconds / 60));
  } catch {
    return null;
  }
}

function directionsModeFor(transport: string): string {
  switch (transport) {
    case 'walk': return 'walking';
    case 'bike': return 'bicycling';
    case 'plane': return 'driving'; // no plane mode; approximate with car ETA
    case 'boat': return 'driving';
    default: return 'driving';
  }
}
