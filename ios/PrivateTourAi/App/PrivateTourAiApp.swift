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
                        // Deep links we recognize:
                        //   waipoint://tour/<shareId>                → open in full tour view
                        //   https://waipoint.o11r.com/tour/<shareId>  → same (Universal Link)
                        //   https://waipoint.o11r.com/passenger/<id>  → open directly in Passenger Mode
                        //   https://*.run.app/tour/<shareId>          → legacy fallback
                        let isOurLink = url.scheme == "waipoint"
                            || url.host == "waipoint.o11r.com"
                            || url.host?.contains("run.app") == true
                        guard isOurLink else {
                            GIDSignIn.sharedInstance.handle(url)
                            return
                        }
                        let path = url.pathComponents
                        if let passengerIdx = path.firstIndex(of: "passenger"),
                           passengerIdx + 1 < path.count {
                            tourViewModel.openSharedTour(shareId: path[passengerIdx + 1], passengerMode: true)
                        } else if let tourIdx = path.firstIndex(of: "tour"),
                                  tourIdx + 1 < path.count {
                            tourViewModel.openSharedTour(shareId: path[tourIdx + 1])
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
