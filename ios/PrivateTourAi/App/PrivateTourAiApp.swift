import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct PrivateTourAiApp: App {
    @StateObject private var tourViewModel: TourViewModel
    @StateObject private var authViewModel: AuthViewModel
    @State private var showSplash = true

    init() {
        // MUST configure Firebase BEFORE creating any ViewModels
        // that access AuthService (which uses Firebase Auth)
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        _tourViewModel = StateObject(wrappedValue: TourViewModel())
        _authViewModel = StateObject(wrappedValue: AuthViewModel())
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
