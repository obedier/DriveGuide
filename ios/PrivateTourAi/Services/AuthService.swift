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

            print("[Auth] Google Sign-In succeeded, exchanging with Firebase...")
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            print("[Auth] Firebase auth succeeded: \(authResult.user.uid)")
        } catch let signInError as GIDSignInError where signInError.code == .canceled {
            // User cancelled — not an error
            print("[Auth] Google Sign-In cancelled by user")
        } catch {
            print("[Auth] Google Sign-In error: \(error)")
            self.error = "Google Sign-In failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Apple Sign-In (direct provider)

    func signInWithApple() async {
        isLoading = true
        error = nil

        let nonce = randomNonceString()
        currentNonce = nonce
        let hashedNonce = sha256(nonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = hashedNonce

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            error = "Cannot present Apple Sign-In"
            isLoading = false
            return
        }

        let delegate = AppleSignInDelegate()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        delegate.window = window

        do {
            let authorization = try await delegate.performRequest(controller: controller)

            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = appleCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                error = "Apple Sign-In: missing credentials"
                isLoading = false
                return
            }

            print("[Auth] Apple token received, exchanging with Firebase...")
            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )

            let result = try await Auth.auth().signIn(with: credential)
            print("[Auth] Firebase Apple auth success: \(result.user.uid)")
        } catch {
            let nsError = error as NSError
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                print("[Auth] Apple Sign-In cancelled")
            } else {
                print("[Auth] Apple Sign-In error: code=\(nsError.code) \(error.localizedDescription)")
                self.error = "Apple error (\(nsError.code)): \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

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
                print("[Auth] Apple: missing identityToken or nonce")
                isLoading = false
                return
            }

            print("[Auth] Apple Sign-In succeeded, exchanging with Firebase...")

            // Use the dedicated Apple credential method
            let credential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )

            do {
                let authResult = try await Auth.auth().signIn(with: credential)
                print("[Auth] Firebase auth succeeded via Apple: \(authResult.user.uid)")
            } catch {
                print("[Auth] Firebase Apple auth error: \(error)")
                self.error = "Apple Sign-In failed: \(error.localizedDescription)"
            }

        case .failure(let err):
            let nsError = err as NSError
            print("[Auth] Apple Sign-In failure: code=\(nsError.code), \(err.localizedDescription)")
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                // User cancelled
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

// MARK: - Apple Sign-In Delegate (async/await bridge)

class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var window: UIWindow?
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func performRequest(controller: ASAuthorizationController) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window ?? UIWindow()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
