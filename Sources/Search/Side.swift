import SwiftUI

/// The tabs, down the left instead of across the top.
///
/// The same pieces as the strip — the grey that slides to the tab you picked,
/// the pinned squares, the cross that appears under the pointer — laid out the
/// other way. The traffic lights keep their corner; the column starts under
/// them and the page takes the whole height beside it.
struct SideBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @Namespace private var pill

    @State private var landing = false
    /// The width the column had when the edge was picked up.
    @State private var grabbed: CGFloat?
    @State private var onEdge = false

    /// A pin, picked up out of the grid — a separate state from the loose
    /// rows above, since the two gestures never happen at once but move on
    /// two different axes.
    /// The neighbouring spaces' own grey, apart from this one's.
    @Namespace private var before
    @Namespace private var after

    @State private var pinDragging: Tab.ID?
    @State private var pinFrom = 0
    @State private var pinTravel: CGSize = .zero

    private static let row: CGFloat = 28
    private static let gap: CGFloat = 2
    private static let square: CGFloat = 34
    private static let pinGap: CGFloat = 4
    /// The line between the pins and the day's tabs, with its air.
    private static let divider: CGFloat = 13
    /// How far a folder's pins sit in from the folder's own row.
    private static let indent: CGFloat = 14

    var body: some View {
        ZStack(alignment: .top) {
            // Not under the card for a new space: it isn't made of views that
            // would take the click first.
            DragStrip(reserved: 0, below: browser.makingSpace ? .greatestFiniteMagnitude : rowsEnd)

            // The band the lights sit in is this mode's title bar: the window
            // is dragged by it and a double-click fills the screen with it,
            // everywhere but over the three doors, which take their own
            // clicks. The lights are the title bar's own and answer first.
            HStack(spacing: 0) {
                DragStrip()
                    .frame(width: 10 + Metrics.sideLights)
                Color.clear
                    .frame(width: Metrics.helm)
                    .allowsHitTesting(false)
                DragStrip()
            }
            .frame(height: Metrics.strip)

            VStack(alignment: .leading, spacing: 0) {
                // The traffic lights' corner, with back, forward and reload
                // sitting right of them — the same three doors as the top
                // bar, moved beside the lights since there's no far end of a
                // row to put them at in this mode.
                HStack(spacing: 0) {
                    Color.clear.frame(width: Metrics.sideLights)
                    Helm(browser: browser)
                    Spacer(minLength: 0)
                }
                .frame(height: Metrics.strip)

                // The spaces side by side, as pages: two fingers sideways move
                // the one on screen and the next one together, the next one
                // coming in as this one goes, with nothing between them.
                pages

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            // Clear of the foot, which sits over the column's bottom edge.
            .padding(.bottom, SideBar.footHeight)

            VStack {
                Spacer()
                foot
            }
        }
        .frame(width: prefs.sideWidth)
        .frame(maxHeight: .infinity)
        // Rows on their way to or from another space stay in the column.
        .clipped()
        .onAppear { SpaceSwipe.shared.start(for: browser) }
        .background(landing ? Palette.hover : Palette.ground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.hairline).frame(width: 1)
        }
        .overlay(alignment: .trailing) { edge }
        .onDrop(of: [.url, .text], isTargeted: $landing) { providers in
            browser.take(providers)
        }
        .animation(Motion.quick, value: landing)
        .animation(Motion.glide, value: browser.activeID)
        .animation(Motion.glide, value: browser.editingTab)
        .animation(Motion.settle, value: browser.tabs.map(\.id))
        .animation(Motion.settle, value: browser.pinnedCount)
        .animation(Motion.settle, value: browser.favoriteCount)
    }

    /// The column's edge: pull it to make the column wider or narrower,
    /// double-click it to put it back. The hairline darkens under the pointer
    /// so the edge says it can be taken before it is.
    private var edge: some View {
        Rectangle()
            .fill(Palette.ink.opacity(onEdge || grabbed != nil ? 0.18 : 0))
            .frame(width: onEdge || grabbed != nil ? 2 : 1)
            .frame(width: 9)
            .contentShape(Rectangle())
            .onHover { over in
                onEdge = over
                if over { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if grabbed == nil { grabbed = prefs.sideWidth }
                        let wanted = (grabbed ?? prefs.sideWidth) + value.translation.width
                        prefs.sideWidth = min(Metrics.sideMax, max(Metrics.sideMin, wanted))
                    }
                    .onEnded { _ in grabbed = nil }
            )
            .modifier(OneClick(double: true) {
                withAnimation(Motion.settle) { prefs.sideWidth = Metrics.side }
            })
            .animation(Motion.quick, value: onEdge)
    }

    // MARK: - the spaces, as pages

    /// Where the space on screen sits among them: one past the last while
    /// the card for a new one is up.
    private var spaceAt: Int {
        browser.makingSpace ? browser.spaces.count : (browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0)
    }

    private var pages: some View {
        let width = prefs.sideWidth
        let swipe = browser.spaceSwipe
        let at = spaceAt
        return ZStack(alignment: .topLeading) {
            page(at, pill: pill)
                .offset(x: swipe)
            // Only while the fingers are bringing one in: the one they are
            // bringing, a page's width away.
            if swipe > 0, at > 0 {
                page(at - 1, pill: before)
                    .offset(x: swipe - width)
            }
            if swipe < 0, at < browser.spaces.count {
                page(at + 1, pill: after)
                    .offset(x: swipe + width)
            }
        }
        // The pages are the column's whole width, each with its own margin.
        .padding(.horizontal, -10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// One space's page: the rows on screen, another space's rows as they
    /// were left, or past the last the card for a new one.
    @ViewBuilder
    private func page(_ index: Int, pill: Namespace.ID) -> some View {
        Group {
            if index == browser.spaces.count {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    NewSpaceCard(browser: browser)
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            } else if browser.spaces[index].id == browser.spaceID {
                VStack(alignment: .leading, spacing: 0) {
                    if browser.favoriteCount > 0 {
                        pinned
                            .padding(.bottom, 10)
                    }
                    // A row too long for the window scrolls between the cards
                    // and the foot, rather than running under the lights at one
                    // end and the foot at the other. While it fits it stays a
                    // plain stack, and the space under it is still the
                    // window's to be dragged by. Inside the page: the swipe
                    // between spaces moves the page, scroll and all.
                    ViewThatFits(in: .vertical) {
                        rows
                        ScrollViewReader { proxy in
                            // The scroll view reaches into the margin on
                            // the right and the rows keep it inside, so the
                            // system's bar lands in the margin beside them
                            // rather than over the cross on the tab under the
                            // pointer. The column's edge lies over that margin
                            // and answers first, so the bar never fights the
                            // resize; the wheel and the trackpad still scroll.
                            ScrollView(.vertical) {
                                rows.padding(.trailing, 10)
                            }
                            .padding(.trailing, -10)
                            // The tab you go to is the tab you see — ⌘1–⌘9,
                            // ⇧⌘], a link opening beside the one on screen.
                            .onChange(of: browser.activeID) { _, id in
                                guard let id else { return }
                                withAnimation(Motion.glide) { proxy.scrollTo(id) }
                            }
                            .onAppear {
                                if let id = browser.activeID { proxy.scrollTo(id, anchor: .center) }
                            }
                        }
                    }
                }
            } else {
                preview(browser.parked[browser.spaces[index].id] ?? Parked(tabs: [], active: nil), pill: pill)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: prefs.sideWidth, alignment: .topLeading)
    }

    /// Another space's rows, drawn with the same pieces as this one's so the
    /// two read as one column while they pass — and nothing to press until
    /// it is the one on screen.
    private func preview(_ row: Parked, pill: Namespace.ID) -> some View {
        let pins = row.tabs.filter { $0.pin != nil && $0.shelf == .favorites }
        let pinsAsRows = row.tabs.filter { $0.pin != nil && $0.shelf == .pins }
        let rest = row.tabs.filter { $0.pin == nil }
        let cols = SideBar.pinColumns(pins.count)
        let width = pinWidth(for: pins.count)
        let height = min(SideBar.square, width)
        return VStack(alignment: .leading, spacing: 0) {
            if !pins.isEmpty {
                VStack(spacing: 0) {
                    PinGrid(columns: cols, width: width, height: height, spacing: SideBar.pinGap) {
                        ForEach(pins) { tab in
                            PinSquare(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active,
                                      pill: pill, width: width, height: height)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            if !pinsAsRows.isEmpty {
                let drawn = Shelves.pinnedRows(Browser.slots(of: pinsAsRows), folders: row.folders, active: row.active)
                VStack(spacing: SideBar.gap) {
                    ForEach(drawn) { line in
                        switch line {
                        case .folder(let id):
                            if let folder = row.folders.first(where: { $0.id == id }) {
                                FolderRow(browser: browser, folder: folder)
                            }
                        case .pin(let id, let folder):
                            if let tab = pinsAsRows.first(where: { $0.id == id }) {
                                SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active, pill: pill, close: {})
                                    .padding(.leading, folder == nil ? 0 : SideBar.indent)
                            }
                        }
                    }
                }
                divider
            }
            VStack(spacing: SideBar.gap) {
                ForEach(Splits.todayRows(rest.map(\.id), splits: row.splits)) { line in
                    switch line {
                    case .tab(let id):
                        if let tab = rest.first(where: { $0.id == id }) {
                            SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == row.active, pill: pill, close: {})
                        }
                    case .split(let id):
                        if let split = row.splits.first(where: { $0.id == id }) {
                            SplitRow(browser: browser, split: split, tabs: row.tabs, interactive: false)
                        }
                    }
                }
            }
            newTab
        }
        .allowsHitTesting(false)
    }

    /// Where the rows stop and the window's own drag area starts. Added up
    /// from what was drawn rather than measured: a measurement would arrive a
    /// frame late, and for one frame the whole column would drag the window.
    private var rowsEnd: CGFloat {
        let favorites = browser.favoriteCount
        let cols = SideBar.pinColumns(favorites)
        let gridRows = favorites == 0 ? 0 : (favorites + cols - 1) / cols
        let grid = gridRows == 0 ? 0
            : CGFloat(gridRows) * pinHeight + CGFloat(gridRows - 1) * SideBar.pinGap + 10
        let loose = CGFloat(browser.todayRows.count) * (SideBar.row + SideBar.gap)
        return Metrics.strip + grid + pinBlock + loose + SideBar.row + 8
    }

    // MARK: - the pinned squares

    private var favoriteTabs: [Tab] { browser.tabs.filter { $0.pin != nil && $0.shelf == .favorites } }
    private var pinTabs: [Tab] { browser.tabs.filter { $0.pin != nil && $0.shelf == .pins } }

    /// Three columns is the block's own shape — up to six pins, that's two
    /// full rows, and one or two is just those same three places with a
    /// couple of them empty rather than a lonely row of its own width. Only
    /// past six does the block widen, one column at a time, to stay at two
    /// rows for as long as that's a reasonable shape at all.
    private static func pinColumns(_ count: Int) -> Int {
        max(3, (count + 1) / 2)
    }

    /// However many columns the count calls for, they split the row's own
    /// width between them — the row is what fills edge to edge, not each
    /// cell on its own, so this grows past 34 just as readily as it shrinks
    /// below it.
    private var pinWidth: CGFloat { pinWidth(for: browser.favoriteCount) }

    private func pinWidth(for count: Int) -> CGFloat {
        let cols = SideBar.pinColumns(count)
        guard cols > 0 else { return SideBar.square }
        let available = prefs.sideWidth - 20 - CGFloat(cols - 1) * SideBar.pinGap
        return max(20, available / CGFloat(cols))
    }

    /// The one dimension that doesn't chase the sidebar's width: past three
    /// columns' worth of room a cell would otherwise turn into a big square
    /// rather than the wide, short button pinned tabs actually look like
    /// everywhere else in this app. It only shrinks below 34 alongside the
    /// width, once a narrow column leaves no other choice.
    private var pinHeight: CGFloat {
        min(SideBar.square, pinWidth)
    }

    /// The grid itself: fixed-size cells, left-aligned, so a half-empty last
    /// row holds its ground rather than stretching to fill it.
    private var pinned: some View {
        let tabs = favoriteTabs
        let cols = SideBar.pinColumns(tabs.count)
        let width = pinWidth
        let height = pinHeight
        // Measured in the grid's own space, not the square's: a square that
        // has just been moved to a new cell would otherwise report the drag
        // from where it now is, the target would jump back, and the square
        // would shuttle between two cells for as long as the finger stayed.
        return VStack(spacing: 0) { PinGrid(columns: cols, width: width, height: height, spacing: SideBar.pinGap) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let held = pinDragging == tab.id
                PinSquare(
                    browser: browser,
                    prefs: prefs,
                    tab: tab,
                    live: tab.id == browser.activeID,
                    pill: pill,
                    width: width,
                    height: height
                )
                .offset(pinOffset(held: held, index: index, columns: cols))
                // Under the hand exactly, as a row is (see the rows below).
                .transaction { if held { $0.animation = nil } }
                .zIndex(held ? 1 : 0)
                .shadow(color: .black.opacity(held ? 0.16 : 0), radius: 10, y: 3)
                .gesture(pinReorder(tab: tab, index: index, columns: cols, width: width, height: height))
            }
        } }
        .coordinateSpace(name: "pins")
    }

    /// The one square actually held stays glued to the fingers; every other
    /// square is already exactly where it belongs, because `browser.move`
    /// put it there — this only cancels out the bit of that same movement
    /// the held square already got for free by changing index underneath
    /// its own drag.
    private func pinOffset(held: Bool, index: Int, columns: Int) -> CGSize {
        guard held else { return .zero }
        let stepX = pinWidth + SideBar.pinGap
        let stepY = pinHeight + SideBar.pinGap
        let from = (row: pinFrom / columns, col: pinFrom % columns)
        let now = (row: index / columns, col: index % columns)
        return CGSize(
            width: pinTravel.width - CGFloat(now.col - from.col) * stepX,
            height: pinTravel.height - CGFloat(now.row - from.row) * stepY
        )
    }

    /// How many cells the drag has moved, in the grid's own row-major order
    /// — a straight line through the array a column-major offset would get
    /// wrong the moment it crossed a row. Row and column travel each measure
    /// themselves against that axis's own step now that a cell's width and
    /// height aren't the same number.
    private func pinDelta(columns: Int, stepX: CGFloat, stepY: CGFloat) -> Int {
        let col = Int((pinTravel.width / stepX).rounded())
        let row = Int((pinTravel.height / stepY).rounded())
        return row * columns + col
    }

    private func pinTarget(from: Int, moved: Int) -> Int {
        min(max(0, from + moved), max(0, favoriteTabs.count - 1))
    }

    /// Pick a square up and the others make way — across a row, and down
    /// into the next, exactly as far as the fingers actually moved.
    private func pinReorder(tab: Tab, index: Int, columns: Int, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("pins"))
            .onChanged { value in
                if pinDragging != tab.id {
                    pinDragging = tab.id
                    pinFrom = index
                }
                pinTravel = value.translation
                let stepX = width + SideBar.pinGap
                let stepY = height + SideBar.pinGap
                let target = pinTarget(from: pinFrom, moved: pinDelta(columns: columns, stepX: stepX, stepY: stepY))
                if target != index {
                    withAnimation(Motion.settle) {
                        browser.move(tab, to: target)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(Motion.settle) {
                    pinDragging = nil
                    pinTravel = .zero
                }
            }
    }

    // MARK: - the rows

    private var loose: some View {
        let rows = browser.todayRows
        let step = SideBar.row + SideBar.gap
        return VStack(spacing: SideBar.gap) {
            // See the grid: the drag is measured in the column's space, not
            // the row's, so a row that has just moved keeps its bearings.
            // Positions are among today's rows as drawn: a split's row is one
            // line, and a tab carried past it passes it whole.
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                switch row {
                case .tab(let id):
                    if let tab = browser.tabs.first(where: { $0.id == id }) {
                        SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == browser.activeID, pill: pill, close: { browser.close(tab) })
                        .modifier(Carried(index: index, count: rows.count, step: step, vertical: true, space: "rows") {
                            browser.moveTodayRow(tab, to: $0)
                        })
                    }
                case .split(let id):
                    if let split = browser.splits.first(where: { $0.id == id }) {
                        SplitRow(browser: browser, split: split, tabs: browser.tabs, interactive: true)
                    }
                }
            }
        }
        .coordinateSpace(name: "rows")
    }

    /// The pins: rows under the cards, for the pages kept all day that want
    /// their titles rather than a letter, and the folders that hold some of
    /// them — each folder's row, then its pins, indented, while it is open.
    /// A pin and a folder are carried the same way, through the rows as
    /// drawn; where one is let go decides its folder (see Shelves.movePin).
    private var pinRows: some View {
        let rows = browser.pinnedRows
        let step = SideBar.row + SideBar.gap
        return VStack(spacing: SideBar.gap) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                switch row {
                case .folder(let id):
                    if let folder = browser.folders.first(where: { $0.id == id }) {
                        FolderRow(browser: browser, folder: folder)
                            .modifier(Carried(index: index, count: rows.count, step: step, vertical: true, space: "pinRows") {
                                browser.moveFolderRow(id, to: $0)
                            })
                    }
                case .pin(let id, let folder):
                    if let tab = browser.tabs.first(where: { $0.id == id }) {
                        SideRow(
                            browser: browser,
                            prefs: prefs,
                            tab: tab,
                            live: tab.id == browser.activeID,
                            pill: pill,
                            close: { browser.close(tab) }
                        )
                        .padding(.leading, folder == nil ? 0 : SideBar.indent)
                        .modifier(Carried(index: index, count: rows.count, step: step, vertical: true, space: "pinRows") {
                            browser.movePinRow(tab, to: $0)
                        })
                    }
                }
            }
        }
        .coordinateSpace(name: "pinRows")
    }

    /// Between the pins and the day's tabs, and only when there are pins.
    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.horizontal, 10)
            .frame(height: SideBar.divider)
    }

    /// The pinned rows as drawn (folder rows and the pins on show) and their
    /// divider — not drawn on its own; `rowsEnd` adds this up from the same
    /// constants the pins and the divider are actually drawn with, so a
    /// change to one of those has to be made in the other too.
    private var pinBlock: CGFloat {
        let rows = CGFloat(browser.pinnedRows.count)
        return rows == 0 ? 0 : rows * (SideBar.row + SideBar.gap) - SideBar.gap + SideBar.divider
    }

    /// The pins and their line, then the loose tabs and the row that makes
    /// another, which scroll as one.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if browser.pinCount > 0 {
                pinRows
                divider
            }
            loose
            newTab
        }
    }

    /// The foot's door and its margin beneath.
    private static let footHeight: CGFloat = 26 + 10

    private var newTab: some View {
        Quiet(icon: "plus", title: "New tab", height: SideBar.row) { browser.newTab() }
            .padding(.top, SideBar.gap)
    }

    /// One small door at the bottom: the settings.
    private var foot: some View {
        HStack(spacing: 2) {
            if browser.prefs.usesSpaces { SpaceDot(browser: browser) }
            ExtensionSlot(edge: .trailing)
            Door(icon: "bookmark", help: "Bookmarks") { browser.bookmarksOpen.toggle() }
                .popover(isPresented: $browser.bookmarksOpen, arrowEdge: .trailing) {
                    BookmarksDropdown(browser: browser, bookmarks: browser.bookmarks)
                }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

}

/// The pinned squares' grid, every cell laid out at once. A lazy grid makes
/// its cells only once the column is on screen, where the column's slide
/// can't take them along: folded with ⌘S and brought back, the squares stood
/// in place while the column came in beneath them. A dozen squares need no
/// laziness.
private struct PinGrid: Layout {
    let columns: Int
    let width: CGFloat
    let height: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = (subviews.count + columns - 1) / columns
        return CGSize(
            width: CGFloat(columns) * width + CGFloat(max(0, columns - 1)) * spacing,
            height: CGFloat(rows) * height + CGFloat(max(0, rows - 1)) * spacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(index % columns) * (width + spacing),
                    y: bounds.minY + CGFloat(index / columns) * (height + spacing)
                ),
                proposal: ProposedViewSize(width: width, height: height)
            )
        }
    }
}

/// A pinned tab as a cell in the block at the top of the column — as wide as
/// its row asks for, but never taller than the classic square, so a row with
/// room to spare turns into a wide, short button rather than a bigger icon.
private struct PinSquare: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let pill: Namespace.ID
    var width: CGFloat = 34
    var height: CGFloat = 34

    @State private var hovering = false

    /// Everything drawn inside scales off the shorter edge — the one that
    /// stays put — so the glyph sits at its usual size, centred, rather than
    /// stretching to chase the width.
    private var scale: CGFloat { min(width, height) }

    var body: some View {
        Group {
            if browser.editingPin == tab.id {
                PinField(browser: browser, tab: tab)
            } else if prefs.glyph == .icons, let icon = tab.icon {
                Mark(icon: icon, letter: tab.pin ?? "", size: scale * 16 / 34, dim: tab.asleep)
            } else {
                Text(tab.pin ?? "")
                    .font(.system(size: scale * 12 / 34, weight: .medium))
                    .foregroundStyle((live ? Palette.ink : Palette.muted).opacity(tab.asleep ? 0.45 : 1))
            }
        }
        .frame(width: scale * 16 / 34, height: scale * 16 / 34)
        .frame(width: width, height: height)
        .background {
            if live {
                RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous)
                    .fill(Palette.wash)
                    .matchedGeometryEffect(id: "live", in: pill)
            } else {
                RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous)
                    .fill(hovering ? Palette.hover : Palette.wash.opacity(0.55))
            }
        }
        .overlay(alignment: .bottom) {
            if tab.away { AwayDot(size: max(3, scale * 4 / 34)).offset(y: -scale * 3 / 34) }
        }
        .overlay(alignment: .topTrailing) {
            if browser.split(of: tab) != nil { SplitMark(size: max(6, scale * 7 / 34)).padding(scale * 3 / 34) }
        }
        .contentShape(RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous))
        .modifier(OneClick(double: live) {
            if live { browser.editLetter(tab) } else { browser.select(tab) }
        })
        // Put down, like ⌘W: close() is what knows a pin isn't removed.
        .overlay { MiddleClick { browser.close(tab) } }
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: { browser.close(tab) }) }
        .help(tab.label)
        .animation(Motion.quick, value: hovering)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// Under a favorite that has left its page: a small mark, not a badge —
/// enough to find the square that isn't where you left it.
struct AwayDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Palette.muted)
            .frame(width: size, height: size)
            .accessibilityLabel("Away from its pinned page")
    }
}

/// One tab, as a line in the column.
private struct SideRow: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let pill: Namespace.ID
    let close: () -> Void

    @State private var hovering = false
    @State private var shake: CGFloat = 0

    private var editing: Bool { browser.editingTab == tab.id }

    /// A pin, drawn as a row: its icon always, no cross — ⌘W or a
    /// middle-click puts it down — and in the cross's place, while it is
    /// away from its page, the way back.
    private var kept: Bool { tab.pin != nil }

    /// What sits at the row's end and takes the title's last few points: the
    /// cross under the pointer, or a pin's way back while it is away.
    private var endMark: Bool { kept ? tab.away : hovering }

    /// The ring or the speaker, which stay for as long as the page loads or
    /// plays (or is muted) and so keep a place of their own at the end of the
    /// row. The cross is only there under the pointer, and takes none.
    private var status: Bool { !editing && (tab.loading || speaker) }
    /// The speaker, which can be pressed, and so steps in beside the cross
    /// under the pointer rather than hiding beneath it as the ring does.
    private var speaker: Bool { !tab.loading && (tab.noisy || tab.muted) }

    /// In the split on screen, though not the pane you are on.
    private var onScreen: Bool { !live && browser.activeSplit?.tabs.contains(tab.id) == true }

    var body: some View {
        HStack(spacing: 8) {
            if editing {
                TabAddressField(browser: browser)
                    .frame(height: 16)
            } else {
                if prefs.glyph == .icons || kept, !tab.isBlank {
                    Mark(icon: tab.icon, letter: tab.monogram, size: 15)
                }
                if browser.split(of: tab) != nil { SplitMark() }
                if tab.bench {
                    // A script's tab, not yours.
                    Image(systemName: "flask")
                        .font(.system(size: 9))
                        .foregroundStyle(colour.opacity(0.7))
                }
                if tab.shy {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9))
                        .foregroundStyle(colour.opacity(0.7))
                }
                Text(tab.label)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(colour)
            }

            if status {
                Spacer(minLength: 2)

                ZStack {
                    if tab.loading {
                        Ring().transition(.opacity)
                    } else {
                        Speaker(tab: tab).transition(.opacity)
                    }
                }
                .frame(width: 15, height: 15)
                // The cross takes this place while the pointer is here; the
                // speaker moves one place in, clear of the cross's reach.
                .opacity(endMark && !speaker ? 0 : 1)
                .padding(.trailing, endMark && speaker ? 23 : 0)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, status ? 7 : 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The title keeps its length under the pointer and fades out
        // beneath the cross, rather than being cut shorter, so its end
        // doesn't jump on each row the pointer passes.
        .mask {
            ZStack {
                Rectangle().opacity(endMark && !editing && !status ? 0 : 1)
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                    Color.clear.frame(width: 26)
                }
            }
        }
        .overlay(alignment: .trailing) {
            if !editing {
                if kept {
                    if tab.away {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 15, height: 15)
                            .background(Palette.ink.opacity(hovering ? 0.07 : 0), in: Circle())
                            .overlay {
                                Color.clear
                                    .frame(width: 30, height: 28)
                                    .contentShape(Rectangle())
                                    .onTapGesture { browser.goHome(tab) }
                            }
                            .help("Back to Pinned Page")
                            .padding(.trailing, 7)
                            .transition(.opacity)
                    }
                } else {
                    ZStack {
                        if hovering {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(width: 15, height: 15)
                                .background(Palette.ink.opacity(0.07), in: Circle())
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 15, height: 15)
                    .overlay {
                        Color.clear
                            .frame(width: 30, height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture { if hovering { close() } }
                    }
                    .padding(.trailing, 7)
                }
            }
        }
        .animation(Motion.quick, value: tab.away)
        .animation(Motion.quick, value: tab.loading)
        .animation(Motion.quick, value: speaker)
        .background { ground }
        .modifier(Shake(travel: shake))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // A pin you are on is renamed with a double-click, as a card has its
        // letter changed; a tab you are on turns into its address.
        .modifier(OneClick(double: live && kept) {
            if !live { browser.select(tab) } else if kept { browser.beginTabRename(tab) } else { browser.beginTabEdit(tab) }
        })
        .overlay { MiddleClick(act: close) }
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: close) }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.glide, value: editing)
        .onChange(of: browser.refusals) { _, _ in
            guard editing else { return }
            shake = 0
            withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
        }
        .transition(.scale(scale: 0.94, anchor: .leading).combined(with: .opacity))
    }

    @ViewBuilder
    private var ground: some View {
        if live {
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.wash)
                if prefs.showsReading {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Palette.ink.opacity(0.055))
                            .frame(width: geo.size.width * tab.reading)
                            .animation(.easeOut(duration: 0.15), value: tab.reading)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .matchedGeometryEffect(id: "live", in: pill)
        } else if onScreen {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.wash.opacity(0.5))
        } else if hovering {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.hover)
        }
    }

    private var colour: Color {
        if live { return Palette.ink }
        return hovering ? Palette.ink.opacity(0.7) : Palette.muted
    }
}

/// A row that is an action rather than a page. Quiet until the pointer is on it.
struct Quiet: View {
    let icon: String
    let title: String
    var height: CGFloat = 28
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? Palette.ink.opacity(0.7) : Palette.faint)
            .padding(.leading, 10)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Palette.hover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// The speaker at the end of a tab that plays sound, or that was muted and
/// so says it is: a press mutes the tab or lets it be heard again. Drawn as
/// it was before it could be pressed, with the cross's faint disc behind
/// it only while the pointer is on it.
struct Speaker: View {
    @ObservedObject var tab: Tab

    @State private var hovering = false

    var body: some View {
        Button(action: tab.toggleMute) {
            Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 8))
                .foregroundStyle(Palette.muted)
                .frame(width: 15, height: 15)
                .background(Palette.ink.opacity(hovering ? 0.07 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.muted ? "Unmute Tab" : "Mute Tab")
        .animation(Motion.quick, value: hovering)
    }
}

/// A small square holding one symbol. Lit when what it opens is open.
struct Door: View {
    let icon: String
    var on = false
    var help = ""
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.7) : Palette.muted))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? Palette.wash : (hovering ? Palette.hover : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: on)
    }
}

/// A folder among the pins, as a line in the column. A click opens or closes
/// it, a double-click renames it; the single click waits the moment a double
/// one takes to rule itself out.
private struct FolderRow: View {
    @ObservedObject var browser: Browser
    let folder: Folder

    @State private var hovering = false

    private var editing: Bool { browser.editingFolder == folder.id }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .rotationEffect(.degrees(folder.open ? 90 : 0))
                .frame(width: 10)
            Image(systemName: "folder")
                .font(.system(size: 11))
            if editing {
                FolderField(browser: browser, folder: folder)
                    .frame(height: 16)
            } else {
                Text(folder.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(hovering || editing ? Palette.ink.opacity(0.7) : Palette.muted)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if hovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.hover)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .gesture(
            TapGesture(count: 2)
                .onEnded { browser.beginFolderRename(folder.id) }
                .exclusively(before: TapGesture().onEnded {
                    withAnimation(Motion.settle) { browser.toggleFolder(folder.id) }
                })
        )
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Rename Folder") { browser.beginFolderRename(folder.id) }
            Button("Delete Folder") { browser.deleteFolder(folder.id) }
        }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: folder.open)
    }
}

/// A folder's name, typed over in place. It arrives selected, so a keystroke
/// replaces it. Return, Tab or a click elsewhere keeps what was typed; Escape
/// keeps the old name.
private struct FolderField: NSViewRepresentable {
    @ObservedObject var browser: Browser
    let folder: Folder

    func makeCoordinator() -> Coordinator { Coordinator(browser: browser, id: folder.id) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12.5)
        field.textColor = Palette.NS.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.stringValue = folder.name
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.browser = browser
        guard !coordinator.claimed else { return }
        coordinator.claimed = true
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var browser: Browser
        let id: UUID
        var claimed = false
        var cancelled = false

        init(browser: Browser, id: UUID) {
            self.browser = browser
            self.id = id
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                cancelled = true
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            if !cancelled { browser.renameFolder(id, to: field.stringValue) }
            // Only its own edit: Rename chosen on another folder meanwhile
            // has already moved the field on.
            if browser.editingFolder == id { browser.endFolderEdit() }
        }
    }
}

/// A split as one line among today's tabs: a segment for each pane, left to
/// right as they sit on screen. A click shows the split with that pane in
/// front; its cross, or a middle-click, closes that pane's tab.
private struct SplitRow: View {
    @ObservedObject var browser: Browser
    let split: Split
    /// Where to find the split's tabs: this space's row, or a parked one's.
    let tabs: [Tab]
    /// Off for another space's preview, which answers nothing.
    let interactive: Bool

    private var onScreen: Bool { interactive && browser.activeSplit?.id == split.id }

    var body: some View {
        GeometryReader { geo in
            let panes = split.tabs.compactMap { id in tabs.first { $0.id == id } }
            let each = panes.isEmpty ? geo.size.width : geo.size.width / CGFloat(panes.count)
            HStack(spacing: 0) {
                ForEach(Array(panes.enumerated()), id: \.element.id) { index, tab in
                    if index > 0 {
                        Rectangle().fill(Palette.hairline).frame(width: 1, height: 14)
                    }
                    SplitSegment(browser: browser, tab: tab, split: split, iconOnly: each < 60,
                                 focused: onScreen && tab.id == browser.activeID, interactive: interactive)
                        .frame(width: max(0, each - (index > 0 ? 1 : 0)))
                }
            }
        }
        // SideBar.row is private to SideBar; a split's row outside it uses
        // the same 28 the rest of this file's rows are drawn with.
        .frame(height: 28)
        .background {
            if onScreen {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.wash)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split view")
    }
}

/// One pane of a split's row.
private struct SplitSegment: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let split: Split
    let iconOnly: Bool
    let focused: Bool
    let interactive: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Mark(icon: tab.icon, letter: tab.monogram, size: 14)
            if !iconOnly {
                Text(tab.label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(focused ? Palette.ink : Palette.muted)
            }
            Spacer(minLength: 0)
            if hovering && interactive && !iconOnly {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 15, height: 15)
                    .background(Palette.ink.opacity(0.07), in: Circle())
                    .contentShape(Rectangle())
                    .onTapGesture { browser.close(tab) }
            }
        }
        .padding(.horizontal, iconOnly ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: iconOnly ? .center : .leading)
        .background {
            if focused {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.ink.opacity(0.06)).padding(2)
            } else if hovering && interactive {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.hover).padding(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if interactive { browser.select(tab) } }
        .overlay { if interactive { MiddleClick { browser.close(tab) } } }
        .onHover { hovering = $0 }
        .contextMenu {
            if interactive {
                TabMenu(browser: browser, tab: tab, close: { browser.close(tab) })
                Divider()
                Button("Separate Split") { browser.separateSplit(split.id) }
            }
        }
        .help(tab.label)
        .animation(Motion.quick, value: hovering)
    }
}
