import MarqetCore
import SwiftUI

/// Horizontal pager for brochures, Inbox, store lists, and the store catalog.
struct StorePager: View {
    @Binding var isComposerFocused: Bool
    @Binding var showsAddStore: Bool
    @Environment(AppModel.self) private var model
    // The inbox is the first visible target from the very first layout. The deck keeps
    // Angebote before it for paging, but that must never become the launch position.
    @State private var position = ScrollPosition(id: PageID.unsorted.rawValue, anchor: .leading)
    @State private var leadingIndex = 0
    /// Bumped when a swipe crosses the midpoint to another card; drives a light haptic tick.
    @State private var swipeFeedback = 0
    /// Only the user's own swipes tick, not programmatic scrolls (launch, page dots).
    @State private var isUserScrolling = false
    /// Index of the card nearest to the scroll offset (the leading card of the visible spread).
    @State private var scrolledIndex = 0

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
                            // Keep the active card close to the composer while typing so more
                            // of its list remains visible above the keyboard.
                            .padding(.bottom, model.composerTarget == nil ? 32 : 8)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition($position)
            .sensoryFeedback(.selection, trigger: swipeFeedback)
            .onScrollPhaseChange { oldPhase, phase in
                isUserScrolling = phase == .interacting || phase == .decelerating
                // A swipe ends: its card becomes the active one. Only the user's swipe picks the
                // active card – layout changes (Duo book ↔ flat, rotation, keyboard) briefly show
                // the old offset under the new card widths and would make a neighbor active.
                if !isUserScrolling, oldPhase == .interacting || oldPhase == .decelerating {
                    adoptScrolledPage(content: content, metrics: metrics)
                }
            }
            // The nearest card by offset, not by visibility: with the composer and keyboard up,
            // no card is 80 % visible any more. Ticks as soon as the nearest card changes.
            .onScrollGeometryChange(for: Int.self) { geometry in
                Int((geometry.contentOffset.x / (metrics.slotWidth + metrics.spacing)).rounded())
            } action: { _, index in
                scrolledIndex = index
                if isUserScrolling { swipeFeedback += 1 }
                let visible = Set(SpreadLayout.visiblePages(leadingIndex: clamped(index, in: content), content: content, slots: metrics.slots))
                if model.visiblePages != visible { model.visiblePages = visible }
                // Known gap: the page indicator's active dot used to move only once the swipe
                // ended, visibly lagging the finger. Follow the drag (and fling) live; the phase
                // end below still fires once more so programmatic/layout scrolls settle too.
                if isUserScrolling { adoptScrolledPage(content: content, metrics: metrics) }
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
            // The card under a dragged item holds still – items only move inside their store.
            .scrollDisabled(model.isDraggingItem)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // The scroll view is narrower than the screen; its edge effect would draw a box under the bar.
            .scrollEdgeEffectHidden(true, for: .all)
            // The composer is nonmodal behind this pager. A tap on the cards dismisses it; a
            // horizontal drag fails the tap recognizer and continues paging underneath. Attached
            // before the composer inset on purpose: a tap on a chip must not end the composer,
            // or the keyboard drops and the cards grow before the composer starts again.
            .simultaneousGesture(TapGesture().onEnded {
                if model.composerTarget != nil { model.endComposer() }
            })
            .frame(width: metrics.scrollWidth)
            .offset(x: metrics.scrollX)
            .frame(width: proxy.size.width, alignment: .leading)
            // Take exactly the height left above keyboard and composer, never the cards' own
            // height: with only max set, a card taller than that space (the empty state) grows
            // the layout and pushes the composer's text field behind the keyboard.
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if model.composerTarget != nil, model.focusedPage == nil {
                        let activeIndex = content.firstIndex { $0.page == model.activePage && !$0.isGhost } ?? leadingIndex
                        let offset = min(max(activeIndex - leadingIndex, 0), metrics.slots - 1)
                        let horizontalOffset = metrics.slots == 1
                            ? 0
                            : metrics.scrollX + CGFloat(offset) * (metrics.slotWidth + metrics.spacing)

                        ZStack(alignment: .leading) {
                            ComposerBar(
                                isFocused: $isComposerFocused,
                                showsAddStore: $showsAddStore,
                                horizontalSafeAreaInsets: proxy.safeAreaInsets
                            )
                            .frame(maxWidth: metrics.slots == 1 ? .infinity : metrics.slotWidth)
                            .offset(x: horizontalOffset)
                            .animation(.smooth, value: horizontalOffset)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // Animate the footer's entrance in isolation. A parent animation here also
                // animates the pager's keyboard-driven height change and lifts the cards.
                .animation(.snappy, value: model.composerTarget == nil)
            }
            .onChange(of: layoutKey) {
                reposition(content: content, pages: deck.pages, metrics: metrics)
            }
            .onChange(of: model.pageRequest) { _, request in
                guard let request else { return }
                model.pageRequest = nil
                navigate(to: request, content: content, pages: deck.pages, metrics: metrics)
            }
            .onChange(of: model.hasLoadedItems) { _, loaded in
                if loaded {
                    reposition(content: content, pages: deck.pages, metrics: metrics)
                }
            }
            .onAppear {
                reposition(content: content, pages: deck.pages, metrics: metrics)
            }
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

    private func clamped(_ index: Int, in content: [SpreadLayout.Slot]) -> Int {
        min(max(index, 0), max(content.count - 1, 0))
    }

    private func adoptScrolledPage(content: [SpreadLayout.Slot], metrics: PagerMetrics) {
        guard !content.isEmpty else { return }
        let leading = clamped(scrolledIndex, in: content)
        guard leading != leadingIndex else { return }
        leadingIndex = leading
        let visible = SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: metrics.slots)
        let pages = content.compactMap { $0.isGhost ? nil : $0.page }
        guard let anchored = SpreadLayout.anchoredPage(leadingIndex: leading, pages: pages, slots: metrics.slots) else { return }
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
        let target = SpreadLayout.leadingIndex(forActive: page, pages: pages, slots: metrics.slots, anchor: metrics.anchor)
        let alreadyInPlace = metrics.anchor == .trailing
            ? target == leadingIndex
            : SpreadLayout.isVisible(page, leadingIndex: leadingIndex, content: content, slots: metrics.slots)
        guard !alreadyInPlace else { return }
        guard content.indices.contains(target) else { return }
        leadingIndex = target
        withAnimation(.smooth) {
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
        case .map:
            Image(systemName: "map.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
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
        case .map: String(localized: "In der Nähe")
        case .brochures: String(localized: "Angebote")
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
        case .map:
            MapCard()
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
