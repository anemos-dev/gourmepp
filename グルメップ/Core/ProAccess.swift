import CryptoKit
import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class ProAccessController {
    static let lifetimeProductID = "com.anemos.gourmepp.pro.lifetime"

    private(set) var product: Product?
    private(set) var hasPurchasedPro = false
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    #if DEBUG
    private(set) var hasDeveloperPro = UserDefaults.standard.bool(forKey: "pro.developerCodeUnlocked")
    #endif

    var isProUnlocked: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return ProcessInfo.processInfo.arguments.contains("-unlockPro")
        }
        return hasPurchasedPro || hasDeveloperPro || ProcessInfo.processInfo.arguments.contains("-unlockPro")
        #else
        hasPurchasedPro
        #endif
    }

    var displayPrice: String {
        product?.displayPrice ?? "App Storeで価格を確認"
    }

    #if DEBUG
    @discardableResult
    func redeemDeveloperCode(_ code: String) -> Bool {
        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        let digest = SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == "58ff5d065f71f79c644b80c37a950950a5bf5318ecc5930297c6051de764b8c1" else {
            return false
        }
        hasDeveloperPro = true
        UserDefaults.standard.set(true, forKey: "pro.developerCodeUnlocked")
        return true
    }
    #endif

    func prepare() async {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        #endif
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            product = try await Product.products(for: [Self.lifetimeProductID]).first
            try await refreshEntitlements()
        } catch {
            errorMessage = "購入情報を読み込めませんでした。通信環境を確認して、もう一度お試しください。"
        }
    }

    func observeTransactions() async {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        #endif
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }
            do {
                let transaction = try verified(result)
                await transaction.finish()
                try await refreshEntitlements()
            } catch {
                errorMessage = "購入情報を確認できませんでした。"
            }
        }
    }

    func purchase() async {
        guard let product, !isPurchasing else {
            if product == nil {
                errorMessage = "商品情報を読み込めませんでした。しばらくしてから、もう一度お試しください。"
            }
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                try await refreshEntitlements()
            case .pending:
                errorMessage = "購入は承認待ちです。承認後に自動で反映されます。"
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "購入を完了できませんでした。"
            }
        } catch {
            errorMessage = "購入を完了できませんでした。時間をおいて、もう一度お試しください。"
        }
    }

    func restorePurchases() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            try await refreshEntitlements()
            if !hasPurchasedPro {
                errorMessage = "復元できる購入が見つかりませんでした。"
            }
        } catch {
            errorMessage = "購入を復元できませんでした。通信環境を確認してください。"
        }
    }

    private func refreshEntitlements() async throws {
        var ownsPro = false
        for await result in Transaction.currentEntitlements {
            let transaction = try verified(result)
            guard transaction.productID == Self.lifetimeProductID else { continue }
            if transaction.revocationDate == nil {
                ownsPro = true
            }
        }
        hasPurchasedPro = ownsPro
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw ProPurchaseError.failedVerification
        }
    }
}

private enum ProPurchaseError: Error {
    case failedVerification
}
