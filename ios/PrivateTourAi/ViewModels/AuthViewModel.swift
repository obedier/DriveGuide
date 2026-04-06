import Foundation

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var displayName: String?
    @Published var email: String?

    // Placeholder — Firebase Auth integration in Sprint S6
    func signIn() {
        // TODO: Implement Firebase Auth
        isAuthenticated = true
        displayName = "Test User"
        email = "test@example.com"
    }

    func signOut() {
        isAuthenticated = false
        displayName = nil
        email = nil
        Task {
            await APIClient.shared.setAuthToken(nil)
        }
    }
}
