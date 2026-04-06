# Product Brief — Private TourAi

## Problem

Travelers and locals alike want personalized, narrated driving tours that feel like having an expert local guide in the car — not generic hop-on/hop-off scripts or canned audio tours. Existing solutions are either: (a) pre-packaged tours locked to fixed routes, (b) itinerary planners with no storytelling, or (c) expensive human guides with limited availability.

## Users

| Persona | Description | Key Need |
|---------|-------------|----------|
| **Tourist** | Visiting South Florida for vacation/business | "Show me the best of this area in 2 hours" |
| **New Resident** | Just moved, wants to learn their city | "Tell me the stories behind my neighborhood" |
| **Weekend Explorer** | Local who wants to discover hidden gems | "Surprise me with something I haven't seen" |
| **Group Host** | Showing visiting friends/family around | "Give me a guided tour I can share" |

## Core Value Proposition

Enter any location + duration → get a bespoke driving tour with optimized route, Google Maps directions, and GPS-triggered audio narration that feels like riding with a brilliant 20-year local guide.

## What This Is NOT

- NOT a generic itinerary planner (TripAdvisor, Wanderlog)
- NOT a marketplace of pre-packaged tours (Viator, GetYourGuide)
- NOT a turn-by-turn navigation app (Google Maps, Waze)
- NOT a podcast or static audio guide

## User Flows

### Flow 1: Quick Taste (No Auth)
1. Open app → land on beautiful map-first home screen
2. Enter location (city, neighborhood, or address) + duration (30min–6hrs)
3. App generates a preview: route outline, stop names, estimated time
4. User sees 2-3 stop previews with teaser narration
5. Prompt: "Sign up to unlock the full guided tour"

### Flow 2: Full Guided Tour (Authenticated)
1. Enter location + duration + optional preferences (history, food, scenic, hidden gems)
2. AI researches area, selects stops, builds narrative arc
3. Tour generated: optimized route, all stops with narration, audio files
4. User taps "Start Tour" → Google Maps opens for navigation
5. As user drives, GPS triggers audio narration between stops and at stops
6. Tour includes: approach narration, stop narration, departure narration, between-stop color commentary
7. Option to pause at recommended restaurants, viewpoints, photo ops
8. Tour saved to library for replay or sharing

### Flow 3: Tour Management
1. View saved tours in library
2. Edit stops (add/remove/reorder)
3. Regenerate narration for modified route
4. Download tour for offline use (maps + audio)
5. Share tour link with others

## Success Criteria

- Tour generation < 60 seconds for a 1-hour tour
- Audio narration feels natural, knowledgeable, and engaging
- GPS triggers fire within 50m of target coordinates
- Offline tours work without any network connectivity
- User completes at least 80% of started tours
- Subscription conversion > 5% of authenticated users

## Non-Negotiables

1. Narration quality must feel premium — no robotic, generic, or Wikipedia-dump content
2. Routes must be drivable and optimized (no U-turns, highway-only segments where needed)
3. Audio must trigger based on GPS position, not manual taps
4. Offline mode must include maps, audio, and route data
5. South Florida content must be deeply local — hidden gems, local lore, insider tips
6. Freemium wall must feel generous, not frustrating

## Monetization

| Tier | Price | Access |
|------|-------|--------|
| **Free** | $0 | Preview tours (2-3 stops with teaser narration), unlimited browsing |
| **Single Tour** | $4.99 | One full guided tour with audio |
| **Weekly** | $7.99/week | Unlimited tours |
| **Monthly** | $14.99/month | Unlimited tours |
| **Annual** | $79.99/year (~$6.67/mo) | Unlimited tours — best value |

## Geographic Scope

- **V1 Launch**: South Florida (Miami-Dade, Broward, Palm Beach counties)
- **V1.1**: Top 10 US cities
- **V2**: Global expansion

## Language Support

- **V1 Foundation**: Multi-language architecture from day 1
- **V1 Launch**: English
- **V1.1**: Top 10 global languages (Spanish, Mandarin, Hindi, Arabic, French, Portuguese, Japanese, German, Korean, Italian)
