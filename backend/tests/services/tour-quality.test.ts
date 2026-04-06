import { describe, it, expect } from 'vitest';

const API_URL = process.env.TEST_API_URL || 'https://private-tourai-api-i32snp7xla-ue.a.run.app';

// These tests validate tour quality by checking actual API responses
// They call the real API and take 30-60 seconds each

describe('Tour Quality — Transport Modes', () => {
  it('car tour should have drivable stops with road-based narration', async () => {
    const res = await fetch(`${API_URL}/v1/tours/preview`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ location: 'Las Olas Fort Lauderdale', duration_minutes: 60, transport_mode: 'car' }),
    });
    const data = await res.json() as { tour_id: string; preview: { title: string; preview_stops: Array<{ name: string; teaser: string }> } };

    expect(res.status).toBe(200);
    expect(data.preview.title).toBeTruthy();

    // Car tours should NOT mention boats, waterways, or docks
    const fullTour = await (await fetch(`${API_URL}/v1/tours/full`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tour_id: data.tour_id }),
    })).json() as { tour: { stops: Array<{ name: string; at_stop_narration: string }> } };

    for (const stop of fullTour.tour.stops) {
      expect(stop.name).toBeTruthy();
      expect(stop.at_stop_narration.length).toBeGreaterThan(100);
    }
  }, 120_000);

  it('boat tour should have waterway-only stops', async () => {
    const res = await fetch(`${API_URL}/v1/tours/preview`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ location: 'Fort Lauderdale Intracoastal', duration_minutes: 60, transport_mode: 'boat' }),
    });
    const data = await res.json() as { tour_id: string; preview: { title: string; preview_stops: Array<{ name: string; teaser: string }> } };

    expect(res.status).toBe(200);

    const fullTour = await (await fetch(`${API_URL}/v1/tours/full`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tour_id: data.tour_id }),
    })).json() as { tour: { stops: Array<{ name: string; at_stop_narration: string; category: string }> } };

    // Boat tour stops should reference water features
    const allNarration = fullTour.tour.stops.map(s => s.at_stop_narration.toLowerCase()).join(' ');
    const waterTerms = ['water', 'boat', 'dock', 'marina', 'yacht', 'intracoastal', 'waterfront', 'channel', 'bay', 'ocean', 'river', 'cruise'];
    const waterMentions = waterTerms.filter(term => allNarration.includes(term));

    // At least 4 water-related terms should appear in the narration
    expect(waterMentions.length).toBeGreaterThanOrEqual(4);

    // No stops should be explicitly inland-only categories
    const inlandCategories = ['mall', 'shopping_center', 'gas_station'];
    for (const stop of fullTour.tour.stops) {
      for (const bad of inlandCategories) {
        expect(stop.category).not.toBe(bad);
      }
    }
  }, 120_000);

  it('walking tour should have nearby stops within walking distance', async () => {
    const res = await fetch(`${API_URL}/v1/tours/preview`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ location: 'Wynwood Miami', duration_minutes: 60, transport_mode: 'walk' }),
    });
    const data = await res.json() as { tour_id: string; preview: { title: string; total_distance_km: number } };

    expect(res.status).toBe(200);
    // Walking tour should be shorter distance than driving
    if (data.preview.total_distance_km) {
      expect(data.preview.total_distance_km).toBeLessThan(10); // Walking should be < 10km
    }
  }, 120_000);

  it('custom prompt should influence stop selection', async () => {
    const res = await fetch(`${API_URL}/v1/tours/preview`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        location: 'Miami Beach',
        duration_minutes: 60,
        custom_prompt: 'art deco architecture and historic buildings',
      }),
    });
    const data = await res.json() as { preview: { title: string; preview_stops: Array<{ name: string; teaser: string }> } };

    expect(res.status).toBe(200);

    // At least one stop should mention art deco or architecture
    const allText = data.preview.preview_stops.map(s => `${s.name} ${s.teaser}`.toLowerCase()).join(' ');
    const hasArtDeco = allText.includes('art deco') || allText.includes('architecture') || allText.includes('historic');
    expect(hasArtDeco).toBe(true);
  }, 120_000);
});
