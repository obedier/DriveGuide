import { config } from 'dotenv';
import { resolve } from 'path';

config({ path: resolve(import.meta.dirname, '../../.env') });

export const env = {
  port: parseInt(process.env.PORT || '8080', 10),
  host: process.env.HOST || '0.0.0.0',
  nodeEnv: process.env.NODE_ENV || 'development',

  // GCP
  gcpProjectId: process.env.GCP_PROJECT_ID || 'driveguide-492423',
  gcpRegion: process.env.GCP_REGION || 'us-east1',

  // Gemini
  geminiApiKey: process.env.GEMINI_API_KEY || '',

  // Google Maps
  googleMapsKey: process.env.DRIVEGUIDE_MAPS_KEY || process.env.GOOGLE_MAPS_KEY || '',

  // GCS Buckets
  audioCacheBucket: process.env.GCS_AUDIO_CACHE_BUCKET || 'driveguide-audio-cache',
  sqliteBackupBucket: process.env.GCS_SQLITE_BACKUP_BUCKET || 'driveguide-sqlite-backups',
  assetsBucket: process.env.GCS_ASSETS_BUCKET || 'driveguide-assets',

  // Firebase
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || 'driveguide-492423',

  // SQLite
  dbPath: process.env.DB_PATH || resolve(import.meta.dirname, '../../data/tourai.db'),

  // Rate limits
  previewGlobalLimit: parseInt(process.env.PREVIEW_GLOBAL_LIMIT || '500', 10),
  previewPerIpLimit: parseInt(process.env.PREVIEW_PER_IP_LIMIT || '3', 10),

  // App version
  minAppVersion: process.env.MIN_APP_VERSION || '1.0.0',
} as const;
