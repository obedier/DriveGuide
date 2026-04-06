# Decision Log — Private TourAi

Agents append decisions here as they are made during development.

| Date | Sprint | Decision | Rationale | Decided By |
|------|--------|----------|-----------|------------|
| 2026-04-05 | Spec | Native iOS over React Native | User requirement for true geofencing via native APIs, background audio, StoreKit 2 | User/Architect |
| 2026-04-05 | Spec | Cloud Run over GKE | Right-sized for v1, scales to zero, lower ops | User/Architect |
| 2026-04-05 | Spec | Gemini 2.0 Flash over Pro | 10x cheaper, fast enough for narration, upgrade path exists | Architect |
| 2026-04-05 | Spec | SQLite + Litestream over Cloud SQL | Zero DB cost for v1, Litestream replicates to GCS. Upgrade to PostgreSQL + PostGIS when concurrent writes or advanced spatial queries needed | User/Architect |
| 2026-04-05 | Spec | Fastify over Express | 2-3x performance, built-in validation, better TS support | Architect |
| 2026-04-05 | Spec | RevenueCat for subscriptions | Handles receipt validation, cross-platform ready, analytics | Architect |
| 2026-04-05 | Spec | Content-hash audio cache | Same text = same audio file, massive TTS cost savings | Architect |
| 2026-04-05 | Review | Cloud Run max-instances=1 hard constraint | SQLite single-writer; WAL mode + 5s busy timeout handles concurrency=80 | Eng Review |
| 2026-04-05 | Review | Sliding-window geofencing (15-18 of 20 max) | iOS CLLocationManager 20-region limit; dynamic swap as user progresses | Eng Review |
| 2026-04-05 | Review | Auto-background audio generation | Avoid 2-min wait; start audio gen immediately after tour gen, enable Start Tour after first 3-4 segments ready | Eng Review |
| 2026-04-05 | Review | Merged AUDIO_CACHE into AUDIO_FILES | Redundant table; in-memory LRU handles hot-path cache lookup | Eng Review |
| 2026-04-05 | Review | Global rate limit on preview endpoint | Prevent API cost abuse; 500 previews/hr global cap + prefer cached template tours | Eng Review |
| 2026-04-05 | Review | X-Min-App-Version header for force-upgrade | Cannot force-update iOS App Store users; header enables server-side control | Eng Review |
| 2026-04-05 | Review | Offline stores audio bytes, not signed URLs | Signed GCS URLs expire; iOS downloads actual files to FileManager | Eng Review |
| 2026-04-05 | Spec | South Florida first | Focus on one region for quality, expand after model proven | User |
