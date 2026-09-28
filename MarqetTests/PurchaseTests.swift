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

    func makeManager() -> PurchaseManager {
        PurchaseManager { [probe] in probe.entitled = $0 }
    }

    @Test func productLoadsAsFamilyShareableNonConsumable() async throws {
        let manager = makeManager()
        await manager.loadProduct()
        let product = try #require(manager.product)
        #expect(product.id == PurchaseManager.proProductID)
        #expect(product.type == .nonConsumable)
        #expect(product.isFamilyShareable)
    }

    @Test func purchaseUnlocksAndRefundLocksAgain() async throws {
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

    @Test func askToBuyStaysPendingAndLocked() async throws {
        session.askToBuyEnabled = true
        let manager = makeManager()
        await manager.start()
        #expect(await manager.purchase() == false)
        #expect(manager.state == .pending)
        #expect(!probe.entitled)
    }

    @Test func existingPurchaseIsFoundAtLaunch() async throws {
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
