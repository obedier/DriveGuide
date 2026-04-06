import Foundation
import RevenueCat

@MainActor
class SubscriptionService: ObservableObject {
    @Published var tier: SubscriptionTier = .free
    @Published var offerings: [Package] = []
    @Published var isLoading = false
    @Published var error: String?

    static let shared = SubscriptionService()

    // RevenueCat API key — configure in App Store Connect + RevenueCat dashboard
    // For now, use a placeholder — replace with real key when RC account is set up
    private let rcApiKey = "appl_PLACEHOLDER_REPLACE_WITH_REAL_KEY"
    private var isConfigured = false

    enum SubscriptionTier: String {
        case free
        case single
        case weekly
        case monthly
        case annual

        var canGenerateTours: Bool { self != .free }
        var isUnlimited: Bool { self == .weekly || self == .monthly || self == .annual }
    }

    func configure(userId: String?) {
        guard !isConfigured else { return }

        // Only configure if we have a real API key
        guard !rcApiKey.contains("PLACEHOLDER") else {
            print("[Subscription] RevenueCat not configured — using free tier for all users")
            // For MVP without RevenueCat, grant full access
            tier = .annual // Unlock everything for testing
            return
        }

        Purchases.logLevel = .warn
        if let userId {
            Purchases.configure(withAPIKey: rcApiKey, appUserID: userId)
        } else {
            Purchases.configure(withAPIKey: rcApiKey)
        }
        isConfigured = true

        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        guard isConfigured else { return }

        do {
            let info = try await Purchases.shared.customerInfo()
            if info.entitlements["unlimited"]?.isActive == true {
                if info.activeSubscriptions.contains(where: { $0.contains("annual") }) {
                    tier = .annual
                } else if info.activeSubscriptions.contains(where: { $0.contains("monthly") }) {
                    tier = .monthly
                } else if info.activeSubscriptions.contains(where: { $0.contains("weekly") }) {
                    tier = .weekly
                }
            } else {
                tier = .free
            }
        } catch {
            print("[Subscription] Error fetching status: \(error)")
        }
    }

    func fetchOfferings() async {
        guard isConfigured else { return }
        isLoading = true

        do {
            let offerings = try await Purchases.shared.offerings()
            self.offerings = offerings.current?.availablePackages ?? []
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func purchase(_ package: Package) async -> Bool {
        guard isConfigured else { return false }
        isLoading = true

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                await refreshStatus()
                isLoading = false
                return true
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
        return false
    }

    func restorePurchases() async {
        guard isConfigured else { return }
        isLoading = true

        do {
            _ = try await Purchases.shared.restorePurchases()
            await refreshStatus()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
