import { FastifyRequest, FastifyReply } from 'fastify';
import admin from 'firebase-admin';
import { env } from '../config/env.js';
import { getDb } from '../lib/db.js';
import { newId } from '../lib/id.js';

// Initialize Firebase Admin (uses ADC in Cloud Run)
if (!admin.apps.length) {
  admin.initializeApp({ projectId: env.firebaseProjectId });
}

export interface AuthUser {
  uid: string;
  userId: string;  // our internal user ID
  email: string | null;
}

declare module 'fastify' {
  interface FastifyRequest {
    user?: AuthUser;
  }
}

export async function requireAuth(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'Missing or invalid authorization header' } });
    return;
  }

  const token = authHeader.slice(7);
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    const user = ensureUser(decoded.uid, decoded.email ?? null, decoded.name ?? null, decoded.picture ?? null);
    request.user = { uid: decoded.uid, userId: user.id, email: decoded.email ?? null };
  } catch {
    reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'Invalid or expired token' } });
  }
}

export async function optionalAuth(request: FastifyRequest): Promise<void> {
  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return;

  const token = authHeader.slice(7);
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    const user = ensureUser(decoded.uid, decoded.email ?? null, decoded.name ?? null, decoded.picture ?? null);
    request.user = { uid: decoded.uid, userId: user.id, email: decoded.email ?? null };
  } catch {
    // Silent fail for optional auth
  }
}

function ensureUser(
  firebaseUid: string,
  email: string | null,
  displayName: string | null,
  avatarUrl: string | null,
): { id: string } {
  const db = getDb();

  const existing = db.prepare('SELECT id FROM users WHERE firebase_uid = ?').get(firebaseUid) as { id: string } | undefined;
  if (existing) return existing;

  const id = newId();
  db.prepare(`
    INSERT INTO users (id, firebase_uid, email, display_name, avatar_url)
    VALUES (?, ?, ?, ?, ?)
  `).run(id, firebaseUid, email, displayName, avatarUrl);

  // Create free subscription
  db.prepare(`
    INSERT INTO subscriptions (id, user_id, tier, status)
    VALUES (?, ?, 'free', 'active')
  `).run(newId(), id);

  return { id };
}
