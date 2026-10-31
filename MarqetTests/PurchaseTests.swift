import Foundation
import MarqetPersistence
import MarqetReminders
import StoreKit
import StoreKitTest
import Testing
@testable import Marqet

/// Collects entitlement changes pushed by `PurchaseManager`.
@MainActor
final class EntitlementProbe {
    var entitled = false
}

@Suite("Purchases (StoreKit)", .serialized)
@MainActor
struct PurchaseTests {
    let session: SKTestSession
    let probe = EntitlementProbe()

    init() throws {
        session = try SKTestSession(configurationFileNamed: "Marqet")
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
    }

    /// Polls `condition` for up to three seconds.
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<30 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    func makeManager(productID: String = PurchaseManager.proProductID) -> PurchaseManager {
        PurchaseManager(productID: productID) { [probe] in probe.entitled = $0 }
    }

    /// Whether StoreKit testing serves the Pro product from `Marqet.storekit`. Until Pro exists in
    /// App Store Connect it does not (also not locally), so the purchase flow tests are skipped then.
    static func storeKitServesPro() async -> Bool {
        guard let session = try? SKTestSession(configurationFileNamed: "Marqet") else { return false }
        session.disableDialogs = true
        let products = try? await Product.products(for: [PurchaseManager.proProductID])
        return products?.isEmpty == false
    }

    nonisolated static let needsProProduct = ConditionTrait.enabled("StoreKit liefert noch kein Marqet-Pro-Produkt") {
        await storeKitServesPro()
    }

    @Test func missingProductShowsNotYetAvailableAndStaysLocked() async {
        let manager = makeManager(productID: "app.marqet.Marqet.missing")
        await manager.start()
        #expect(manager.product == nil)
        #expect(manager.state == .unavailable)
        #expect(await manager.purchase() == false)
        #expect(!probe.entitled)
    }

    @Test(needsProProduct) func productLoadsAsFamilyShareableNonConsumable() async throws {
        let manager = makeManager()
        await manager.loadProduct()
        let product = try #require(manager.product)
        #expect(product.id == PurchaseManager.proProductID)
        #expect(product.type == .nonConsumable)
        #expect(product.isFamilyShareable)
    }

    @Test(needsProProduct) func purchaseUnlocksAndRefundLocksAgain() async throws {
        let manager = makeManager()
        await manager.start()
        #expect(!probe.entitled)

        #expect(await manager.purchase())
        #expect(probe.entitled)

        let transaction = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        // The revocation arrives asynchronously via Transaction.updates, which the manager listens to.
        #expect(await eventually { !probe.entitled })
    }

    @Test(needsProProduct) func askToBuyStaysPendingAndLocked() async throws {
        session.askToBuyEnabled = true
        let manager = makeManager()
        await manager.start()
        #expect(await manager.purchase() == false)
        #expect(manager.state == .pending)
        #expect(!probe.entitled)
    }

    @Test(needsProProduct) func existingPurchaseIsFoundAtLaunch() async throws {
        try await session.buyProduct(identifier: PurchaseManager.proProductID)
        let manager = makeManager()
        await manager.start()
        // Found either in the launch read or, if StoreKit lags, via Transaction.updates.
        #expect(await eventually { probe.entitled })
    }

    @Test func entitlementDrivesProIndependentOfDeveloperOverride() throws {
        let model = AppModel(
            gateway: InMemoryReminderGateway(),
            container: try PersistenceContainer.make(inMemory: true),
            intelligence: UnavailableIntelligence(),
            defaults: try #require(UserDefaults(suiteName: "purchase-\(UUID().uuidString)"))
        )
        #expect(!model.isPro)
        model.hasProEntitlement = true
        #expect(model.isPro)
        #expect(!model.developerProOverride)
        model.hasProEntitlement = false
        #expect(!model.isPro)
    }
}
