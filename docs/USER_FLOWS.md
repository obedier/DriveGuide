# User Flows — Private TourAi

## Flow 1: First Launch (No Account)

### Steps
1. User opens app for first time
2. App shows onboarding carousel (3 screens):
   - "Your personal tour guide, anywhere"
   - "AI-crafted routes with live narration"
   - "Start exploring — no account needed"
3. User taps "Get Started"
4. App shows map-first home screen with search bar

### Acceptance Criteria
- [ ] Onboarding completes in under 10 seconds of user time
- [ ] "Skip" button visible on every onboarding screen
- [ ] Home screen loads with map centered on user's current location (if permitted)
- [ ] Search bar is prominent and immediately tappable
- [ ] No auth required to reach home screen

---

## Flow 2: Generate Tour Preview (Unauthenticated)

### Steps
1. User taps search bar
2. Types location: "South Beach Miami" or "Coral Gables" or "Fort Lauderdale Beach to Wynwood"
3. Selects duration from picker: 30min, 1hr, 1.5hr, 2hr, 3hr, 4hr, 6hr
4. Optionally selects themes: history, food, scenic, hidden gems
5. Taps "Create Tour"
6. Loading state with progress indicator ("Researching area...", "Selecting stops...", "Building route...")
7. Preview screen shows:
   - Route outline on map
   - Tour title and description
   - 2-3 stops revealed with teaser narration
   - Remaining stops shown as locked/blurred
   - Total duration and distance
8. CTA: "Sign up to unlock the full guided tour"

### Acceptance Criteria
- [ ] Preview generates in < 15 seconds
- [ ] Map shows route polyline with stop markers
- [ ] 2-3 preview stops have real, engaging teaser narration (not placeholder)
- [ ] Locked stops show just the stop name and category icon
- [ ] Sign-up CTA is clear but not aggressive
- [ ] Preview is functional without any account

---

## Flow 3: Sign Up / Sign In

### Steps
1. User taps "Sign up" from preview screen or profile tab
2. Auth screen shows three options:
   - Continue with Google
   - Continue with Apple
   - Continue with Email
3a. Google/Apple: Native OAuth flow → auto-create account
3b. Email: Enter email → magic link or password → verify
4. On first auth: profile created with defaults
5. User returned to where they were (preview → now unlocked tour)

### Acceptance Criteria
- [ ] Google Sign-In uses native iOS SDK (ASAuthorizationAppleIDProvider for Apple)
- [ ] Account creation happens automatically on first sign-in
- [ ] User's display name and avatar pulled from OAuth provider
- [ ] After sign-in, user sees full tour (not sent back to home)
- [ ] Session persists (no re-login on app restart)

---

## Flow 4: Generate Full Tour (Authenticated, Paid)

### Steps
1. User enters location + duration + themes (same as preview flow)
2. Taps "Create Tour"
3. Generation with rich loading states:
   - "Researching South Beach..." (2s)
   - "Finding the best stops..." (3s)
   - "Crafting your story arc..." (5s)
   - "Optimizing your route..." (3s)
4. Full tour screen shows:
   - Interactive map with route and all stops
   - Tour title, description, story arc summary
   - Stop-by-stop list with narration previews
   - Total duration, distance, stop count
   - "Open in Google Maps" button
   - "Prepare Audio" button
   - "Start Tour" button
5. User can browse stop details, read narration text
6. Taps "Prepare Audio" → audio generation with progress
7. Taps "Start Tour" to begin guided experience

### Acceptance Criteria
- [ ] Full generation completes in < 60 seconds
- [ ] All stops have approach, at-stop, and departure narration
- [ ] Between-stop narration exists for every leg
- [ ] Route is optimized (no backtracking, sensible order)
- [ ] Google Maps link includes all waypoints
- [ ] Stop narration reads like a knowledgeable local, not Wikipedia
- [ ] Audio preparation shows per-segment progress

---

## Flow 5: Active Guided Tour (GPS-Triggered Audio)

### Steps
1. User taps "Start Tour" (audio must be prepared)
2. App opens to tour map view with current location
3. "Open in Google Maps" prompt — user opens Maps for navigation
4. App runs in background, monitoring GPS
5. As user approaches first segment trigger point:
   - Notification: "Your tour guide has something to share"
   - Audio begins playing (even if app is in background)
   - Tour card shows current narration text
6. Between stops: continuous narration about neighborhoods, streets, landmarks
7. Approaching a stop: approach narration triggers
8. At a stop: at-stop narration with details, tips, photo suggestions
9. Leaving a stop: departure narration transitions to next leg
10. Optional stops: "Want to stop at Joe's Stone Crab? It's a 5-minute detour"
11. Tour completion: outro narration, "Tour complete! Rate your experience"

### Acceptance Criteria
- [ ] GPS triggers fire within 50m of target coordinates
- [ ] Audio plays in background (AVAudioSession configured)
- [ ] Transitions between segments are smooth (no silence gaps > 2s)
- [ ] User can pause/resume audio
- [ ] User can skip to next segment
- [ ] Current position shown on tour map
- [ ] Stop markers change state (upcoming → current → visited)
- [ ] Optional stops can be skipped without breaking narration flow
- [ ] Works while Google Maps is the active app

---

## Flow 6: Edit Tour

### Steps
1. From tour detail, user taps "Edit"
2. Edit mode shows draggable stop list
3. User can:
   - Remove stops (swipe to delete)
   - Reorder stops (drag and drop)
   - Add a stop (tap "+" → search for place → insert at position)
4. Taps "Update Route"
5. Route re-optimized, timing recalculated
6. Option to "Regenerate Narration" for the new route
7. New audio generation if narration changed

### Acceptance Criteria
- [ ] Drag and drop is smooth on stop list
- [ ] Route updates on map in real-time during editing
- [ ] Removing a stop doesn't break surrounding narration continuity
- [ ] Adding a custom stop generates appropriate narration
- [ ] "Regenerate Narration" creates new story arc for modified route
- [ ] Original tour preserved (edit creates a copy)

---

## Flow 7: Offline Tour Download

### Steps
1. From tour detail (with audio generated), user taps "Download for Offline"
2. Download progress: map tiles, audio files, tour data
3. Downloaded tour badge appears in library
4. User goes offline (airplane mode, no signal)
5. Opens downloaded tour → full functionality without network
6. GPS-triggered audio works offline
7. Map shows cached tiles (may be lower detail at some zoom levels)

### Acceptance Criteria
- [ ] Download includes: tour data, all audio files, map tile cache
- [ ] Download size shown before starting (estimated MB)
- [ ] Offline indicator shown when network unavailable
- [ ] All narration segments play offline
- [ ] GPS triggers work offline
- [ ] Tour resumes correctly after app backgrounding offline
- [ ] Downloaded tours expire when subscription lapses (show "Renew to access")

---

## Flow 8: Subscription Purchase

### Steps
1. User hits paywall (free user tries to generate full tour)
2. Subscription screen shows:
   - What you get: full tours, audio narration, offline access, unlimited tours
   - Pricing tiers with annual highlighted as "Best Value"
   - Single tour option for one-time users
3. User selects tier → native App Store purchase sheet
4. Purchase completes → entitlement immediately active
5. User returned to full tour (paywall removed)

### Acceptance Criteria
- [ ] StoreKit 2 purchase flow (native sheet)
- [ ] Entitlement active within 2 seconds of purchase
- [ ] "Restore Purchases" button visible
- [ ] Annual tier shows per-month price and savings percentage
- [ ] Single tour purchase deducts from remaining count
- [ ] Subscription status synced with RevenueCat
- [ ] Graceful handling of purchase failures/cancellations

---

## Flow 9: Tour Library Management

### Steps
1. User navigates to Library tab
2. Sees grid/list of saved tours with:
   - Tour thumbnail (static map image)
   - Title, location, duration
   - Favorite star
   - Download indicator
   - Progress bar (if partially completed)
3. User can: tap to open, favorite, delete, filter by location/date
4. Pull to refresh syncs from server

### Acceptance Criteria
- [ ] Library loads from local cache first, then syncs
- [ ] Search/filter by tour name or location
- [ ] Sort by: date saved, last played, favorites first
- [ ] Swipe to delete with confirmation
- [ ] Empty state with CTA: "Create your first tour"
- [ ] Offline-available tours marked with download icon
