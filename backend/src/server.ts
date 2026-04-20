import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { env } from './config/env.js';
import { runMigrations } from './lib/migrate.js';
import { closeDb, getDb } from './lib/db.js';
import { healthRoutes } from './routes/health.js';
import { tourRoutes } from './routes/tours.js';
import { scoringRoutes } from './routes/scoring.js';
import { audioRoutes } from './routes/audio.js';
import { libraryRoutes } from './routes/library.js';
import { pageRoutes } from './routes/pages.js';

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

  // Apple Universal Links
  app.get('/.well-known/apple-app-site-association', async (_request, reply) => {
    reply.header('Content-Type', 'application/json');
    return {
      applinks: {
        apps: [],
        details: [{
          appID: 'U3972W2GDJ.com.privatetourai.app',
          paths: ['/tour/*', '/passenger/*'],
        }],
      },
    };
  });

  // Shared tour landing page (web fallback + link preview)
  app.get<{ Params: { shareId: string } }>('/tour/:shareId', async (request, reply) => {
    const db = getDb();
    const row = db.prepare('SELECT id, title, description, location_query, duration_minutes, transport_mode FROM tours WHERE share_id = ?')
      .get(request.params.shareId) as { id: string; title: string; description: string; location_query: string; duration_minutes: number; transport_mode: string } | undefined;

    if (!row) {
      reply.code(404).type('text/html');
      return '<html><body><h1>Tour not found</h1><p><a href="https://apps.apple.com/app/waipoint/id6761740179">Get wAIpoint</a></p></body></html>';
    }

    const appStoreUrl = 'https://apps.apple.com/app/waipoint/id6761740179';
    const deepLink = `waipoint://tour/${request.params.shareId}`;

    reply.type('text/html');
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${row.title} — wAIpoint</title>
  <meta property="og:title" content="${row.title}">
  <meta property="og:description" content="${row.description} • ${row.location_query} • ${row.duration_minutes} min ${row.transport_mode || 'car'} tour">
  <meta property="og:type" content="website">
  <meta property="og:image" content="https://private-tourai-api-i32snp7xla-ue.a.run.app/static/og-image.png">
  <style>
    body { font-family: -apple-system, sans-serif; background: #1B2D4F; color: white; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; text-align: center; }
    .card { max-width: 400px; padding: 40px; }
    h1 { color: #C5A55A; font-size: 24px; }
    p { color: rgba(255,255,255,0.6); }
    .btn { display: inline-block; background: linear-gradient(135deg, #C5A55A, #D4B96A); color: #1B2D4F; padding: 16px 32px; border-radius: 14px; text-decoration: none; font-weight: bold; margin: 10px; }
    .stats { color: rgba(255,255,255,0.4); font-size: 14px; margin: 16px 0; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🧭 ${row.title}</h1>
    <p>${row.description}</p>
    <div class="stats">${row.location_query} • ${row.duration_minutes} min • ${row.transport_mode || 'car'}</div>
    <a href="${deepLink}" class="btn">Open in wAIpoint</a>
    <br>
    <a href="${appStoreUrl}" class="btn" style="background: rgba(255,255,255,0.1); color: white;">Get the App</a>
  </div>
  <script>
    // Try to open the app, fall back to App Store
    setTimeout(function() { window.location = '${deepLink}'; }, 100);
    setTimeout(function() { window.location = '${appStoreUrl}'; }, 2000);
  </script>
</body>
</html>`;
  });

  // Routes
  await app.register(healthRoutes);
  await app.register(tourRoutes, { prefix: '/v1' });
  await app.register(scoringRoutes, { prefix: '/v1' });
  await app.register(audioRoutes, { prefix: '/v1' });
  await app.register(libraryRoutes, { prefix: '/v1' });
  await app.register(pageRoutes);



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
