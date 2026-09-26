import Foundation
import Observation
import StoreKit

/// Marqet Pro as a one-time, family-shareable purchase (KONZEPT §9.4).
///
/// StoreKit is the source of truth: current entitlements at launch, `Transaction.updates` while
/// running (purchases on other devices, family sharing, refunds). The result is pushed into
/// `AppModel.hasProEntitlement`, which caches it for offline launches.
@MainActor
@Observable
final class PurchaseManager {
    static let proProductID = "app.marqet.Marqet.pro"

    enum State: Equatable {
        case idle
        case loading
        case purchasing
        /// Waiting for approval, e.g. Ask to Buy.
        case pending
        case failed(String)
    }

    private(set) var product: Product?
    private(set) var state: State = .idle
    private(set) var isFamilyShared = false

    @ObservationIgnored private let onEntitlementChange: @MainActor (Bool) -> Void
    @ObservationIgnored private var updates: Task<Void, Never>?

    init(onEntitlementChange: @escaping @MainActor (Bool) -> Void) {
        self.onEntitlementChange = onEntitlementChange
    }

    func start() async {
        listenForTransactions()
        await refreshEntitlement()
        await loadProduct()
    }

    func loadProduct() async {
        guard product == nil else { return }
        state = .loading
        do {
            product = try await Product.products(for: [Self.proProductID]).first
            state = product == nil ? .failed(String(localized: "Marqet Pro ist gerade nicht verfügbar.")) : .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Returns `true` if Pro is unlocked afterwards.
    @discardableResult
    func purchase() async -> Bool {
        if product == nil { await loadProduct() }
        guard let product else { return false }
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlement()
                state = .idle
                return true
            case .pending:
                state = .pending
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
        return false
    }

    /// "Käufe wiederherstellen" – syncs with the App Store, then re-reads the entitlements.
    func restore() async {
        state = .loading
        do {
            try await AppStore.sync()
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var entitled = false
        var familyShared = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.proProductID,
                  transaction.revocationDate == nil else { continue }
            entitled = true
            familyShared = transaction.ownershipType == .familyShared
        }
        isFamilyShared = familyShared
        onEntitlementChange(entitled)
    }

    private func listenForTransactions() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified(_, let error): throw error
        }
    }
}
