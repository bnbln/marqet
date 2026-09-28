import MarqetCore
import SwiftUI
import UIKit

/// The checkout view: the store's customer cards full screen, barcode on white, screen at full
/// brightness until it closes (KONZEPT §2.1). Several cards: swipe sideways.
struct LoyaltyCardScreen: View {
    let cards: [LoyaltyCard]
    var initialCardID: LoyaltyCard.ID?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: LoyaltyCard.ID?
    @State private var editedCard: LoyaltyCard?
    @State private var brightness = ScreenBrightness()

    /// Cards follow the model, so edits and deletions show up right away.
    private var currentCards: [LoyaltyCard] {
        cards.compactMap { card in model.loyaltyCards.first { $0.id == card.id } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if currentCards.isEmpty {
                    ContentUnavailableView("Keine Kundenkarte", systemImage: "wallet.pass")
                } else {
                    TabView(selection: $selection) {
                        ForEach(currentCards) { card in
                            LoyaltyCardFace(card: card)
                                .padding(.horizontal, 20)
                                .tag(Optional(card.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: currentCards.count > 1 ? .always : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(selectedCard?.name ?? String(localized: "Kundenkarte"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig", systemImage: "xmark") { dismiss() }
                }
                if let selectedCard {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Bearbeiten", systemImage: "pencil") { editedCard = selectedCard }
                    }
                }
            }
            .sheet(item: $editedCard) { card in
                LoyaltyCardEditor(card: card)
            }
        }
        // Text and bar icons in the text color, never the accent (`.primary` does not reach
        // the UIKit navigation bar, the label color does).
        .tint(Color(uiColor: .label))
        .onAppear {
            selection = initialCardID ?? cards.first?.id
            brightness.raise()
        }
        .onDisappear { brightness.restore() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            brightness.restore()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            brightness.raise()
        }
        .onChange(of: currentCards.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    private var selectedCard: LoyaltyCard? {
        currentCards.first { $0.id == selection } ?? currentCards.first
    }
}

/// One card: colored strip with the name, barcode on white, number to read out.
struct LoyaltyCardFace: View {
    let card: LoyaltyCard

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wallet.pass.fill")
                Text(card.name)
                    .font(.title3.bold())
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(Color(hex: card.colorHex).contrastingForeground)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(hex: card.colorHex))

            VStack(spacing: 14) {
                BarcodeView(payload: card.payload, symbology: card.symbology)
                    .frame(maxWidth: BarcodeView.isSquare(card.symbology) ? 240 : .infinity)
                    .frame(height: BarcodeView.isSquare(card.symbology) ? 240 : 130)
                Text(card.payload)
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .foregroundStyle(.black)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(.white)
        }
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Raises the screen to full brightness for scanning and puts it back afterwards.
@MainActor
struct ScreenBrightness {
    private var previous: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    mutating func raise() {
        guard previous == nil, let screen else { return }
        previous = screen.brightness
        screen.brightness = 1
    }

    mutating func restore() {
        guard let previous, let screen else { return }
        screen.brightness = previous
        self.previous = nil
    }
}

extension Color {
    /// Black or white, whichever reads better on this color (for card strips in any color).
    var contrastingForeground: Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? .black : .white
    }
}
