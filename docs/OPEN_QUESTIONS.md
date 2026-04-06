# Open Questions — Private TourAi

## Unresolved

1. **Apple Developer account**: Is there an active Apple Developer Program membership for App Store distribution and StoreKit testing? (Required for TestFlight and in-app purchases)

2. **RevenueCat account**: Should we create a RevenueCat project, or use a different server-side receipt validation approach?

3. **Google Maps SDK license**: The Google Maps SDK for iOS requires an API key with Maps SDK for iOS enabled. Need to verify the DriveGuide GCP project has this enabled and billing is active.

4. **TTS voice selection**: Google Cloud TTS has multiple voice types (Standard, WaveNet, Neural2, Journey). Journey voices are most natural but cost more. Should we start with Neural2 for cost savings and upgrade later?

5. **Tour sharing**: Should users be able to share tours with non-users via a web link? This would require a minimal web viewer (not in current spec).

6. **Content moderation**: Should AI-generated narration pass through a content filter before serving? (Gemini generally produces safe content, but edge cases exist)

7. **App Store pricing regions**: Should subscription prices be localized per region, or flat USD pricing with Apple's auto-conversion?

8. **Analytics provider**: Firebase Analytics (free, integrated) vs. Mixpanel/Amplitude (more powerful, paid)?

9. **Crash reporting**: Firebase Crashlytics (free, integrated) or Sentry (more detailed, paid)?

10. **Custom domain**: Should the API be served from `api.privatetourai.com` or is a Cloud Run default URL acceptable for v1?
