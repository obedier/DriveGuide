import SwiftUI

@main
struct PrivateTourAiApp: App {
    @StateObject private var tourViewModel = TourViewModel()
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tourViewModel)
                .environmentObject(authViewModel)
        }
    }
}
