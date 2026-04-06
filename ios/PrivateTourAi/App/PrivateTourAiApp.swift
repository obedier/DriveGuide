import SwiftUI
import FirebaseCore

@main
struct PrivateTourAiApp: App {
    @StateObject private var tourViewModel = TourViewModel()
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        // Firebase is configured in AuthService.shared.init()
        _ = AuthService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tourViewModel)
                .environmentObject(authViewModel)
        }
    }
}
