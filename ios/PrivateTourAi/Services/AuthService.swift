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

    func getIdToken() async -> String? { try? await user?.getIDToken() }

    // MARK: - Apple Sign-In
    //
    // Correct pattern (verified from Firebase quickstart + SDK source):
    // 1. SignInWithAppleButton sets hashed nonce on request
    // 2. onCompletion receives ASAuthorization with identity token
    // 3. OAuthProvider.appleCredential() creates Firebase credential
    // 4. Auth.auth().signIn(with:) exchanges with Firebase
    //
    // NEVER use OAuthProvider(providerID: .apple) — it fatalErrors on device

    func prepareAppleNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        error = nil

        switch result {
        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = appleCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                error = "Apple: missing identity token"
                isLoading = false
                return
            }

            guard let nonce = currentNonce else {
                error = "Apple: missing nonce — try again"
                isLoading = false
                return
            }

            do {
                let credential = OAuthProvider.appleCredential(
                    withIDToken: idToken,
                    rawNonce: nonce,
                    fullName: appleCredential.fullName
                )
                let result = try await Auth.auth().signIn(with: credential)
                print("[Auth] Apple+Firebase success: \(result.user.uid)")
            } catch {
                print("[Auth] Firebase Apple error: \(error)")
                self.error = "Sign-in failed: \(error.localizedDescription)"
            }

        case .failure(let err):
            let nsErr = err as NSError
            if nsErr.code != ASAuthorizationError.canceled.rawValue {
                self.error = "Apple error: \(err.localizedDescription)"
            }
        }

        isLoading = false
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        isLoading = true
        error = nil

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            error = "Cannot present sign-in"
            isLoading = false
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                error = "Google: missing token"
                isLoading = false
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await Auth.auth().signIn(with: credential)
        } catch let e as GIDSignInError where e.code == .canceled {
            // cancelled
        } catch {
            self.error = "Google error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Email/Password

    func signInWithEmail(email: String, password: String) async {
        isLoading = true
        self.error = nil
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch let authError as NSError {
            if authError.code == AuthErrorCode.userNotFound.rawValue {
                do { try await Auth.auth().createUser(withEmail: email, password: password) }
                catch { self.error = error.localizedDescription }
            } else if authError.code == AuthErrorCode.wrongPassword.rawValue {
                self.error = "Incorrect password"
            } else { self.error = authError.localizedDescription }
        }
        isLoading = false
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async {
        isLoading = true
        self.error = nil
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            self.error = "Reset email sent to \(email)"
        } catch { self.error = "Reset failed: \(error.localizedDescription)" }
        isLoading = false
    }

    // MARK: - Sign Out / Delete

    func signOut() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    func deleteAccount() async throws {
        // Delete server-side data first
        try? await APIClient.shared.deleteAccount()
        // Then delete Firebase auth account
        try await user?.delete()
        // Sign out of Google
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}
