import MarqetCore
import SwiftUI

/// Horizontal card pager, 1–4 cards side by side (KONZEPT §7.2, KONZEPT-DUO-IPAD §2).
struct StorePager: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("activePage") private var storedActivePage = PageID.unsorted.rawValue
    @State private var position = ScrollPosition(idType: String.self)
    @State private var leadingIndex = 0

    var body: some View {
        GeometryReader { proxy in
            let deck = model.deck
            let metrics = PagerMetrics(size: proxy.size, fold: FoldGeometry.verticalFold(in: proxy))
            let content = SpreadLayout.contentSlots(pages: deck.pages, slots: metrics.slots, anchor: metrics.anchor)
            let layoutKey = LayoutKey(pages: deck.pages, metrics: metrics)

            ScrollView(.horizontal) {
                // Not lazy: neighbor cards must render outside the scroll bounds to peek in.
                HStack(spacing: metrics.spacing) {
                    ForEach(content) { slot in
                        slotView(slot, deck: deck, metrics: metrics)
                            .frame(width: metrics.slotWidth)
                            .padding(.vertical, 8)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition($position)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // The scroll view is narrower than the screen; its edge effect would draw a box under the bar.
            .scrollEdgeEffectHidden(true, for: .all)
            .frame(width: metrics.scrollWidth)
            .offset(x: metrics.scrollX)
            .frame(width: proxy.size.width, alignment: .leading)
            .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.8) { ids in
                didScroll(toVisible: ids, content: content, metrics: metrics)
            }
            .onChange(of: layoutKey) {
                reposition(content: content, pages: deck.pages, metrics: metrics)
            }
            .onChange(of: model.pageRequest) { _, request in
                guard let request else { return }
                model.pageRequest = nil
                navigate(to: request, content: content, pages: deck.pages, metrics: metrics)
            }
            .onChange(of: model.activePage) { _, page in
                storedActivePage = page.rawValue
            }
            .onAppear {
                if let stored = PageID(rawValue: storedActivePage) { model.activePage = stored }
                reposition(content: content, pages: deck.pages, metrics: metrics)
            }
        }
    }

    @ViewBuilder
    private func slotView(_ slot: SpreadLayout.Slot, deck: CardDeck, metrics: PagerMetrics) -> some View {
        if let page = slot.page {
            let isFocused = metrics.slots > 1 && page == model.activePage && !slot.isGhost
            PageCard(page: page, deck: deck, isFocused: isFocused)
                // "Der Fokus folgt der Hand": touching a card makes it the active one.
                .simultaneousGesture(TapGesture().onEnded {
                    if metrics.slots > 1 { model.activePage = page }
                })
        } else {
            Color.clear
        }
    }

    // MARK: Scroll ↔ active page

    private func didScroll(toVisible ids: [String], content: [SpreadLayout.Slot], metrics: PagerMetrics) {
        let indices = ids.compactMap { id in content.firstIndex { $0.id == id } }
        guard let leading = indices.min() else { return }
        let visible = SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: metrics.slots)
        if model.visiblePages != Set(visible) { model.visiblePages = Set(visible) }

        guard leading != leadingIndex else { return }
        leadingIndex = leading
        let pages = content.compactMap { $0.isGhost ? nil : $0.page }
        guard let anchored = SpreadLayout.anchoredPage(leadingIndex: leading, pages: pages) else { return }
        // Duo: the right-hand card is always the active one. iPad: keep a tapped card while visible.
        if metrics.anchor == .trailing || !visible.contains(model.activePage) {
            model.activePage = anchored
        }
    }

    private func reposition(content: [SpreadLayout.Slot], pages: [PageID], metrics: PagerMetrics) {
        // Keep the remembered page even if it is missing right now: at launch the items load after
        // the first layout, and the page reappears a moment later.
        let page = pages.contains(model.activePage) ? model.activePage : (pages.first ?? .more)
        let target = SpreadLayout.leadingIndex(forActive: page, pages: pages, slots: metrics.slots, anchor: metrics.anchor)
        guard content.indices.contains(target) else { return }
        leadingIndex = target
        position.scrollTo(id: content[target].id, anchor: .leading)
    }

    private func navigate(to page: PageID, content: [SpreadLayout.Slot], pages: [PageID], metrics: PagerMetrics) {
        model.activePage = page
        let alreadyInPlace = metrics.anchor == .trailing
            ? SpreadLayout.anchoredPage(leadingIndex: leadingIndex, pages: pages) == page
            : SpreadLayout.isVisible(page, leadingIndex: leadingIndex, content: content, slots: metrics.slots)
        guard !alreadyInPlace else { return }
        let target = SpreadLayout.leadingIndex(forActive: page, pages: pages, slots: metrics.slots, anchor: metrics.anchor)
        guard content.indices.contains(target) else { return }
        leadingIndex = target
        withAnimation(.snappy) {
            position.scrollTo(id: content[target].id, anchor: .leading)
        }
    }

    private struct LayoutKey: Equatable {
        let pages: [PageID]
        let metrics: PagerMetrics
    }
}

/// Dots in store colors; the visible range is highlighted, the active page is larger.
struct PageIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pages = model.deck.pages
        HStack(spacing: 8) {
            ForEach(pages, id: \.self) { page in
                Button {
                    model.pageRequest = page
                } label: {
                    dot(for: page)
                        .opacity(model.visiblePages.contains(page) ? 1 : 0.35)
                        .scaleEffect(page == model.activePage ? 1.35 : 1)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: page))
            }
        }
        .animation(.snappy, value: model.activePage)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dot(for page: PageID) -> some View {
        switch page {
        case .more:
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.secondary)
        case .unsorted:
            Circle().fill(Color.gray).frame(width: 7, height: 7)
        case .store(let id):
            Circle().fill(model.store(id)?.color ?? .gray).frame(width: 7, height: 7)
        }
    }

    private func label(for page: PageID) -> String {
        switch page {
        case .more: String(localized: "Weitere Läden")
        case .unsorted: String(localized: "Unsortiert")
        case .store(let id): model.store(id)?.name ?? ""
        }
    }
}

/// Routes a page to its card view.
struct PageCard: View {
    let page: PageID
    let deck: CardDeck
    var isFocused = false
    @Environment(AppModel.self) private var model

    var body: some View {
        switch page {
        case .more:
            MoreStoresCard(isFocused: isFocused)
        case .unsorted:
            StoreCard(page: page, store: nil, items: deck.items(on: page), state: nil, isFocused: isFocused)
        case .store(let id):
            if let store = model.store(id) {
                StoreCard(page: page, store: store, items: deck.items(on: page), state: deck.state(of: id), isFocused: isFocused)
            }
        }
    }
}
