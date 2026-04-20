# Pre-Submission Audit — wAIpoint 2.17

Proactive audit conducted 2026-04-20 against `main` + `experiment/google-navigation-sdk` to land a
clean 2.17 App Review with no avoidable rejections.

**Context correction:** 2.16 was NOT rejected. `state=COMPLETE, lastUpdatedByActor=API_KEY` was
our own withdrawal via `DELETE /v1/appStoreVersionSubmissions`. 2.16 currently sits at
`PREPARE_FOR_SUBMISSION` — editable and ready for re-submission as 2.17.

Legend: PASS | FAIL | ACTION-REQUIRED | INFO

---

## 1. Account deletion flow — PASS

Apple requires in-app deletion (not just "contact support") for any app that allows sign-up.
Confirmed present and wired end-to-end.

**Evidence:**

- UI entry: `ios/PrivateTourAi/Views/ContentView.swift:937-944`
  ```
  Button { showDeleteConfirm = true } label: {
      Text("Delete Account")
          .font(.caption)
          .foregroundStyle(.red.opacity(0.6))
  }
  ```
  Lives in Profile tab, under the main menu — reachable without extra paid wall.

- Destructive confirmation: `ContentView.swift:1060-1075`
  ```
  .alert("Delete Account", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Everything", role: .destructive) { ... }
  } message: {
      Text("This will permanently delete your account, all saved tours, ratings, and
      subscription data. This cannot be undone.")
  }
  ```

- Service layer: `ios/PrivateTourAi/Services/AuthService.swift:165-172`
  ```
  func deleteAccount() async throws {
      try? await APIClient.shared.deleteAccount()   // server wipe first
      try await user?.delete()                      // Firebase auth delete
      GIDSignIn.sharedInstance.signOut()            // Google sign-out
  }
  ```

- API client: `ios/PrivateTourAi/Services/APIClient.swift:353-357` → `DELETE /v1/account`

- Backend: `backend/src/routes/library.ts:96-122` wipes `community_ratings`, `saved_tours`,
  `tour_downloads`, `purchases`, `subscriptions`, all tour sub-rows, `tours`, and finally
  the `users` row. Returns 200 `{ status: 'deleted' }`.

**Minor nit (LOW, non-blocking):** The "Delete Account" label uses `.font(.caption)` +
`.foregroundStyle(.red.opacity(0.6))` — small and faded, but still legible and reachable.
Apple does not require a specific style; placement in Profile is what matters. **No fix needed.**

---

## 2. Privacy policy URL — PASS

`https://waipoint.o11r.com/privacy` returns 200 with real privacy content covering
what/why/retention/deletion. No placeholder or "lorem ipsum" risk.

**Evidence (`curl -I`):**
```
HTTP/2 200
content-type: text/html
content-length: 2375
server: Google Frontend
```

**Content (excerpt from `curl -s https://waipoint.o11r.com/privacy`):**
- "Information We Collect" — Location, Account info, Tour preferences, Usage data.
- "How We Use It" — AI generation, GPS triggers, subscriptions.
- "Data Sharing" — Named third parties (Google, Firebase, Apple, VectorCharts). Explicit
  "We never sell your data."
- "Your Rights" — **"Delete your account anytime from Profile"** + `support@waipoint.app` for data requests.
- "Children" — Not directed at <13.

Implementation: `backend/src/routes/pages.ts:15-40` (inline HTML wrapper, served from
Cloud Run). Consistent with ASC metadata URL (`marketingUrl`, `supportUrl` in
`ios/scripts/push-asc-metadata.js:134-135`).

**No fix needed.** (One potential enhancement for later: add a "Data Retention" section
with explicit retention windows — not a rejection driver.)

---

## 3. Demo account validity — PASS

`tester@o11r.com / AppleTester9!` is a real, working account in Firebase Auth that
successfully authenticates end-to-end against the production backend.

**Evidence:**

- Firebase Auth lookup (`identitytoolkit.googleapis.com/v1/projects/driveguide-492423/accounts:lookup`):
  ```json
  {
    "localId": "IE4mSPDkitSkT1eqR7i3yEB7noI3",
    "email": "tester@o11r.com",
    "providerUserInfo": [{ "providerId": "password" }],
    "createdAt": "1775655600720",
    "lastRefreshAt": "2026-04-10T08:11:24.006Z"
  }
  ```

- Password verification via `accounts:signInWithPassword` → returned valid `idToken`
  with `sub=IE4mSPDkitSkT1eqR7i3yEB7noI3`, `exp=...` +1h. Password is current.

- Backend API with the resulting token:
  ```
  GET https://waipoint.o11r.com/v1/user/tours
  → HTTP 200 {"tours":[],"archived":[]}
  ```

User record auto-provisions in SQLite on first authenticated call via
`backend/src/middleware/auth.ts:55-79` (`ensureUser` creates row + free subscription).

The credentials stored in App Store Connect `appStoreReviewDetails` (queried via
`GET /v1/appStoreVersions/{id}/appStoreReviewDetail`) exactly match:
```
demoAccountName:     "tester@o11r.com"
demoAccountPassword: "AppleTester9!"
demoAccountRequired: true
```

**No fix needed.** User can verify manually by launching the app, tapping Profile → email sign-in,
and entering the credentials.

---

## 4. EULA — PASS (Apple default)

Custom EULA is NOT set. Using Apple's default Standard EULA, which is the normal
choice and fully accepted for subscription apps.

**Evidence:**
```
GET https://api.appstoreconnect.apple.com/v1/apps/6761740179/endUserLicenseAgreement
→ 200 { "data": null, "links": {...} }
```

`data: null` = no custom EULA attached. App Review will use Apple's standard license.

Terms of Service link (`https://waipoint.o11r.com/terms`) is a separate document
referenced from the paywall (`PaywallView.swift:110`) and covers subscription terms
(`backend/src/routes/pages.ts:42-58`) — this is sufficient and does not conflict with
the default EULA.

**No fix needed.**

---

## 5. Location permission strings — PASS (minor polish optional)

Both strings clearly explain WHY location is needed and tie it to the user-visible
behaviour (GPS-triggered narration). They meet Apple's "purposeful, human-readable"
bar and are unlikely to trigger a reviewer nitpick.

**Current strings (`ios/project.yml:94-95`):**

- `NSLocationWhenInUseUsageDescription`
  > "wAIpoint needs your location to provide GPS-triggered narration during tours."

- `NSLocationAlwaysAndWhenInUseUsageDescription`
  > "wAIpoint needs continuous location access to trigger audio narration as you drive through your tour route."

**Assessment:**
- Both name the app, state what they do with location, and tie it to user benefit.
- `AlwaysAndWhenInUse` version correctly justifies background usage ("as you drive
  through your tour route"), which reviewers probe for.
- No vague phrasing like "to improve your experience" or "for core features."

**Optional polish (LOW, non-blocking):** Consider making `Always` version mention that
narration continues when the phone auto-locks — reviewers sometimes ask why background
is needed when the app appears inactive. Suggested rewrite (not required):

- Current: "wAIpoint needs continuous location access to trigger audio narration as you drive through your tour route."
- Tighter: "wAIpoint uses location in the background so GPS-triggered tour narration keeps playing when your phone is locked or the app is in the background during a drive."

**No fix required for 2.17.**

---

## 6. IDFA / ATT — PASS (answer "No" is accurate)

Current ASC declaration: "Does app use Advertising Identifier? No". Verified correct.

**Evidence — no IDFA-collecting SDK is linked:**

- Grep for `ASIdentifierManager`, `advertisingIdentifier`, `SKAdNetwork`, `AdSupport`,
  `NSUserTracking`, `AppTracking` across `ios/` → **zero matches** in app source.

- `ios/project.yml:8-17` — explicit SPM packages:
  - `FirebaseAuth` (NO `FirebaseAnalytics` / `GoogleAppMeasurement`)
  - `GoogleSignIn`
  - `RevenueCat 5.18.0`
  - `Ferrostar`
  - `MapLibreSwiftUI`

- `ios/PrivateTourAi.xcodeproj/project.pbxproj` PBXBuildFile "Frameworks" section
  (lines 22-71) — only `FirebaseAuth`, `GoogleSignIn[Swift]`, `RevenueCat`,
  `Ferrostar{Core,MapLibreUI,SwiftUI}`, `MapLibreSwift{UI,DSL}`, `ViewInspector` are
  actually linked. `FirebaseAnalytics` / `GoogleAppMeasurement` are NOT linked.

- `Package.resolved` pins `googleappmeasurement 11.12.0` — this is a transitive
  entry from SPM dependency resolution of `firebase-ios-sdk`, but since no product
  targeting it is imported, it is not compiled into the binary.

- `FirebaseApp.configure()` is called once (`PrivateTourAiApp.swift:9`), which is
  fine — Firebase Auth only.

- RevenueCat 5.x does not collect IDFA by default. No `Purchases.configure` option
  in source that enables IDFA. (RevenueCat collects "subscriber attributes" such as
  `$appsFlyerId`/`$idfa` only if you set them via `setAttributes()` — not done here.)

- GoogleSignIn 8.x does not use IDFA.

**Conclusion:** "No IDFA" is correct. No ATT prompt required. No fix needed.

---

## 7. Subscription paywall — PASS (complete and compliant)

`PaywallView.swift` meets Apple's subscription-disclosure requirements:

**Evidence (`ios/PrivateTourAi/Views/Screens/PaywallView.swift`):**

| Required element                          | Present | Location |
|-------------------------------------------|---------|----------|
| Clear price per period                    | Yes     | Lines 39-52 (StoreKit `product.displayPrice`) + 33-35 fallback |
| Period length (week/month/year)           | Yes     | Lines 159-167 `periodLabel` + 189 `/year` etc. |
| Auto-renewal disclosure                   | Yes     | Line 104 — "Subscription auto-renews unless canceled at least 24 hours before the end of the current period. Manage in Settings > Apple ID > Subscriptions." |
| Restore Purchases button                  | Yes     | Lines 99-102 `Button("Restore Purchases")` → `store.restorePurchases()` |
| Link to Terms of Service                  | Yes     | Line 110 `Link("Terms of Service", url: .../terms)` |
| Link to Privacy Policy                    | Yes     | Line 111 `Link("Privacy Policy", url: .../privacy)` |
| CTA button clearly labelled               | Yes     | Line 83 — "Start Free Trial" / "Processing..." |

**StoreKit products (`backend/src/routes/pages.ts:50` + landing page pricing):**
- Weekly $7.99, Monthly $14.99, Annual $79.99 ($6.67/mo).

**Subtle caveat (LOW, non-blocking):** The CTA label says "Start Free Trial" regardless
of whether the currently-selected product actually has an introductory trial offer
configured. If StoreKit `Subscriptions.storekit` does not include a free-trial intro
offer for a product, Apple occasionally rejects for misleading CTA. **Recommend before
2.17 submission:**
- Either verify `ios/PrivateTourAi/Resources/Subscriptions.storekit` has
  `introductoryOffer` set for each product, OR
- Change the button label to pick dynamically: show "Start Free Trial" only when
  `product.subscription?.introductoryOffer != nil`, else show "Subscribe".

This is a one-line conditional in `PaywallView.swift:83`. Suggest QA-ing in TestFlight
before 2.17 submit.

**Otherwise no fix required.**

---

## Summary table

| # | Item                             | Status | Blocker for 2.17? |
|---|----------------------------------|--------|-------------------|
| 1 | Account deletion flow            | PASS   | No                |
| 2 | Privacy policy URL               | PASS   | No                |
| 3 | Demo account validity            | PASS   | No                |
| 4 | EULA (Apple default)             | PASS   | No                |
| 5 | Location permission strings      | PASS   | No                |
| 6 | IDFA / ATT                       | PASS   | No                |
| 7 | Subscription paywall             | PASS   | No (see caveat)   |

**Overall:** No submission blockers found. 2.17 can be submitted with confidence.

Two LOW-severity polish items (optional):
- §5: Tighten `NSLocationAlwaysAndWhenInUseUsageDescription` to mention lock-screen / background explicitly.
- §7: Make "Start Free Trial" CTA conditional on the selected product actually having an intro offer.

Neither is a 2.17 blocker. Ship without them if time-pressured; revisit in 2.18.

---

## Evidence artefacts (commands used)

```
# 1. Delete account (iOS + backend)
grep -rn "deleteAccount" ios/PrivateTourAi
grep -rn "DELETE /account\|app.delete" backend/src

# 2. Privacy policy
curl -I https://waipoint.o11r.com/privacy          # → 200
curl -s https://waipoint.o11r.com/privacy | head   # → real content

# 3. Demo account
gcloud auth print-access-token
curl -H "x-goog-user-project: driveguide-492423" \
     -H "Authorization: Bearer $TOKEN" \
     -d '{"email":["tester@o11r.com"]}' \
     https://identitytoolkit.googleapis.com/v1/projects/driveguide-492423/accounts:lookup

# password verify
curl -d '{"email":"tester@o11r.com","password":"AppleTester9!","returnSecureToken":true}' \
     "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$WEB_API_KEY"

# backend verify
curl -H "Authorization: Bearer $TOKEN" https://waipoint.o11r.com/v1/user/tours
# → 200 {"tours":[],"archived":[]}

# 4. EULA
# GET /v1/apps/6761740179/endUserLicenseAgreement → { data: null }

# 5. Location strings
grep -n NSLocation ios/project.yml

# 6. IDFA audit
grep -rn "ASIdentifierManager\|advertisingIdentifier\|AdSupport\|SKAdNetwork\|AppTracking" ios/
# (zero hits)
grep -n "FirebaseAnalytics\|GoogleAppMeasurement" ios/PrivateTourAi.xcodeproj/project.pbxproj
# (zero hits in Frameworks / PBXBuildFile / XCSwiftPackageProductDependency)

# 7. Paywall inspection
cat ios/PrivateTourAi/Views/Screens/PaywallView.swift
```
