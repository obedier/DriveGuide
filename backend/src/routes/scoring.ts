// Routes exposing the v2.17 scoring engine to the iOS client.
//
//   GET  /v1/tours/:id/score                 → latest score bundle for a tour
//   POST /v1/tours/:id/rescore               → recompute + persist (admin)
//
// The iOS client hits GET to render the "87 · Scenic" chip + the
// Gemini-free explanation. POST /rescore is admin-only for now — it lets
// us re-run the scorer against a tour after a prompt-tuning or
// weights-tuning change.

import type { FastifyInstance } from 'fastify';
import { loadTour } from '../services/tour/generator.js';
import {
  loadLatestScoreBundle,
  persistScoreBundle,
  buildFinalScoreFromBundle,
} from '../services/scoring/persistence.js';
import { scoreTour } from '../services/scoring/scorer.js';
import { explainTour } from '../services/scoring/explainer.js';
import type { ScorableStop, ScorableTour } from '../services/scoring/rule-based.js';

export async function scoringRoutes(app: FastifyInstance): Promise<void> {
  // Public — anyone who can see the tour can see its quality score.
  // Caching is free: we read the latest persisted rows, no LLM calls here.
  app.get<{ Params: { id: string } }>('/tours/:id/score', async (request, reply) => {
    const tourId = request.params.id;
    const bundle = loadLatestScoreBundle(tourId);
    if (!bundle) {
      return reply.code(404).send({
        error: { code: 'NOT_SCORED', message: 'This tour has not been scored yet.' },
      });
    }
    const final = buildFinalScoreFromBundle(tourId, bundle);
    const explanation = explainTour(bundle.tourAbsolute, bundle.intentFits);
    return {
      final_score: Math.round(final.final_score * 10) / 10,
      absolute: {
        composite: Math.round(bundle.tourAbsolute.composite * 10) / 10,
        iconic_value: bundle.tourAbsolute.iconic_value,
        geographic_coherence: bundle.tourAbsolute.geographic_coherence,
        time_realism: bundle.tourAbsolute.time_realism,
        narrative_flow: bundle.tourAbsolute.narrative_flow,
        scenic_payoff: bundle.tourAbsolute.scenic_payoff,
        variety_balance: bundle.tourAbsolute.variety_balance,
        practical_usability: bundle.tourAbsolute.practical_usability,
      },
      intent_fits: bundle.intentFits.map((i) => ({
        intent: i.intent,
        fit_score: Math.round(i.fit_score * 10) / 10,
      })),
      explanation,
    };
  });

  // Admin/test — gated by the same FEATURED_SEED_SECRET header we use for
  // other privileged ops. Rescore re-runs the scoring engine against the
  // latest tour data and persists a new bundle.
  app.post<{ Params: { id: string }; Body: { intents?: string[]; cityHint?: string } }>(
    '/tours/:id/rescore',
    async (request, reply) => {
      const expected = process.env.FEATURED_SEED_SECRET;
      const got = request.headers['x-admin-secret'];
      if (!expected || got !== expected) {
        return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Admin secret required' } });
      }

      let tour;
      try {
        tour = loadTour(request.params.id);
      } catch {
        return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Tour not found' } });
      }

      const scorable = loadTourToScorable(tour as unknown as Record<string, unknown>);
      const result = await scoreTour(scorable, {
        intents: (request.body.intents as Array<string>) ?? [],
        cityHint: request.body.cityHint,
        productMode: 'calibration',
      });
      persistScoreBundle({
        tourId: scorable.id,
        stopScores: result.stopScores,
        tourAbsolute: result.tourAbsolute,
        intentFits: result.intentFits,
      });
      return {
        tour_id: scorable.id,
        absolute_composite: Math.round(result.tourAbsolute.composite * 10) / 10,
        final_score: Math.round(result.finalScore.final_score * 10) / 10,
      };
    },
  );
}

/**
 * Map a loaded `Tour` object from generator.ts to the shape the scorer
 * expects. The scorer is intentionally decoupled from the DB schema so
 * it can also be run against in-memory candidates that haven't been
 * persisted yet.
 */
function loadTourToScorable(tour: Record<string, unknown>): ScorableTour {
  const stops = (tour.stops as Array<Record<string, unknown>> | undefined) ?? [];
  const scorableStops: ScorableStop[] = stops.map((s) => ({
    id: s.id as string,
    sequence_order: s.sequence_order as number,
    name: s.name as string,
    category: (s.category as string) ?? 'other',
    latitude: s.latitude as number,
    longitude: s.longitude as number,
    recommended_stay_minutes: (s.recommended_stay_minutes as number) ?? 10,
  }));

  const transportMode = (tour.transport_mode as ScorableTour['transport_mode']) ?? 'car';
  return {
    id: tour.id as string,
    title: (tour.title as string) ?? '',
    description: (tour.description as string) ?? '',
    duration_minutes: (tour.duration_minutes as number) ?? 60,
    transport_mode: transportMode,
    themes: (tour.themes as string[] | undefined) ?? [],
    stops: scorableStops,
  };
}
