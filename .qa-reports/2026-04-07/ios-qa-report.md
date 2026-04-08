# iOS QA Report — wAIpoint
> Date: 2026-04-07 | Device: iPhone 17 Pro (Simulator) | iOS: 26.3 | Build: 6

## Summary
- Build: **PASS**
- Launch: **PASS**
- Screens tested: 6
- Issues found: 3 (0 critical, 2 medium, 1 low)
- Screenshots captured: 10

## Screen-by-Screen Results

### Splash Screen
- Status: **OK**
- Screenshot: 01-splash.png
- Compass animation displays, gold branding visible

### Explore (Home)
- Status: **OK**
- Screenshot: 03-explore-tab.png, 06-explore-return.png
- Map renders, search bar visible with gold accent, location button, "wAIpoint" watermark at bottom
- Navy overlay provides good contrast

### Library
- Status: **OK**
- Screenshot: 04-library-tab.png
- Sample boat tour displayed with correct formatting
- Gold title, green card background, nautical miles (8.5 nm), ferry icon
- "wAIpoint / Tour Library" branded nav bar

### Profile (Sign-In)
- Status: **OK**
- Screenshot: 05-profile-tab.png
- Apple Sign-In button (white, native style)
- Google Sign-In button (gold)
- Email/Password fields visible with proper contrast
- "Forgot Password?" link visible

### Dark Mode — Explore
- Status: **OK**
- Screenshot: 07-dark-mode-explore.png
- Map switches to dark theme automatically
- Search bar and UI elements maintain readability

### Dark Mode — Library
- Status: **OK**
- Screenshot: 08-dark-mode-library.png
- Green cards maintain contrast on dark background

### Dark Mode — Profile
- Status: **OK**
- Screenshot: 09-dark-mode-profile.png
- All buttons and text fields visible

### Large Text
- Status: **MEDIUM ISSUE**
- Screenshot: 10-large-text.png
- Search placeholder text truncated
- Tab bar text clips slightly

## Issues Found

### ISSUE-001: Search placeholder truncated at large text sizes
- Severity: Low
- Screen: Explore (large text mode)
- Description: The search placeholder "City, neighborhood, or a..." gets clipped further at XXL text
- Screenshot: 10-large-text.png

### ISSUE-002: Apple Sign-In 2FA password loop on physical device
- Severity: Medium
- Screen: Profile
- Description: On physical device, Apple Sign-In shows password dialog that loops after entering password (2FA challenge not completing). Firebase OAuthProvider web flow added as alternative in build 6.
- Workaround: Use email sign-in or wait for TestFlight build 6

### ISSUE-003: Generation overlay only covers bottom half of screen
- Severity: Medium
- Screen: Explore (during tour generation)
- Description: Fixed in latest build — now uses full-screen overlay with `.ignoresSafeArea()` and disables search card during generation
- Status: Fixed, needs device verification

## Responsive Check
- Dark Mode: **OK** — all screens render correctly
- Large Text: **MINOR** — search placeholder truncation
- iPad: N/A (iPhone-only app)

## Verified Working
- ✅ Splash screen animation (compass + gold title)
- ✅ Map renders with dark overlay
- ✅ Tab navigation (Explore → Library → Profile)
- ✅ Library shows saved tours with correct units (nm for boat)
- ✅ Profile shows sign-in options
- ✅ Dark mode adaptation
- ✅ Firebase initialization (confirmed via debug logs — no more "not configured" error)
- ✅ No crashes on any screen
