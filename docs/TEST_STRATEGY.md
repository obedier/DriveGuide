# Test Strategy — Private TourAi

## Coverage Target: 80%+

## Backend (TypeScript + Fastify)

### Unit Tests (vitest)
| Area | What to Test |
|------|-------------|
| Tour generation | Gemini prompt builder produces correct structure |
| Route optimizer | Waypoint ordering, distance calculation |
| Audio cache | Content hash generation, cache hit/miss logic |
| Narration segmenter | Text split into GPS-triggered segments |
| Subscription | Entitlement logic for each tier |
| URL builder | Google Maps multi-stop URL construction |
| Validation | Request body validation for all endpoints |

### Integration Tests (vitest)
| Area | What to Test |
|------|-------------|
| Database | Migrations run, CRUD operations, Haversine geo queries |
| API routes | Full request/response cycle with real DB |
| Auth middleware | Valid/invalid/expired Firebase tokens |
| Entitlement middleware | Free/paid/expired subscription access |
| RevenueCat webhook | Subscription lifecycle events |

### External Service Mocks
- **Gemini API**: Mock with recorded responses (don't call real API in tests)
- **Google Maps APIs**: Mock with fixture data (real route responses, place data)
- **Google Cloud TTS**: Mock returning fake audio bytes
- **Cloud Storage**: Use in-memory mock or local file system
- **Firebase Auth**: Mock token verification

## iOS (Swift + XCTest / Swift Testing)

### Unit Tests
| Area | What to Test |
|------|-------------|
| ViewModels | State transitions, error handling |
| API Client | Request encoding, response decoding |
| Location Manager | Geofence trigger calculations |
| Audio Segment Sequencer | Segment ordering, trigger matching |
| Offline Storage | Core Data save/load/delete |
| Subscription Manager | Entitlement state machine |

### UI Tests (XCUITest)
| Flow | What to Test |
|------|-------------|
| Onboarding | Carousel completes, skip works |
| Tour generation | Input → loading → result |
| Tour detail | Stops visible, map renders, actions work |
| Auth | Sign in → profile created |
| Paywall | Tiers visible, purchase flow triggered |
| Library | Tour list, favorite, delete |
| Edit | Reorder stops, remove stop |

### Snapshot Tests
- Key screens at multiple device sizes (iPhone SE, iPhone 15, iPhone 15 Pro Max)
- Dark mode variants

## Acceptance Criteria per Sprint

### S0: Scaffold
- [ ] Backend builds and deploys to Cloud Run
- [ ] Health endpoint returns 200
- [ ] Database migrations run successfully
- [ ] iOS project builds for simulator
- [ ] All stub routes return mock data

### S1: Tour Generation
- [ ] `POST /tours/generate` returns valid tour structure
- [ ] Tour has 4-10 stops appropriate for duration
- [ ] Narration passes quality check (> 50 words per stop, no generic phrases)
- [ ] Route is drivable (Google Maps Directions validates)
- [ ] Cache hit returns same tour for same inputs
- [ ] Preview returns limited data for free users

### S2: Audio Pipeline
- [ ] TTS produces audible mp3 files
- [ ] Content hash cache prevents duplicate TTS calls
- [ ] Audio manifest maps to correct GPS triggers
- [ ] ZIP download contains all segments

### S3: iOS Core UI
- [ ] Home screen renders map with location permission prompt
- [ ] Search autocomplete returns relevant results
- [ ] Tour generation shows progressive loading
- [ ] Tour detail shows all stops on map

### S4: Integration
- [ ] iOS generates real tours from API
- [ ] Error states shown for network failures
- [ ] Google Maps deep link opens with correct waypoints

### S5: GPS Audio
- [ ] Audio triggers within 50m of GPS coordinates
- [ ] Background playback works (app backgrounded)
- [ ] Lock screen controls functional
- [ ] Smooth transitions between segments

### S6: Auth + Subscription
- [ ] Google/Apple/Email sign-in complete flow
- [ ] Entitlement correctly gates tour generation
- [ ] StoreKit purchase completes and activates
- [ ] RevenueCat webhook updates subscription state

### S7: Offline
- [ ] Downloaded tour plays without network
- [ ] GPS triggers work offline
- [ ] Map tiles cached for tour area

### S8: Edit + Library
- [ ] Stop reorder updates route correctly
- [ ] Stop removal doesn't break narration
- [ ] Library CRUD works with sync

### S9: Polish
- [ ] All strings in localization files
- [ ] VoiceOver navigation works
- [ ] No crashes in 1-hour stress test
- [ ] All flows work end-to-end
