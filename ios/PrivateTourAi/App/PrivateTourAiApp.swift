import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct PrivateTourAiApp: App {
    @StateObject private var tourViewModel = TourViewModel()
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        _ = AuthService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tourViewModel)
                .environmentObject(authViewModel)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
