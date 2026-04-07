import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct PrivateTourAiApp: App {
    @StateObject private var tourViewModel = TourViewModel()
    @StateObject private var authViewModel = AuthViewModel()
    @State private var showSplash = true

    init() {
        _ = AuthService.shared
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(tourViewModel)
                    .environmentObject(authViewModel)
                    .onOpenURL { url in
                        GIDSignIn.sharedInstance.handle(url)
                    }

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
