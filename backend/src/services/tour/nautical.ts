import { env } from '../../config/env.js';

const VC_BASE = 'https://api.vectorcharts.com/api/v1';

interface NauticalRoute {
  distance_nm: number;
  waypoints: Array<[number, number]>;
  chart_url: string;
}

export async function computeNauticalRoute(
  stops: Array<{ latitude: number; longitude: number }>,
): Promise<NauticalRoute> {
  const waypoints: Array<[number, number]> = stops.map((s) => [s.latitude, s.longitude] as [number, number]);

  // Compute route via VectorCharts API
  try {
    const res = await fetch(`${VC_BASE}/routing/route?token=${env.vectorchartsApiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ waypoints }),
    });

    if (res.ok) {
      const data = await res.json() as { distance?: number; route?: unknown };
      const distanceNm = (data.distance ?? 0) / 1852; // meters to nautical miles

      return {
        distance_nm: Math.round(distanceNm * 10) / 10,
        waypoints,
        chart_url: buildChartUrl(waypoints),
      };
    }
  } catch (err) {
    console.error('VectorCharts route error:', err);
  }

  // Fallback: return chart URL without route distance
  return {
    distance_nm: estimateNauticalDistance(stops),
    waypoints: waypoints,
    chart_url: buildChartUrl(waypoints),
  };
}

function buildChartUrl(waypoints: Array<[number, number]>): string {
  // Center on the midpoint of all waypoints
  const lats = waypoints.map(w => w[0]);
  const lngs = waypoints.map(w => w[1]);
  const centerLat = (Math.min(...lats) + Math.max(...lats)) / 2;
  const centerLng = (Math.min(...lngs) + Math.max(...lngs)) / 2;

  // Build a VectorCharts viewer URL with markers
  // VectorCharts provides tile-based charts — we'll use their style endpoint
  // For now, generate an embeddable map URL
  const markers = waypoints.map((w) => `${w[0]},${w[1]}`).join(';');
  return `https://api.vectorcharts.com/api/v1/styles/base.json?token=${env.vectorchartsApiKey}&center=${centerLat},${centerLng}&markers=${markers}`;
}

function estimateNauticalDistance(stops: Array<{ latitude: number; longitude: number }>): number {
  let total = 0;
  for (let i = 1; i < stops.length; i++) {
    total += haversineNm(stops[i - 1].latitude, stops[i - 1].longitude, stops[i].latitude, stops[i].longitude);
  }
  return Math.round(total * 10) / 10;
}

function haversineNm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 3440.065; // Earth radius in nautical miles
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
