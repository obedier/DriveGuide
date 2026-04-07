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
    private var appleSignInDelegate: AppleSignInDelegate?

    static let shared = AuthService()

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
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

    func getIdToken() async -> String? { try? await user?.getIDToken() }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        isLoading = true
        error = nil
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            error = "Cannot present sign-in"; isLoading = false; return
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                error = "Google: missing token"; isLoading = false; return
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await Auth.auth().signIn(with: credential)
        } catch let e as GIDSignInError where e.code == .canceled {
            // cancelled
        } catch {
            self.error = "Google error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Apple Sign-In (Shelly-proven pattern: callback delegate, no async bridge)

    func signInWithApple() {
        isLoading = true
        error = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let delegate = AppleSignInDelegate()
        appleSignInDelegate = delegate // retain strongly

        delegate.onSuccess = { [weak self] credential in
            guard let self else { return }
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = self.currentNonce else {
                Task { @MainActor in
                    self.error = "Apple: missing credentials"
                    self.isLoading = false
                }
                return
            }

            Task { @MainActor in
                do {
                    let firebaseCred = OAuthProvider.appleCredential(
                        withIDToken: idToken,
                        rawNonce: nonce,
                        fullName: credential.fullName
                    )
                    let result = try await Auth.auth().signIn(with: firebaseCred)
                    print("[Auth] Apple+Firebase success: \(result.user.uid)")
                } catch {
                    print("[Auth] Firebase error after Apple: \(error)")
                    self.error = "Firebase: \(error.localizedDescription)"
                }
                self.isLoading = false
                self.appleSignInDelegate = nil
            }
        }

        delegate.onError = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                let nsErr = error as NSError
                if nsErr.code == ASAuthorizationError.canceled.rawValue {
                    // User cancelled — not an error
                } else {
                    print("[Auth] Apple error: \(nsErr.domain) code=\(nsErr.code)")
                    self.error = "Apple error \(nsErr.code): \(nsErr.domain) — \(error.localizedDescription)"
                }
                self.isLoading = false
                self.appleSignInDelegate = nil
            }
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        controller.performRequests()
    }

    // MARK: - Email/Password

    func signInWithEmail(email: String, password: String) async {
        isLoading = true; self.error = nil
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
        isLoading = true; self.error = nil
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

    func deleteAccount() async {
        try? await user?.delete()
    }

    // MARK: - Nonce helpers

    func prepareAppleNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

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

// MARK: - Apple Sign-In Delegate (NOT @MainActor — matches Shelly's working pattern)

final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var onSuccess: ((ASAuthorizationAppleIDCredential) -> Void)?
    var onError: ((Error) -> Void)?

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        onSuccess?(credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onError?(error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
