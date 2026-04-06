import { FastifyInstance } from 'fastify';
import { env } from '../config/env.js';

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get('/health', async () => ({
    status: 'ok',
    version: '0.1.0',
    min_app_version: env.minAppVersion,
  }));
}
