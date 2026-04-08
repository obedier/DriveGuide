import Foundation
import StoreKit

@MainActor
class StoreKitService: ObservableObject {
    static let shared = StoreKitService()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var error: String?

    private let productIDs = [
        "com.privatetourai.weekly",
        "com.privatetourai.monthly",
        "com.privatetourai.annual"
    ]

    var isPremium: Bool { !purchasedProductIDs.isEmpty }

    var currentTier: String {
        if purchasedProductIDs.contains("com.privatetourai.annual") { return "Annual" }
        if purchasedProductIDs.contains("com.privatetourai.monthly") { return "Monthly" }
        if purchasedProductIDs.contains("com.privatetourai.weekly") { return "Weekly" }
        return "Free"
    }

    init() {
        Task { await loadProducts() }
        Task { await updatePurchasedProducts() }
        listenForTransactions()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            print("[Store] Failed to load products: \(error)")
            self.error = "Could not load subscription options"
        }
        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        error = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
                isLoading = false
                return true
            case .userCancelled:
                break
            case .pending:
                error = "Purchase is pending approval"
            @unknown default:
                break
            }
        } catch {
            self.error = "Purchase failed: \(error.localizedDescription)"
        }

        isLoading = false
        return false
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        error = nil
        try? await AppStore.sync()
        await updatePurchasedProducts()
        if purchasedProductIDs.isEmpty {
            error = "No active subscriptions found"
        }
        isLoading = false
    }

    // MARK: - Check Entitlements

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchased.insert(transaction.productID)
            }
        }
        purchasedProductIDs = purchased
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() {
        Task {
            for await result in Transaction.updates {
                if let transaction = try? checkVerified(result) {
                    purchasedProductIDs.insert(transaction.productID)
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let safe): return safe
        }
    }

    enum StoreError: Error { case failedVerification }

    // MARK: - Helpers

    func priceString(for product: Product) -> String {
        product.displayPrice
    }

    func monthlyEquivalent(for product: Product) -> String? {
        guard let sub = product.subscription else { return nil }
        let months: Decimal
        switch sub.subscriptionPeriod.unit {
        case .week: months = Decimal(sub.subscriptionPeriod.value) / 4.33
        case .month: months = Decimal(sub.subscriptionPeriod.value)
        case .year: months = Decimal(sub.subscriptionPeriod.value) * 12
        default: return nil
        }
        let monthly = product.price / months
        return "$\(NSDecimalNumber(decimal: monthly).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)))/mo"
    }
}
