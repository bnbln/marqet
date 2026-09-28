import MarqetCore
import SwiftUI

/// Add or edit a customer card: scan or type the number, pick the stores it belongs to.
struct LoyaltyCardEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LoyaltyCard
    @State private var symbologyIsManual: Bool
    @State private var showsScanner = false
    @State private var confirmsDelete = false
    @State private var showsValidation = false
    private let isNew: Bool

    /// New card, optionally for a store (name and color taken from it).
    init(for store: Store?) {
        _draft = State(initialValue: LoyaltyCard(
            name: store?.name ?? "",
            payload: "",
            symbology: .code128,
            colorHex: store?.colorHex ?? "#3A3A3C",
            storeIDs: store.map { [$0.id] } ?? []
        ))
        _symbologyIsManual = State(initialValue: false)
        isNew = true
    }

    init(card: LoyaltyCard) {
        _draft = State(initialValue: card)
        _symbologyIsManual = State(initialValue: true)
        isNew = false
    }

    var body: some View {
        NavigationStack {
            Form {
                if BarcodeScanner.isAvailable {
                    Section {
                        Button("Karte scannen", systemImage: "barcode.viewfinder") { showsScanner = true }
                    } footer: {
                        Text("Halte den Barcode deiner Kundenkarte vor die Kamera.")
                    }
                }

                Section {
                    TextField("Name, z. B. Payback", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    TextField("Kartennummer", text: $draft.payload)
                        // Digits first, letters one tap away: most cards are numeric, some are not.
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.body.monospaced())
                    Picker("Barcode-Typ", selection: Binding(
                        get: { draft.symbology },
                        set: { draft.symbology = $0; symbologyIsManual = true }
                    )) {
                        ForEach(BarcodeSymbology.allCases, id: \.self) { symbology in
                            Text(symbology.title).tag(symbology)
                        }
                    }
                } header: {
                    Text("Karte")
                } footer: {
                    if let message = validationMessage, showsValidation || !draft.payload.isEmpty {
                        Text(message).foregroundStyle(.red)
                    }
                }

                if draft.validationError == nil || draft.validationError == .missingName {
                    Section("Vorschau") {
                        BarcodeView(payload: draft.symbology.normalized(draft.payload), symbology: draft.symbology)
                            .frame(maxWidth: BarcodeView.isSquare(draft.symbology) ? 160 : .infinity)
                            .frame(height: BarcodeView.isSquare(draft.symbology) ? 160 : 80)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(.white, in: .rect(cornerRadius: 12))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    ForEach(model.sortedStores) { store in
                        Button {
                            toggle(store)
                        } label: {
                            HStack(spacing: 12) {
                                StoreBadge(store: store, size: 28)
                                Text(store.name).foregroundStyle(.primary)
                                Spacer()
                                if draft.storeIDs.contains(store.id) {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(store.readableColor)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft.storeIDs.contains(store.id) ? .isSelected : [])
                    }
                } header: {
                    Text("Gilt in diesen Läden")
                } footer: {
                    Text("Die Karte erscheint im Vollbild dieser Läden. Eine Payback-Karte kannst du mehreren Läden zuordnen.")
                }

                Section("Farbe") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(colorChoices, id: \.self) { hex in
                                Button {
                                    draft.colorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if draft.colorHex == hex {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(Color(hex: hex).contrastingForeground)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(hex)
                                .accessibilityAddTraits(draft.colorHex == hex ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }

                if !isNew {
                    Section {
                        Button("Kundenkarte löschen", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Neue Kundenkarte" : "Kundenkarte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save)
                }
            }
            .onChange(of: draft.payload) { _, payload in
                // Typed numbers pick their type until the user chooses one.
                if !symbologyIsManual { draft.symbology = BarcodeSymbology.guess(for: payload) }
            }
            .sheet(isPresented: $showsScanner) {
                NavigationStack {
                    BarcodeScanner { payload, symbology in
                        draft.payload = payload
                        draft.symbology = symbology
                        symbologyIsManual = true
                        showsScanner = false
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Karte scannen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { showsScanner = false }
                        }
                    }
                }
            }
            .confirmationDialog("Kundenkarte löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    model.deleteLoyaltyCard(draft.id)
                    dismiss()
                }
            }
        }
        .tint(.primary)
    }

    private func toggle(_ store: Store) {
        if let index = draft.storeIDs.firstIndex(of: store.id) {
            draft.storeIDs.remove(at: index)
        } else {
            draft.storeIDs.append(store.id)
        }
    }

    private func save() {
        guard draft.validationError == nil else {
            showsValidation = true
            return
        }
        if model.saveLoyaltyCard(draft) { dismiss() }
    }

    /// Colors of the chosen stores first, then a neutral set.
    private var colorChoices: [String] {
        let storeColors = draft.storeIDs.compactMap { model.store($0)?.colorHex }
        var seen = Set<String>()
        return (storeColors + [draft.colorHex] + Self.palette).filter { seen.insert($0.uppercased()).inserted }
    }

    private static let palette = ["#3A3A3C", "#003EAA", "#CC071E", "#1F8A4C", "#F2A900", "#7B3FA0", "#0A7EA4"]

    private var validationMessage: String? {
        switch draft.validationError {
        case nil: nil
        case .missingName: String(localized: "Gib der Karte einen Namen.")
        case .missingNumber: String(localized: "Scanne die Karte oder gib die Nummer ein.")
        case .invalidDigits: String(localized: "Dieser Barcode-Typ enthält nur Ziffern.")
        case .wrongLength(let expected): String(localized: "Die Nummer braucht \(expected) Ziffern.")
        case .wrongCheckDigit: String(localized: "Die Prüfziffer passt nicht: Prüf die Nummer oder wähle einen anderen Barcode-Typ.")
        case .unsupportedCharacters: String(localized: "Code 128 erlaubt keine Umlaute oder Sonderzeichen.")
        }
    }
}

extension BarcodeSymbology {
    var title: String {
        switch self {
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .code128: "Code 128"
        case .qr: String(localized: "QR-Code")
        case .pdf417: "PDF417"
        case .aztec: "Aztec"
        }
    }
}
