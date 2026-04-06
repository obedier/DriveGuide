import { env } from '../../config/env.js';

const MAPS_BASE = 'https://maps.googleapis.com/maps/api';

interface GeocodingResult {
  latitude: number;
  longitude: number;
  formatted_address: string;
}

interface NearbyPlace {
  place_id: string;
  name: string;
  latitude: number;
  longitude: number;
  types: string[];
  rating?: number;
  vicinity?: string;
}

interface DirectionsLeg {
  distance_km: number;
  duration_minutes: number;
  start_lat: number;
  start_lng: number;
  end_lat: number;
  end_lng: number;
  polyline: string;
}

export interface OptimizedRoute {
  legs: DirectionsLeg[];
  waypoint_order: number[];
  total_distance_km: number;
  total_duration_minutes: number;
  overview_polyline: string;
  directions_url: string;
}

export async function geocode(address: string): Promise<GeocodingResult> {
  const url = `${MAPS_BASE}/geocode/json?address=${encodeURIComponent(address)}&key=${env.googleMapsKey}`;
  const res = await fetch(url);
  const data = await res.json() as { status: string; results: Array<{ geometry: { location: { lat: number; lng: number } }; formatted_address: string }> };

  if (data.status !== 'OK' || !data.results[0]) {
    throw new Error(`Geocoding failed for "${address}": ${data.status}`);
  }

  const loc = data.results[0].geometry.location;
  return {
    latitude: loc.lat,
    longitude: loc.lng,
    formatted_address: data.results[0].formatted_address,
  };
}

export async function nearbySearch(
  lat: number,
  lng: number,
  radiusMeters: number = 5000,
  types: string[] = ['tourist_attraction', 'point_of_interest', 'museum', 'park'],
): Promise<NearbyPlace[]> {
  const allPlaces: NearbyPlace[] = [];

  for (const type of types) {
    const url = `${MAPS_BASE}/place/nearbysearch/json?location=${lat},${lng}&radius=${radiusMeters}&type=${type}&key=${env.googleMapsKey}`;
    const res = await fetch(url);
    const data = await res.json() as { results: Array<{ place_id: string; name: string; geometry: { location: { lat: number; lng: number } }; types: string[]; rating?: number; vicinity?: string }> };

    for (const place of data.results || []) {
      if (!allPlaces.some((p) => p.place_id === place.place_id)) {
        allPlaces.push({
          place_id: place.place_id,
          name: place.name,
          latitude: place.geometry.location.lat,
          longitude: place.geometry.location.lng,
          types: place.types,
          rating: place.rating,
          vicinity: place.vicinity,
        });
      }
    }
  }

  return allPlaces.sort((a, b) => (b.rating ?? 0) - (a.rating ?? 0));
}

export async function getPlacePhoto(placeId: string): Promise<string | null> {
  const detailUrl = `${MAPS_BASE}/place/details/json?place_id=${placeId}&fields=photos&key=${env.googleMapsKey}`;
  const res = await fetch(detailUrl);
  const data = await res.json() as { result?: { photos?: Array<{ photo_reference: string }> } };
  const photoRef = data.result?.photos?.[0]?.photo_reference;
  if (!photoRef) return null;
  return `${MAPS_BASE}/place/photo?maxwidth=600&photo_reference=${photoRef}&key=${env.googleMapsKey}`;
}

type GoogleTravelMode = 'driving' | 'walking' | 'bicycling' | 'transit';

function toGoogleTravelMode(mode: string): GoogleTravelMode {
  switch (mode) {
    case 'walk': return 'walking';
    case 'bike': return 'bicycling';
    case 'boat': return 'driving'; // no boat mode in Google, use driving
    case 'plane': return 'driving'; // approximate with driving
    default: return 'driving';
  }
}

function toMapsTravelMode(mode: string): string {
  switch (mode) {
    case 'walk': return 'walking';
    case 'bike': return 'bicycling';
    default: return 'driving';
  }
}

export async function optimizeRoute(
  origin: { lat: number; lng: number },
  destination: { lat: number; lng: number },
  waypoints: Array<{ lat: number; lng: number }>,
  transportMode: string = 'car',
): Promise<OptimizedRoute> {
  const waypointsParam = waypoints
    .map((w) => `${w.lat},${w.lng}`)
    .join('|');

  const travelMode = toGoogleTravelMode(transportMode);
  const url = `${MAPS_BASE}/directions/json?origin=${origin.lat},${origin.lng}&destination=${destination.lat},${destination.lng}&waypoints=optimize:true|${waypointsParam}&mode=${travelMode}&key=${env.googleMapsKey}`;

  const res = await fetch(url);
  const data = await res.json() as {
    status: string;
    geocoded_waypoints: unknown[];
    routes: Array<{
      legs: Array<{
        distance: { value: number };
        duration: { value: number };
        start_location: { lat: number; lng: number };
        end_location: { lat: number; lng: number };
        steps: Array<{ polyline: { points: string } }>;
      }>;
      waypoint_order: number[];
      overview_polyline: { points: string };
    }>;
  };

  if (data.status !== 'OK' || !data.routes[0]) {
    throw new Error(`Directions failed: ${data.status}`);
  }

  const route = data.routes[0];
  const legs: DirectionsLeg[] = route.legs.map((leg) => ({
    distance_km: leg.distance.value / 1000,
    duration_minutes: Math.ceil(leg.duration.value / 60),
    start_lat: leg.start_location.lat,
    start_lng: leg.start_location.lng,
    end_lat: leg.end_location.lat,
    end_lng: leg.end_location.lng,
    polyline: leg.steps.map((s) => s.polyline.points).join(''),
  }));

  const totalDistance = legs.reduce((sum, l) => sum + l.distance_km, 0);
  const totalDuration = legs.reduce((sum, l) => sum + l.duration_minutes, 0);

  // Build Google Maps multi-stop URL
  const orderedWaypoints = route.waypoint_order.map((i) => waypoints[i]);
  const allPoints = [origin, ...orderedWaypoints, destination];
  const mapsUrl = buildMapsUrl(allPoints, transportMode);

  return {
    legs,
    waypoint_order: route.waypoint_order,
    total_distance_km: Math.round(totalDistance * 10) / 10,
    total_duration_minutes: totalDuration,
    overview_polyline: route.overview_polyline.points,
    directions_url: mapsUrl,
  };
}

function buildMapsUrl(points: Array<{ lat: number; lng: number }>, transportMode: string = 'car'): string {
  if (points.length < 2) return '';
  const origin = points[0];
  const destination = points[points.length - 1];
  const waypoints = points.slice(1, -1);

  let url = `https://www.google.com/maps/dir/?api=1&origin=${origin.lat},${origin.lng}&destination=${destination.lat},${destination.lng}`;

  if (waypoints.length > 0) {
    const wp = waypoints.map((w) => `${w.lat},${w.lng}`).join('|');
    url += `&waypoints=${wp}`;
  }

  url += `&travelmode=${toMapsTravelMode(transportMode)}`;
  return url;
}
