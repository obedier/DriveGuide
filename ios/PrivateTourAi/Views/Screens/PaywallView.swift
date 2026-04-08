import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var store = StoreKitService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProduct: Product?
    @State private var selectedFallback: Int = 2  // default annual
    @State private var purchasing = false

    var body: some View {
        ZStack {
            Color.brandDarkNavy.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("wAIpoint")
                            .font(.caption).foregroundStyle(.brandGold)
                        Text("Unlock Premium")
                            .font(.title.bold()).foregroundStyle(.white)
                        Text("Get unlimited AI-guided tours with audio narration")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    // Subscription cards
                    if store.products.isEmpty {
                        // Fallback when StoreKit products not available
                        HStack(spacing: 12) {
                            FallbackCard(name: "Weekly", price: "$7.99", period: "/week", isBestValue: false, isSelected: selectedFallback == 0) { selectedFallback = 0 }
                            FallbackCard(name: "Monthly", price: "$14.99", period: "/month", isBestValue: false, isSelected: selectedFallback == 1) { selectedFallback = 1 }
                            FallbackCard(name: "Annual", price: "$79.99", period: "/year", isBestValue: true, isSelected: selectedFallback == 2) { selectedFallback = 2 }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        HStack(spacing: 12) {
                            ForEach(store.products, id: \.id) { product in
                                SubscriptionCard(
                                    product: product,
                                    isSelected: selectedProduct?.id == product.id,
                                    isBestValue: product.id.contains("annual"),
                                    monthlyPrice: store.monthlyEquivalent(for: product)
                                ) {
                                    selectedProduct = product
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Features list
                    VStack(alignment: .leading, spacing: 14) {
                        FeatureRow(icon: "checkmark.circle.fill", text: "Unlimited AI Tours")
                        FeatureRow(icon: "checkmark.circle.fill", text: "Audio Narration")
                        FeatureRow(icon: "checkmark.circle.fill", text: "GPS-Triggered Playback")
                        FeatureRow(icon: "checkmark.circle.fill", text: "Offline Downloads")
                        FeatureRow(icon: "checkmark.circle.fill", text: "Premium Voice Options")
                        FeatureRow(icon: "checkmark.circle.fill", text: "All Transport Modes")
                    }
                    .padding(.horizontal, 30)

                    // Subscribe button
                    Button {
                        if let product = selectedProduct {
                            purchasing = true
                            Task {
                                let success = await store.purchase(product)
                                purchasing = false
                                if success { dismiss() }
                            }
                        } else if store.products.isEmpty {
                            // Products not loaded — inform user
                            store.error = "Subscriptions are being set up. Please try again from TestFlight or App Store."
                        }
                    } label: {
                        HStack {
                            if purchasing {
                                ProgressView().tint(.brandNavy)
                            }
                            Text(purchasing ? "Processing..." : "Start Free Trial")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(
                            LinearGradient(colors: [.brandGold, Color(red: 0.85, green: 0.73, blue: 0.45)],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .foregroundStyle(.brandNavy)
                    }
                    .disabled(purchasing)
                    .padding(.horizontal, 30)

                    // Restore + terms
                    VStack(spacing: 8) {
                        Button("Restore Purchases") {
                            Task { await store.restorePurchases() }
                        }
                        .font(.caption).foregroundStyle(.brandGold)

                        Text("Cancel anytime. Terms & Privacy.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.3))
                    }

                    if let error = store.error {
                        Text(error)
                            .font(.caption).foregroundStyle(.red)
                            .padding(.horizontal, 30)
                    }
                }
                .padding(.bottom, 30)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            if store.products.isEmpty {
                Task { await store.loadProducts() }
            }
            // Default select annual
            selectedProduct = store.products.first { $0.id == "com.privatetourai.annual" }
                ?? store.products.last
        }
    }
}

// MARK: - Subscription Card

struct SubscriptionCard: View {
    let product: Product
    let isSelected: Bool
    let isBestValue: Bool
    let monthlyPrice: String?
    let onTap: () -> Void

    var periodLabel: String {
        guard let sub = product.subscription else { return "" }
        switch sub.subscriptionPeriod.unit {
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Annual"
        default: return ""
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                if isBestValue {
                    Text("BEST VALUE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.brandGold, in: Capsule())
                        .foregroundStyle(.brandNavy)
                }

                Text(periodLabel)
                    .font(.headline.bold())
                    .foregroundStyle(isSelected ? .brandGold : .white)

                Text(product.displayPrice)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                if let sub = product.subscription {
                    Text("/\(sub.subscriptionPeriod.unit == .year ? "year" : sub.subscriptionPeriod.unit == .month ? "month" : "week")")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                }

                if let monthly = monthlyPrice, product.subscription?.subscriptionPeriod.unit == .year {
                    Text(monthly)
                        .font(.caption2).foregroundStyle(.brandGold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.brandNavy)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.brandGold : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
    }
}

struct FallbackCard: View {
    let name: String
    let price: String
    let period: String
    let isBestValue: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                if isBestValue {
                    Text("BEST VALUE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.brandGold, in: Capsule())
                        .foregroundStyle(.brandNavy)
                }
                Text(name).font(.headline.bold()).foregroundStyle(isSelected ? .brandGold : .white)
                Text(price).font(.title3.bold()).foregroundStyle(.white)
                Text(period).font(.caption2).foregroundStyle(.white.opacity(0.5))
                if isBestValue {
                    Text("$6.67/mo").font(.caption2).foregroundStyle(.brandGold)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Color.brandNavy)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Color.brandGold : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1))
            )
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.brandGold)
            Text(text)
                .foregroundStyle(.white)
        }
    }
}
