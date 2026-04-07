import Foundation
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit

@MainActor
class AuthService: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: String?

    private var currentNonce: String?

    static let shared = AuthService()

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // Configure Google Sign-In with client ID from GoogleService-Info.plist
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = user != nil
            }
        }
    }

    var displayName: String? { user?.displayName }
    var email: String? { user?.email }
    var photoURL: URL? { user?.photoURL }
    var uid: String? { user?.uid }

    func getIdToken() async -> String? {
        try? await user?.getIDToken()
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        isLoading = true
        error = nil

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            error = "Cannot present sign-in screen"
            isLoading = false
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                error = "Google Sign-In: missing ID token"
                isLoading = false
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await Auth.auth().signIn(with: credential)
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue {
                self.error = "Google Sign-In failed: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    // MARK: - Apple Sign-In

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        error = nil

        switch result {
        case .success(let auth):
            guard let appleCredential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = appleCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                error = "Apple Sign-In: missing credentials"
                isLoading = false
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )

            do {
                try await Auth.auth().signIn(with: credential)
            } catch {
                self.error = "Apple Sign-In failed: \(error.localizedDescription)"
            }

        case .failure(let err):
            let nsError = err as NSError
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                // User cancelled — not an error
            } else if nsError.code == ASAuthorizationError.unknown.rawValue {
                self.error = "Apple Sign-In requires the Sign in with Apple capability. Check Xcode → Signing & Capabilities."
            } else {
                self.error = "Apple Sign-In error: \(err.localizedDescription)"
            }
        }

        isLoading = false
    }

    func prepareAppleNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    // MARK: - Email/Password

    func signInWithEmail(email: String, password: String) async {
        isLoading = true
        error = nil

        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch let authError as NSError {
            if authError.code == AuthErrorCode.userNotFound.rawValue {
                do {
                    try await Auth.auth().createUser(withEmail: email, password: password)
                } catch {
                    self.error = error.localizedDescription
                }
            } else if authError.code == AuthErrorCode.wrongPassword.rawValue {
                self.error = "Incorrect password"
            } else {
                self.error = authError.localizedDescription
            }
        }

        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAccount() async {
        do {
            try await user?.delete()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
