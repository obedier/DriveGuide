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

    // Mirror auth state as @Published so SwiftUI re-renders
    @Published var isAuthenticated = false
    @Published var displayName: String?
    @Published var email: String?
    @Published var photoURL: URL?
    @Published var isLoading = false
    @Published var authError: String?

    var tier: SubscriptionService.SubscriptionTier { subscription.tier }

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Sync all auth state changes to our @Published properties
        auth.$isAuthenticated.receive(on: RunLoop.main).sink { [weak self] val in
            self?.isAuthenticated = val
            if val {
                self?.subscription.configure(userId: self?.auth.uid)
            }
        }.store(in: &cancellables)

        auth.$user.receive(on: RunLoop.main).sink { [weak self] user in
            self?.displayName = user?.displayName
            self?.email = user?.email
            self?.photoURL = user?.photoURL
        }.store(in: &cancellables)

        auth.$isLoading.receive(on: RunLoop.main).sink { [weak self] val in
            self?.isLoading = val
        }.store(in: &cancellables)

        auth.$error.receive(on: RunLoop.main).sink { [weak self] val in
            self?.authError = val
        }.store(in: &cancellables)
    }

    func signInWithGoogle() {
        Task { await auth.signInWithGoogle() }
    }

    func signInWithApple() {
        Task { await auth.signInWithApple() }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task { await auth.handleAppleSignIn(result: result) }
    }

    func prepareAppleNonce() -> String {
        auth.prepareAppleNonce()
    }

    func signInWithEmail() {
        guard !emailText.isEmpty, !passwordText.isEmpty else {
            authError = "Please enter email and password"
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
