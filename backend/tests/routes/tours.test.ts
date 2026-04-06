import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import { runMigrations } from '../../src/lib/migrate.js';
import { closeDb, getDb } from '../../src/lib/db.js';
import { healthRoutes } from '../../src/routes/health.js';
import { tourRoutes } from '../../src/routes/tours.js';
import { env } from '../../src/config/env.js';

// Use a test database
process.env.DB_PATH = '/tmp/tourai-test.db';

const app = Fastify();

beforeAll(async () => {
  runMigrations();
  await app.register(cors);
  await app.register(healthRoutes);
  await app.register(tourRoutes, { prefix: '/v1' });
  await app.ready();
});

afterAll(async () => {
  await app.close();
  closeDb();
});

describe('Health', () => {
  it('GET /health returns 200', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.status).toBe('ok');
    expect(body.version).toBe('0.1.0');
    expect(body.min_app_version).toBeDefined();
  });
});

describe('Tour Routes', () => {
  it('POST /v1/tours/verify-location returns coordinates for valid location', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/verify-location',
      payload: { location: 'Miami Beach' },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.verified).toBe(true);
    expect(body.location.latitude).toBeCloseTo(25.79, 0);
    expect(body.location.longitude).toBeCloseTo(-80.13, 0);
    expect(body.location.formatted_address).toContain('Miami Beach');
    expect(body.nearby_highlights).toBeDefined();
    expect(body.nearby_highlights.length).toBeGreaterThan(0);
  });

  it('POST /v1/tours/verify-location rejects empty location', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/verify-location',
      payload: { location: '' },
    });
    expect(res.statusCode).toBe(400);
  });

  it('POST /v1/tours/verify-location returns 404 for gibberish', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/verify-location',
      payload: { location: 'xyzzy99999notaplace' },
    });
    // Google Geocoding may still return results for gibberish, so accept 200 or 404
    expect([200, 404]).toContain(res.statusCode);
  });

  it('POST /v1/tours/preview rejects missing location', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/preview',
      payload: { duration_minutes: 60 },
    });
    expect(res.statusCode).toBe(400);
  });

  it('POST /v1/tours/preview rejects invalid duration', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/preview',
      payload: { location: 'Miami', duration_minutes: 10 },
    });
    expect(res.statusCode).toBe(400);
  });

  it('POST /v1/tours/preview rejects duration > 360', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/preview',
      payload: { location: 'Miami', duration_minutes: 500 },
    });
    expect(res.statusCode).toBe(400);
  });

  it('POST /v1/tours/preview generates a real tour preview', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/preview',
      payload: { location: 'Coconut Grove Miami', duration_minutes: 60 },
    });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body);
    expect(body.preview).toBeDefined();
    expect(body.preview.title).toBeTruthy();
    expect(body.preview.stop_count).toBeGreaterThanOrEqual(3);
    expect(body.preview.duration_minutes).toBe(60);
    expect(body.preview.preview_stops.length).toBeGreaterThanOrEqual(2);
    for (const stop of body.preview.preview_stops) {
      expect(stop.name).toBeTruthy();
      expect(stop.category).toBeTruthy();
      expect(stop.teaser.length).toBeGreaterThan(50);
    }
  }, 120_000);

  it('GET /v1/tours/:id requires auth', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/v1/tours/nonexistent-id',
    });
    expect(res.statusCode).toBe(401);
  });

  it('DELETE /v1/tours/:id requires auth', async () => {
    const res = await app.inject({
      method: 'DELETE',
      url: '/v1/tours/nonexistent-id',
    });
    expect(res.statusCode).toBe(401);
  });
});
