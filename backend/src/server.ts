import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { env } from './config/env.js';
import { runMigrations } from './lib/migrate.js';
import { closeDb } from './lib/db.js';
import { healthRoutes } from './routes/health.js';
import { tourRoutes } from './routes/tours.js';
import { audioRoutes } from './routes/audio.js';
import { libraryRoutes } from './routes/library.js';

const app = Fastify({
  logger: {
    level: env.nodeEnv === 'production' ? 'info' : 'debug',
  },
  requestTimeout: 120_000,
});

async function start(): Promise<void> {
  // Run database migrations
  runMigrations();

  // Plugins
  await app.register(cors, {
    origin: true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  });

  await app.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
  });

  // Add min app version header to all responses
  app.addHook('onSend', async (_request, reply) => {
    reply.header('X-Min-App-Version', env.minAppVersion);
  });

  // Routes
  await app.register(healthRoutes);
  await app.register(tourRoutes, { prefix: '/v1' });
  await app.register(audioRoutes, { prefix: '/v1' });
  await app.register(libraryRoutes, { prefix: '/v1' });

  // Graceful shutdown
  const shutdown = async () => {
    app.log.info('Shutting down...');
    await app.close();
    closeDb();
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  await app.listen({ port: env.port, host: env.host });
  app.log.info(`Server running on http://${env.host}:${env.port}`);
}

start().catch((err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
