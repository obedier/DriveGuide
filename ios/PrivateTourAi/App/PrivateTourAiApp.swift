import SwiftUI
import FirebaseCore
import GoogleSignIn

// Firebase recommended: use UIApplicationDelegateAdaptor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        return true
    }
}

@main
struct PrivateTourAiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var tourViewModel = TourViewModel()
    @StateObject private var authViewModel = AuthViewModel()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(tourViewModel)
                    .environmentObject(authViewModel)
                    .onOpenURL { url in
                        // Handle deep links: waipoint://tour/<shareId> or https://...cloud.run.app/tour/<shareId>
                        if url.scheme == "waipoint" || url.host?.contains("run.app") == true {
                            let path = url.pathComponents
                            if let tourIdx = path.firstIndex(of: "tour"),
                               tourIdx + 1 < path.count {
                                let shareId = path[tourIdx + 1]
                                tourViewModel.openSharedTour(shareId: shareId)
                            }
                        } else {
                            GIDSignIn.sharedInstance.handle(url)
                        }
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
