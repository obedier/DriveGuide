# Tourist Recommendation Engine — Strategy v0.1

> Date: 2026-04-08 | Status: Research Complete, Implementation Pending

## Vision

Build the world's best AI tour recommendation engine by combining verified top-rated locations with AI-generated narration, personalized per transport mode and user preferences.

## Architecture

```
User Request → Gemini AI (with function calling) → Google Places Verification → Mode Scoring → Tour Assembly → Audio Generation
                                                          ↑
                                               Master Location Database
                                           (verified top-100 per city)
```

---

## 1. Data Sources (Ranked by Value)

| Source | Data | Cost | Priority |
|--------|------|------|----------|
| Google Places API (New) | Name, address, coords, rating, 5 reviews, photos, hours | $32/1K searches, $200/mo free | P0 |
| Yelp Fusion API | Ratings, price level, 3 review excerpts, categories | Free (5K/day) | P1 |
| Foursquare Places API | 900+ category taxonomy, popularity scores, tips | Free (100K/mo) | P2 |
| Walk Score API | Walkability score per coordinate (0-100) | Free (<5K/day) | P1 for walk mode |
| OpenStreetMap Overpass | Bike lanes, waterways, harbours, parking | Free | P1 for bike/boat |
| GBFS Feeds | Bike share station locations (Citi Bike, etc.) | Free, real-time | P2 |
| TripAdvisor | Reviews, rankings, Travelers' Choice | Partner-only (API closed 2019) | P3 |

## 2. Master Database Schema

### Locations Table
- `id`, `google_place_id`, `yelp_id`
- `name`, `address`, `city`, `state`, `coordinates` (PostGIS POINT)
- `category` (restaurant, attraction, museum, park, etc.)
- `google_rating`, `google_review_count`, `yelp_rating`, `composite_score`
- `price_level` (1-4)
- Mode accessibility scores (0.0-1.0): `car`, `walk`, `bike`, `boat`, `plane`
- `last_verified_at`, `is_active`

### Composite Score Formula
```
composite = (0.4 * google_rating_normalized) + 
            (0.3 * review_count_normalized) +
            (0.2 * yelp_rating_normalized) +
            (0.1 * presence_in_curated_lists)
```

### Category Balance (per city, top 100)
- ~30 restaurants
- ~25 attractions/sights
- ~15 museums/cultural
- ~10 parks/outdoor
- ~10 shopping/entertainment
- ~10 nightlife/bars

## 3. Mode-Specific Scoring

### Car
- Parking availability (+3), drive-up access (+2), scenic route (+1)
- Exclude: pedestrian-only zones
- Data: Google Places `parkingOptions`, OpenStreetMap

### Walk
- Walk Score >80 (+3), walkable district cluster (+3), pedestrian streets (+2)
- Cluster stops within 15-20 min walk of each other
- Data: Walk Score API, OSM pedestrian tags

### Bike
- Bike lane within 200m (+3), bike rack at location (+2), flat terrain (+1)
- Bike share station nearby (+2)
- Data: OSM `cycleway` tags, GBFS feeds

### Boat
- Waterfront location (+3), dock within 200m (+3), visible from water (+2)
- Must pass vessel constraints (draft, length, air draft)
- Data: NOAA charts, ActiveCaptain, OSM `harbour`/`waterway`

### Plane
- Aerial landmark visibility (+3), no restricted airspace (+2)
- Data: FAA NASR database, SkyVector

### Minimum Threshold
Locations scoring below 0.3 on mode_accessibility EXCLUDED for that mode.

## 4. Prompt Engineering Strategy

### Quality Chain (5 steps)
1. **Generate**: 15 candidate stops with few-shot examples of known top tours
2. **Verify**: Function-call each stop against Google Places (rating >= 4.0, 500+ reviews)
3. **Filter**: Remove failed verifications, replace with alternatives
4. **Narrate**: Write compelling narration for each verified stop
5. **Quality Check**: "Does this match what a local expert would recommend?"

### Few-Shot Anchoring
Include 2-3 examples of verified excellent tours in every prompt:
```
EXAMPLE - Miami Beach Walking Tour (verified quality):
Stop 1: Joe's Stone Crab - 4.4★ (12,847 reviews)
Stop 2: Art Deco Historic District - 4.6★ (8,231 reviews)
...
```

### Function Calling
```
verify_location(place_name, city, expected_category)
→ Google Places API → confirm: exists, rating >= 4.0, review_count >= 500
```

### Quality Target
**80%+ of AI stops should match verified top-100 list for each city**

## 5. Review Integration

### Legal Framework
| Source | Can Display? | Requirements | In Audio? |
|--------|-------------|-------------|-----------|
| Google | Yes | Google attribution, link to Maps, no >30 day cache | Paraphrase only |
| Yelp | Yes | Yelp logo, official star assets, link to listing | Paraphrase only |
| TripAdvisor | Partner only | TripAdvisor branding, link back | N/A |

### Safe Approach
- Display reviews with attribution in app UI
- Audio narration paraphrases review sentiment (never quotes verbatim)
- Example: "celebrated for its waterfront views" not "as one reviewer said..."

## 6. Implementation Phases

### Phase 1: South Florida (Current)
- **Scope**: Miami, Fort Lauderdale, Palm Beach — 300 verified locations
- **Timeline**: 8-10 weeks
- **Cost**: ~$300-400/month
- **Status**: Using Gemini function calling, no master database yet

### Phase 2: Top 10 US Cities
- **Scope**: NYC, LA, Chicago, SF, Las Vegas, Orlando, DC, Boston, Seattle, New Orleans
- **Timeline**: 8-10 weeks after Phase 1
- **Cost**: ~$750-1,000/month
- **Includes**: Walk Score integration, city-specific prompt tuning

### Phase 3: Top 100 US Cities
- **Scope**: 90 additional cities, fully automated pipeline
- **Timeline**: 10-12 weeks after Phase 2
- **Cost**: ~$2,500-3,000/month
- **Includes**: Monitoring dashboard, automated quality scoring

## 7. Competitive Advantage

No competitor offers ALL of:
- AI-generated (not pre-packaged)
- Verified against real ratings data
- Multi-modal (car/walk/bike/boat/plane)
- Personalized (custom prompts, themes)
- On-demand (any location, instant)

| Competitor | AI? | Verified? | Multi-modal? | Personalized? | On-demand? |
|------------|-----|-----------|-------------|---------------|------------|
| VoiceMap | ❌ | ❌ | Walk only | ❌ | ❌ |
| Action Tour Guide | ❌ | ❌ | Drive only | ❌ | ❌ |
| GyPSy Guide | ❌ | ❌ | Drive only | ❌ | ❌ |
| **wAIpoint** | ✅ | ✅ | ✅ 5 modes | ✅ | ✅ |

## 8. Success Metrics

| Metric | Target | How to Measure |
|--------|--------|---------------|
| Top-100 match rate | ≥80% | Compare AI stops vs verified database |
| Average stop rating | ≥4.2 | Google Places rating of selected stops |
| Tour completion rate | ≥80% | % of users who finish started tours |
| User rating | ≥4.5 | In-app tour ratings |
| Subscription conversion | ≥5% | Free → paid conversion rate |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v0.1 | 2026-04-08 | Initial strategy based on deep research. API analysis, mode scoring framework, prompt engineering strategy, phased implementation plan. |
