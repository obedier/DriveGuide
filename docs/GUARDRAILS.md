# Guardrails — Private TourAi

## Hard Rules (NEVER violate)

### Security
1. **Never expose API keys in client code** — all GCP/Gemini/Maps calls go through the backend
2. **Never trust client-submitted subscription status** — always verify server-side via RevenueCat
3. **Never serve audio URLs without auth** — signed URLs with short expiry only
4. **Never log PII** — no email, name, or location history in plaintext logs
5. **Never store payment data** — Apple/RevenueCat handle all billing

### Content Quality
6. **Never generate generic Wikipedia-style narration** — every prompt must include the "20-year local guide" persona with specific instructions for storytelling, humor, insider knowledge
7. **Never show placeholder or lorem ipsum content to users** — all visible text must be real
8. **Never ship a stop without narration** — every stop must have approach, at-stop, and departure text
9. **Never include stops that are permanently closed** — validate against Google Places data

### Architecture
10. **Never call GCP APIs directly from the iOS app** — all external API calls go through Cloud Run
11. **Never skip the audio cache check** — always check content hash in GCS before calling TTS
12. **Never store audio files without content hashing** — identical text = identical file, always
13. **Never modify API contracts without updating API_CONTRACTS.md first** — spec is source of truth
14. **Never use synchronous audio generation in the request path** — audio gen is always async/background

### User Experience
15. **Never block the UI on network calls** — all API calls are async with loading states
16. **Never lose tour progress** — save playback position on every segment transition
17. **Never break the narration flow on optional stop skip** — departure narration must gracefully handle skipped stops
18. **Never show the paywall before the user sees value** — preview first, then gate

### Data
19. **Never delete a user's tours on subscription expiry** — lock access, don't delete
20. **Never serve stale subscription status** — check RevenueCat on every gated request (with in-memory LRU cache, 5min TTL)
21. **Never allow IDOR on tour resources** — every tour/library/audio query MUST include `WHERE user_id = :authenticated_user_id`; template tours (`is_template=true`) use a separate read-only access path
22. **Never skip RevenueCat webhook signature verification** — validate `X-RevenueCat-Signature` header using HMAC-SHA256 with shared secret
23. **Never allow tour generation to hang** — 90-second timeout on the full pipeline; if any external API fails, set `status: 'failed'` with error reason and clean up partial data

## Soft Rules (Prefer but can override with reason)

1. Prefer cached tours over re-generation when location hash matches
2. Prefer Gemini 2.0 Flash over Pro for cost (upgrade to Pro only if quality insufficient)
3. Prefer Google's "Journey" voices for TTS (most natural for narration)
4. Prefer 30-second narration segments (sweet spot for attention + trigger precision)
5. Prefer Cloud Run min-instances=1 to avoid cold starts (until cost is a concern)
