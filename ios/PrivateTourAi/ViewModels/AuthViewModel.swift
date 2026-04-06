import Foundation
import Combine
import AuthenticationServices

@MainActor
class AuthViewModel: ObservableObject {
    let auth = AuthService.shared
    let subscription = SubscriptionService.shared

    @Published var showAuthSheet = false
    @Published var emailText = ""
    @Published var passwordText = ""

    var isAuthenticated: Bool { auth.isAuthenticated }
    var displayName: String? { auth.displayName }
    var email: String? { auth.email }
    var photoURL: URL? { auth.photoURL }
    var isLoading: Bool { auth.isLoading }
    var error: String? { auth.error }
    var tier: SubscriptionService.SubscriptionTier { subscription.tier }

    init() {
        // Configure subscription service when auth state changes
        auth.$isAuthenticated.receive(on: RunLoop.main).sink { [weak self] isAuth in
            if isAuth {
                self?.subscription.configure(userId: self?.auth.uid)
            }
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func signInWithGoogle() {
        Task { await auth.signInWithGoogle() }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task { await auth.handleAppleSignIn(result: result) }
    }

    func prepareAppleNonce() -> String {
        auth.prepareAppleNonce()
    }

    func signInWithEmail() {
        guard !emailText.isEmpty, !passwordText.isEmpty else {
            auth.error = "Please enter email and password"
            return
        }
        Task { await auth.signInWithEmail(email: emailText, password: passwordText) }
    }

    func signOut() {
        auth.signOut()
    }

    func deleteAccount() {
        Task { await auth.deleteAccount() }
    }
}
