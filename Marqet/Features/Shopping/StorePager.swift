import MarqetCore
import SwiftUI

/// Horizontal pager for brochures, Inbox, store lists, and the store catalog.
struct StorePager: View {
    @Binding var isComposerFocused: Bool
    @Binding var showsAddStore: Bool
    @Environment(AppModel.self) private var model
    @SceneStorage("selectedPageV2") private var storedActivePage = ""
    @State private var position = ScrollPosition(idType: String.self)
    @State private var leadingIndex = 0
    /// Bumped when a swipe crosses the midpoint to another card; drives a light haptic tick.
    @State private var swipeFeedback = 0
    /// Only the user's own swipes tick, not programmatic scrolls (launch, page dots).
    @State private var isUserScrolling = false

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
                        slotView(slot, content: content, deck: deck, metrics: metrics, horizontalSafeAreaInsets: proxy.safeAreaInsets)
                            .frame(width: metrics.slotWidth)
                            .padding(.top, 8)
                            .padding(.bottom, 32)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition($position)
            .sensoryFeedback(.selection, trigger: swipeFeedback)
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .interacting || phase == .decelerating
            }
            // Tick as soon as the nearest card changes, not when the next one is fully in view.
            .onScrollGeometryChange(for: Int.self) { geometry in
                Int((geometry.contentOffset.x / (metrics.slotWidth + metrics.spacing)).rounded())
            } action: { _, _ in
                if isUserScrolling { swipeFeedback += 1 }
            }
            // How far the pager is from the inbox toward the next card – the briefing follows it.
            .onScrollGeometryChange(for: Double.self) { geometry in
                guard metrics.slots == 1, let inbox = content.firstIndex(where: { $0.page == .unsorted }) else { return 0 }
                let position = geometry.contentOffset.x / (metrics.slotWidth + metrics.spacing)
                return min(max(position - Double(inbox), 0), 1)
            } action: { _, progress in
                if model.briefing != nil { model.briefingProgress = progress }
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // The scroll view is narrower than the screen; its edge effect would draw a box under the bar.
            .scrollEdgeEffectHidden(true, for: .all)
            .frame(width: metrics.scrollWidth)
            .offset(x: metrics.scrollX)
            .frame(width: proxy.size.width, alignment: .leading)
            // Take exactly the height left above keyboard and composer, never the cards' own
            // height: with only max set, a card taller than that space (the empty state) grows
            // the layout and pushes the composer's text field behind the keyboard.
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.composerTarget != nil, model.focusedPage == nil {
                    if metrics.slots == 1 {
                        ComposerBar(
                            isFocused: $isComposerFocused,
                            showsAddStore: $showsAddStore,
                            horizontalSafeAreaInsets: proxy.safeAreaInsets
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        let activeIndex = content.firstIndex { $0.page == model.activePage && !$0.isGhost } ?? leadingIndex
                        let offset = min(max(activeIndex - leadingIndex, 0), metrics.slots - 1)
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: metrics.scrollX + CGFloat(offset) * (metrics.slotWidth + metrics.spacing))
                            ComposerBar(
                                isFocused: $isComposerFocused,
                                showsAddStore: $showsAddStore,
                                horizontalSafeAreaInsets: proxy.safeAreaInsets
                            )
                            .frame(width: metrics.slotWidth)
                            Spacer(minLength: 0)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
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
                if model.hasLoadedItems { storedActivePage = page.rawValue }
            }
            .onChange(of: model.hasLoadedItems) { _, loaded in
                if loaded {
                    selectInitialPage(pages: deck.pages)
                    reposition(content: content, pages: deck.pages, metrics: metrics)
                }
            }
            .onChange(of: model.selectedListID) { _, _ in
                storedActivePage = ""
            }
            .onAppear {
                if model.hasLoadedItems { selectInitialPage(pages: deck.pages) }
                reposition(content: content, pages: deck.pages, metrics: metrics)
            }
            // The composer is nonmodal behind this pager. A background tap dismisses it;
            // a horizontal drag fails the tap recognizer and continues paging underneath.
            .simultaneousGesture(TapGesture().onEnded {
                if model.composerTarget != nil { model.endComposer() }
            })
        }
    }

    private func selectInitialPage(pages: [PageID]) {
        // The briefing belongs to the inbox: start there.
        if model.briefing != nil {
            model.activePage = .unsorted
            return
        }
        if let stored = PageID(rawValue: storedActivePage), pages.contains(stored) {
            model.activePage = stored
        } else if !model.unsortedItems.isEmpty {
            model.activePage = .unsorted
        } else {
            model.activePage = pages.first(where: { $0.storeID != nil }) ?? .unsorted
        }
    }

    @ViewBuilder
    private func slotView(_ slot: SpreadLayout.Slot, content: [SpreadLayout.Slot], deck: CardDeck, metrics: PagerMetrics, horizontalSafeAreaInsets: EdgeInsets) -> some View {
        if let page = slot.page {
            PageCard(page: page, deck: deck, horizontalSafeAreaInsets: horizontalSafeAreaInsets)
                // "Der Fokus folgt der Hand": touching a card makes it the active one.
                .simultaneousGesture(TapGesture().onEnded {
                    guard metrics.slots > 1 else { return }
                    if metrics.anchor == .trailing {
                        navigate(to: page, content: content, pages: deck.pages, metrics: metrics)
                    } else {
                        model.activePage = page
                    }
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

/// Neutral gray dots; the visible range is highlighted, the active page is larger.
struct PageIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pages = model.deck.pages
        let activeIndex = pages.firstIndex(of: model.activePage)
            ?? (model.activePage == .more ? pages.count - 1 : 0)
        let start = max(0, min(activeIndex - 2, pages.count - 5))
        let visible = Array(pages.dropFirst(start).prefix(5))
        HStack(spacing: 8) {
            ForEach(visible, id: \.self) { page in
                Button {
                    model.pageRequest = page
                } label: {
                    dot(for: page)
                        .opacity(model.visiblePages.contains(page) ? 1 : 0.5)
                        .scaleEffect(page == model.activePage ? 1.35 : 1)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: page))
            }
        }
        .animation(.snappy, value: model.activePage)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(start > 0 ? 0.25 : 1), location: 0),
                    .init(color: .black, location: 0.15),
                    .init(color: .black, location: 0.85),
                    .init(color: .black.opacity(start + visible.count < pages.count ? 0.25 : 1), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func dot(for page: PageID) -> some View {
        switch page {
        case .brochures:
            Image(systemName: "newspaper.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        case .more:
            Image(systemName: "storefront.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        case .unsorted:
            Image(systemName: "tray.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        case .store:
            Circle().fill(.secondary).frame(width: 7, height: 7)
        }
    }

    private func label(for page: PageID) -> String {
        switch page {
        case .brochures: String(localized: "Prospekte")
        case .unsorted: String(localized: "Inbox")
        case .more: String(localized: "Weitere Läden")
        case .store(let id): model.store(id)?.name ?? ""
        }
    }
}

/// Routes a page to its card view.
struct PageCard: View {
    let page: PageID
    let deck: CardDeck
    var horizontalSafeAreaInsets = EdgeInsets()
    @Environment(AppModel.self) private var model

    var body: some View {
        switch page {
        case .brochures:
            BrochuresCard()
        case .more:
            MoreStoresCard()
        case .unsorted:
            StoreCard(page: page, store: nil, items: deck.items(on: page), state: nil, horizontalSafeAreaInsets: horizontalSafeAreaInsets)
        case .store(let id):
            if let store = model.store(id) {
                StoreCard(page: page, store: store, items: deck.items(on: page), state: deck.state(of: id), horizontalSafeAreaInsets: horizontalSafeAreaInsets)
            }
        }
    }
}
