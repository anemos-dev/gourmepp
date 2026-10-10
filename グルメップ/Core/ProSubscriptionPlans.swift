import Foundation
import Observation
import StoreKit

enum ProSubscriptionPlan: String, CaseIterable, Identifiable {
    case monthly, annual
    var id: String { rawValue }
    var title: String { self == .monthly ? "月額プラン" : "年額プラン" }
    var unit: String { self == .monthly ? "月" : "年" }
    var referencePrice: String { self == .monthly ? "480円" : "4,500円" }
    var referenceOfferPrice: String { self == .monthly ? "320円" : "2,960円" }

    // Set these to the registered App Store products; never reuse the lifetime ID.
    var productID: String? {
        let configuration = Bundle.main.object(forInfoDictionaryKey: "ProSubscriptionProducts") as? [String: String]
        guard let value = configuration?[rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

@MainActor
@Observable
final class ProSubscriptionPlans {
    private(set) var products: [ProSubscriptionPlan: Product] = [:]
    private(set) var introductoryPlans: Set<ProSubscriptionPlan> = []
    private(set) var isLoading = false

    var isConfigured: Bool { ProSubscriptionPlan.allCases.contains { $0.productID != nil } }
    var canShowLimitedOffer: Bool {
        if !isConfigured { return true } // Design-only pricing until registered products are supplied.
        return !introductoryPlans.isEmpty
    }

    func prepare() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let ids = ProSubscriptionPlan.allCases.compactMap(\.productID)
        guard !ids.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: ids)
            var eligible: Set<ProSubscriptionPlan> = []
            var available: [ProSubscriptionPlan: Product] = [:]
            for plan in ProSubscriptionPlan.allCases {
                guard let product = loaded.first(where: { $0.id == plan.productID }),
                      let subscription = product.subscription,
                      subscription.subscriptionPeriod.unit == (plan == .monthly ? .month : .year),
                      subscription.subscriptionPeriod.value == 1 else { continue }
                available[plan] = product
                if let offer = subscription.introductoryOffer,
                   isFirstYearOffer(offer, plan: plan),
                   await subscription.isEligibleForIntroOffer {
                    eligible.insert(plan)
                }
            }
            products = available
            introductoryPlans = eligible
        } catch {
            products = [:]
            introductoryPlans = []
        }
    }

    func price(for plan: ProSubscriptionPlan, limited: Bool) -> String {
        if limited, introductoryPlans.contains(plan), let offer = products[plan]?.subscription?.introductoryOffer {
            return offer.displayPrice
        }
        if !limited, let product = products[plan] { return product.displayPrice }
        return limited ? plan.referenceOfferPrice : plan.referencePrice
    }

    func canPurchase(_ plan: ProSubscriptionPlan, limited: Bool) -> Bool {
        products[plan] != nil && (!limited || introductoryPlans.contains(plan))
    }

    private func isFirstYearOffer(_ offer: Product.SubscriptionOffer, plan: ProSubscriptionPlan) -> Bool {
        guard offer.paymentMode == .payAsYouGo || (plan == .annual && offer.paymentMode == .payUpFront) else { return false }
        let period = offer.period
        switch plan {
        case .monthly: return period.unit == .month && period.value == 1 && offer.periodCount == 12
        case .annual: return period.unit == .year && period.value == 1 && offer.periodCount == 1
        }
    }
}
