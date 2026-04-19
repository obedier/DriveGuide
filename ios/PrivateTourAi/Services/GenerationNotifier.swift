import Foundation
import UserNotifications

/// Posts a local notification when a long-running tour build finishes.
/// Used by the "Keep going in background" button on GenerationView so the
/// user can explore the rest of the app while tour/audio generation runs.
///
/// All calls are safe to invoke without first asking for permission — we
/// request on-demand the first time a caller actually wants to notify.
enum GenerationNotifier {

    /// Request the user's permission if we don't have it yet. Safe to call
    /// repeatedly; UNNotificationCenter dedupes.
    static func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        }
    }

    /// Post a local "tour ready" notification. No-op if permission was denied.
    static func notifyTourReady(title: String, body: String, tourId: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let tourId {
            content.userInfo = ["tourId": tourId]
        }
        // Deliver immediately — `trigger: nil` fires right now.
        let request = UNNotificationRequest(
            identifier: "waipoint.generation.\(tourId ?? UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[GenerationNotifier] Failed to post: \(error)")
            }
        }
    }

    static func cancelPendingTourReady() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
