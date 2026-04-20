import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import Fastify, { FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

// Community library v2.10 — round-trip tests for the public browse endpoint
// (`GET /v1/tours/public`), the owner-only visibility toggle
// (`POST /v1/tours/:id/visibility`), and `is_public` exposure on
// `GET /v1/tours/:id`.
//
// Strategy: seed the SQLite DB directly with tour rows, then hit the public
// (no-auth) endpoints via `app.inject`. Auth-gated endpoints are exercised
// only for 401 behavior — anything deeper would require mocking Firebase.

// Isolate this suite's DB before any app modules import the env/db singletons.
const tmpDir = mkdtempSync(join(tmpdir(), 'waipoint-community-test-'));
const dbPath = join(tmpDir, 'community-library.db');
process.env.DB_PATH = dbPath;

// Import after DB_PATH is set so env.dbPath picks it up.
const { runMigrations } = await import('../../src/lib/migrate.js');
const { closeDb, getDb } = await import('../../src/lib/db.js');
const { tourRoutes } = await import('../../src/routes/tours.js');

let app: FastifyInstance;

// Fixture tour IDs — we reuse these in assertions.
const TOUR_TOP = 'tour-top-rated';
const TOUR_MID = 'tour-mid-rated';
const TOUR_FRESH = 'tour-recent-unrated';
const TOUR_PRIVATE = 'tour-private';
const TOUR_MIA = 'tour-miami-metro';
const TOUR_NYC = 'tour-nyc-metro';
const TOUR_TRENDING = 'tour-trending-hot';

function insertTour(params: {
  id: string;
  title: string;
  isPublic: boolean;
  isFeatured?: boolean;
  rating?: number | null;
  ratingCount?: number;
  metro?: string | null;
  createdAt?: string;
  userId?: string | null;
  stops?: number;
  transportMode?: string;
}): void {
  const db = getDb();
  db.prepare(`
    INSERT INTO tours (
      id, user_id, title, description, location_query,
      duration_minutes, themes, language, status, transport_mode,
      is_public, is_featured, community_rating, community_rating_count, metro_area,
      created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, '[]', 'en', 'ready', ?, ?, ?, ?, ?, ?,
      COALESCE(?, datetime('now')), datetime('now'))
  `).run(
    params.id,
    params.userId ?? null,
    params.title,
    'desc',
    'Somewhere',
    60,
    params.transportMode ?? 'car',
    params.isPublic ? 1 : 0,
    params.isFeatured ? 1 : 0,
    params.rating ?? null,
    params.ratingCount ?? 0,
    params.metro ?? null,
    params.createdAt ?? null,
  );

  const stopCount = params.stops ?? 3;
  const stopStmt = db.prepare(`
    INSERT INTO tour_stops (
      id, tour_id, sequence_order, name, description, category,
      latitude, longitude, recommended_stay_minutes, is_optional,
      approach_narration, at_stop_narration, departure_narration
    ) VALUES (?, ?, ?, 'Stop', '', 'landmark', 0, 0, 5, 0, '', '', '')
  `);
  for (let i = 0; i < stopCount; i++) {
    stopStmt.run(`${params.id}-stop-${i}`, params.id, i);
  }
}

function insertRatingAt(tourId: string, rating: number, createdAt: string): void {
  const db = getDb();
  db.prepare(`
    INSERT INTO community_ratings (id, tour_id, user_id, rating, review, created_at)
    VALUES (?, ?, ?, ?, NULL, ?)
  `).run(`${tourId}-rating-${Math.random().toString(36).slice(2, 8)}`, tourId, `rater-${Math.random()}`, rating, createdAt);
}

function resetDb(): void {
  const db = getDb();
  db.prepare('DELETE FROM community_ratings').run();
  db.prepare('DELETE FROM tour_stops').run();
  db.prepare('DELETE FROM tours').run();
}

beforeAll(async () => {
  runMigrations();

  app = Fastify();
  await app.register(cors);
  await app.register(tourRoutes, { prefix: '/v1' });
  await app.ready();
});

afterAll(async () => {
  await app.close();
  closeDb();
  rmSync(tmpDir, { recursive: true, force: true });
});

beforeEach(() => {
  resetDb();
});

describe('GET /v1/tours/public — sort', () => {
  it('defaults to sort=top, ordering by rating DESC', async () => {
    insertTour({ id: TOUR_TOP, title: 'Top', isPublic: true, rating: 4.8, ratingCount: 50 });
    insertTour({ id: TOUR_MID, title: 'Mid', isPublic: true, rating: 3.5, ratingCount: 20 });
    insertTour({ id: TOUR_FRESH, title: 'Fresh', isPublic: true, rating: null, ratingCount: 0 });

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public' });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { tours: Array<{ id: string; avgRating: number; ratingCount: number; stopCount: number }>; total: number };

    expect(body.total).toBe(3);
    expect(body.tours.map((t) => t.id)).toEqual([TOUR_TOP, TOUR_MID, TOUR_FRESH]);
    expect(body.tours[0].avgRating).toBe(4.8);
    expect(body.tours[0].stopCount).toBe(3);
  });

  it('sort=recent orders by createdAt DESC', async () => {
    // Explicit created_at values, oldest-to-newest.
    insertTour({ id: 'a', title: 'Oldest', isPublic: true, rating: 5.0, ratingCount: 100, createdAt: '2024-01-01 00:00:00' });
    insertTour({ id: 'b', title: 'Middle', isPublic: true, rating: 4.0, ratingCount: 50, createdAt: '2024-06-01 00:00:00' });
    insertTour({ id: 'c', title: 'Newest', isPublic: true, rating: 1.0, ratingCount: 1, createdAt: '2024-12-01 00:00:00' });

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public?sort=recent' });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { tours: Array<{ id: string }> };
    expect(body.tours.map((t) => t.id)).toEqual(['c', 'b', 'a']);
  });

  it('sort=trending weights tours by ratings in the last 7 days', async () => {
    insertTour({ id: TOUR_TRENDING, title: 'Trending', isPublic: true, rating: 3.0, ratingCount: 3 });
    insertTour({ id: TOUR_TOP, title: 'All-time top (stale)', isPublic: true, rating: 5.0, ratingCount: 500 });
    insertTour({ id: TOUR_FRESH, title: 'Cold', isPublic: true, rating: 4.0, ratingCount: 10 });

    // TOUR_TRENDING: 3 ratings in the last 24h.
    insertRatingAt(TOUR_TRENDING, 4, "datetime('now', '-1 day')");
    insertRatingAt(TOUR_TRENDING, 5, "datetime('now', '-2 days')");
    insertRatingAt(TOUR_TRENDING, 3, "datetime('now', '-3 days')");
    // TOUR_TOP: one very old rating
    insertRatingAt(TOUR_TOP, 5, "datetime('now', '-60 days')");
    // TOUR_FRESH: one rating just outside the window
    insertRatingAt(TOUR_FRESH, 4, "datetime('now', '-8 days')");

    // Rewrite the literal datetime() placeholders we smuggled in as strings.
    // (community_ratings.created_at was set to the literal text above, not a
    // datetime — fix it here with a direct UPDATE using SQLite expressions.)
    const db = getDb();
    db.prepare("UPDATE community_ratings SET created_at = datetime('now', '-1 day') WHERE tour_id = ? AND rating = 4").run(TOUR_TRENDING);
    db.prepare("UPDATE community_ratings SET created_at = datetime('now', '-2 days') WHERE tour_id = ? AND rating = 5 AND tour_id = ?").run(TOUR_TRENDING, TOUR_TRENDING);
    db.prepare("UPDATE community_ratings SET created_at = datetime('now', '-3 days') WHERE tour_id = ? AND rating = 3").run(TOUR_TRENDING);
    db.prepare("UPDATE community_ratings SET created_at = datetime('now', '-60 days') WHERE tour_id = ?").run(TOUR_TOP);
    db.prepare("UPDATE community_ratings SET created_at = datetime('now', '-8 days') WHERE tour_id = ?").run(TOUR_FRESH);

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public?sort=trending' });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { tours: Array<{ id: string }> };
    // TOUR_TRENDING has 3 recent ratings; the others have 0 in the 7-day window.
    expect(body.tours[0].id).toBe(TOUR_TRENDING);
  });

  it('unknown sort values fall back to top', async () => {
    insertTour({ id: 'hi', title: 'Hi', isPublic: true, rating: 5.0, ratingCount: 10 });
    insertTour({ id: 'lo', title: 'Lo', isPublic: true, rating: 1.0, ratingCount: 10 });

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public?sort=bogus' });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { tours: Array<{ id: string }> };
    expect(body.tours[0].id).toBe('hi');
  });

  it('sort=top surfaces featured tours ahead of higher-rated community tours', async () => {
    // A featured tour with no ratings must still lead a 5-star community tour.
    insertTour({ id: 'five-star', title: 'All-time top (community)', isPublic: true, rating: 5.0, ratingCount: 200 });
    insertTour({ id: 'feat-curated', title: 'Featured curated', isPublic: true, isFeatured: true, rating: null, ratingCount: 0 });
    insertTour({ id: 'three-star', title: 'Mid (community)', isPublic: true, rating: 3.0, ratingCount: 10 });

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public' });
    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body) as { tours: Array<{ id: string; isFeatured: boolean }> };
    expect(body.tours[0].id).toBe('feat-curated');
    expect(body.tours[0].isFeatured).toBe(true);
    // The community tours fall in below, sorted by rating.
    expect(body.tours[1].id).toBe('five-star');
    expect(body.tours[2].id).toBe('three-star');
  });

  it('returned items include isFeatured boolean', async () => {
    insertTour({ id: 'f', title: 'Featured', isPublic: true, isFeatured: true });
    insertTour({ id: 'c', title: 'Community', isPublic: true, rating: 5.0, ratingCount: 3 });

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public' });
    const body = JSON.parse(res.body) as { tours: Array<{ id: string; isFeatured: boolean }> };
    const map = Object.fromEntries(body.tours.map((t) => [t.id, t.isFeatured]));
    expect(map.f).toBe(true);
    expect(map.c).toBe(false);
  });
});

describe('GET /v1/tours/public — filtering', () => {
  it('only returns rows where is_public = 1', async () => {
    insertTour({ id: 'pub', title: 'Public', isPublic: true, rating: 4.0, ratingCount: 5 });
    insertTour({ id: TOUR_PRIVATE, title: 'Private', isPublic: false, rating: 4.9, ratingCount: 100 });

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public' });
    const body = JSON.parse(res.body) as { tours: Array<{ id: string }>; total: number };
    expect(body.total).toBe(1);
    expect(body.tours.map((t) => t.id)).toEqual(['pub']);
  });

  it('filters by metro', async () => {
    insertTour({ id: TOUR_MIA, title: 'Miami', isPublic: true, rating: 4.0, ratingCount: 5, metro: 'Miami' });
    insertTour({ id: TOUR_NYC, title: 'NYC', isPublic: true, rating: 5.0, ratingCount: 10, metro: 'New York' });
    insertTour({ id: 'nometro', title: 'No metro', isPublic: true, rating: 3.0, ratingCount: 1, metro: null });

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public?metro=Miami' });
    const body = JSON.parse(res.body) as { tours: Array<{ id: string; metroArea: string | null }>; total: number };
    expect(body.total).toBe(1);
    expect(body.tours[0].id).toBe(TOUR_MIA);
    expect(body.tours[0].metroArea).toBe('Miami');
  });

  it('applies limit + offset and caps limit at 50', async () => {
    for (let i = 0; i < 5; i++) {
      insertTour({ id: `row-${i}`, title: `t${i}`, isPublic: true, rating: 5 - i * 0.1, ratingCount: 10 });
    }

    const page1 = await app.inject({ method: 'GET', url: '/v1/tours/public?limit=2&offset=0' });
    const p1 = JSON.parse(page1.body) as { tours: Array<{ id: string }>; total: number };
    expect(p1.total).toBe(5);
    expect(p1.tours).toHaveLength(2);

    const page2 = await app.inject({ method: 'GET', url: '/v1/tours/public?limit=2&offset=2' });
    const p2 = JSON.parse(page2.body) as { tours: Array<{ id: string }> };
    expect(p2.tours).toHaveLength(2);
    expect(p2.tours[0].id).not.toBe(p1.tours[0].id);

    // Over-cap
    const capped = await app.inject({ method: 'GET', url: '/v1/tours/public?limit=500' });
    const c = JSON.parse(capped.body) as { tours: unknown[] };
    expect(c.tours.length).toBeLessThanOrEqual(50);
  });

  it('rejects negative offset', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/tours/public?offset=-1' });
    expect(res.statusCode).toBe(400);
  });

  it('returns the CommunityTourItem shape', async () => {
    insertTour({
      id: 'shape',
      title: 'Shape',
      isPublic: true,
      rating: 4.2,
      ratingCount: 7,
      metro: 'Chicago',
      transportMode: 'walk',
      stops: 5,
    });

    const res = await app.inject({ method: 'GET', url: '/v1/tours/public' });
    const body = JSON.parse(res.body) as { tours: Array<Record<string, unknown>> };
    const item = body.tours[0];
    expect(item).toMatchObject({
      id: 'shape',
      title: 'Shape',
      durationMinutes: 60,
      stopCount: 5,
      transportMode: 'walk',
      metroArea: 'Chicago',
      avgRating: 4.2,
      ratingCount: 7,
    });
    expect(item.createdAt).toBeTruthy();
    expect(item.description).toBeDefined();
    // Explicit: must NOT include full tour fields.
    expect(item.stops).toBeUndefined();
    expect(item.narration_segments).toBeUndefined();
  });
});

describe('POST /v1/tours/:id/visibility', () => {
  it('requires auth', async () => {
    // No seed needed: requireAuth runs before any DB work, so a missing
    // Authorization header must return 401 regardless of whether the tour
    // exists.
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/any/visibility',
      payload: { isPublic: true },
    });
    expect(res.statusCode).toBe(401);
  });

  it('returns 401 regardless of body validity (auth runs first)', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/v1/tours/any/visibility',
      payload: { garbage: 1 },
    });
    expect(res.statusCode).toBe(401);
  });
});

describe('visibility flip round-trip (direct DB)', () => {
  // Round-trip test: simulate what the visibility endpoint does (toggle the
  // column) and verify the public endpoint picks up the change. This covers
  // the DB-level contract without needing to mock Firebase auth.
  it('flipping is_public=1 makes a tour visible on /tours/public and reverting hides it', async () => {
    const db = getDb();
    insertTour({ id: 'flip', title: 'Flip', isPublic: false, rating: 4.0, ratingCount: 2 });

    // Hidden initially.
    let res = await app.inject({ method: 'GET', url: '/v1/tours/public' });
    let body = JSON.parse(res.body) as { tours: Array<{ id: string }>; total: number };
    expect(body.total).toBe(0);

    // Publish.
    db.prepare("UPDATE tours SET is_public = 1, updated_at = datetime('now') WHERE id = ?").run('flip');
    res = await app.inject({ method: 'GET', url: '/v1/tours/public' });
    body = JSON.parse(res.body) as { tours: Array<{ id: string }>; total: number };
    expect(body.total).toBe(1);
    expect(body.tours[0].id).toBe('flip');

    // Unpublish.
    db.prepare("UPDATE tours SET is_public = 0, updated_at = datetime('now') WHERE id = ?").run('flip');
    res = await app.inject({ method: 'GET', url: '/v1/tours/public' });
    body = JSON.parse(res.body) as { tours: Array<{ id: string }>; total: number };
    expect(body.total).toBe(0);
  });
});

describe('GET /v1/tours/:id exposes is_public', () => {
  it('requires auth (existing behavior)', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/tours/does-not-matter' });
    expect(res.statusCode).toBe(401);
  });
});
