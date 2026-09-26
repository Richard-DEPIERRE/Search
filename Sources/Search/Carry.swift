import SwiftUI

/// A tab carried out of its section in the column, on its way to be dropped
/// somewhere else (see Drops). Held by the browser but not published by it:
/// every view watches the browser, and the hand moves on every event.
@MainActor
final class Carry: ObservableObject {
    /// Where the hand is, apart from the rest: it changes on every move, and
    /// only the chip under the hand needs to hear about it.
    final class Hand: ObservableObject {
        @Published var point: CGPoint = .zero
    }

    @Published private(set) var tab: Tab?
    @Published private(set) var source: DragSource?
    /// Out of its own section: the section stops making way for it and the
    /// chip takes over.
    @Published private(set) var lifted = false
    @Published private(set) var target: DropTarget?
    /// The wells for an empty section are showing: only once the hand is clear
    /// of its own section. Over another split's row inside today's, a well
    /// opening above would slide that row out from under the hand.
    @Published private(set) var wells = false
    let hand = Hand()
    /// The areas as they were when this drag began, before any well opened.
    /// Whether the tab is out of its section is judged against these: a well
    /// opening above a section moves it, and judged against where it moved to,
    /// the section could come back under the hand, close the well, move back,
    /// and open it again for as long as the hand stayed there.
    private var start: DropAreas?

    /// Reported by the areas as they are laid out. Not published: read only
    /// when the hand moves or the layer draws.
    var areas = DropAreas()
    /// The wells an empty section shows while a tab is carried, reported apart
    /// from the grid and the rows: the one going and the one coming can report
    /// in either order, and neither may wipe out the other.
    var favoritesWell: CGRect?
    var pinsWell: CGRect?
    weak var browser: Browser?

    /// The areas as they stand: counts from the browser, a well in place of an
    /// empty section, and only the splits there still are.
    var effective: DropAreas {
        var a = areas
        guard let browser else { return a }
        a.favoriteCount = browser.favoriteCount
        if browser.favoriteCount == 0 {
            a.favorites = favoritesWell
            a.favoriteStep = .zero
        }
        a.pinCount = browser.pinnedRows.count
        if browser.pinCount == 0 { a.pins = pinsWell }
        a.todayCount = browser.todayRows.count
        let ids = Set(browser.splits.map(\.id))
        a.splitRows = a.splitRows.filter { ids.contains($0.key) }
        return a
    }

    /// The hand moved, carrying `tab`. True once it is out of its own section
    /// (a pane pulled from a split's row is out at once).
    @discardableResult
    func move(_ tab: Tab, from source: DragSource, to point: CGPoint) -> Bool {
        let areas = effective
        if self.tab?.id != tab.id { start = areas }
        let before = start ?? areas
        let home: CGRect? = switch source {
        case .favorite: before.favorites
        case .pin: before.pins
        case .today: before.today
        case .pane: nil
        }
        let out = Drops.isOut(tab.id, from: source, at: point, home: home, areas: before, splits: browser?.splits ?? [])
        let clear = out && (home.map { !$0.insetBy(dx: -6, dy: -6).contains(point) } ?? true)
        if self.tab?.id != tab.id { self.tab = tab }
        if self.source != source { self.source = source }
        hand.point = point
        if lifted != out { lifted = out }
        if wells != clear { wells = clear }
        // Where it would land is read from the areas as drawn now, wells and all.
        let now = out ? Drops.target(at: point, in: areas) : nil
        if target != now { target = now }
        return out
    }

    /// The hand let go: dropped where it is, if it was out of its own section.
    func end() {
        defer {
            tab = nil
            source = nil
            lifted = false
            target = nil
            wells = false
            start = nil
        }
        guard lifted, let tab, let source, let browser else { return }
        let action = Drops.resolve(source: source, target: target, tab: tab.id, active: browser.activeID, splits: browser.splits)
        withAnimation(Motion.settle) { browser.apply(action, to: tab) }
    }
}

/// What a section's drag needs to lift its tab out (see Carried).
struct Lifting {
    let carry: Carry
    let tab: Tab
    let source: DragSource
}

/// Tells `report` where this view is in the window, now and whenever it moves.
struct ReportFrame: ViewModifier {
    let report: (CGRect) -> Void

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { report(geo.frame(in: .global)) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in report(frame) }
            }
        }
    }
}

/// An empty section while a tab is carried: somewhere to let it go.
struct DropWell: View {
    let title: String
    let height: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .transition(.opacity)
    }
}

/// Over the whole window while a tab is carried out of its section: the tab
/// under the hand, and a mark where it would go if let go now — none where
/// letting go would do nothing.
struct DropLayer: View {
    @ObservedObject var browser: Browser
    @ObservedObject var carry: Carry

    var body: some View {
        GeometryReader { geo in
            // The layer's own place in the window, taken off every frame the
            // areas reported, which are the window's.
            let origin = geo.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                Color.clear
                if carry.lifted, let tab = carry.tab {
                    if let target = carry.target, let source = carry.source,
                       Drops.resolve(source: source, target: target, tab: tab.id, active: browser.activeID, splits: browser.splits) != .none {
                        mark(for: target, areas: carry.effective)
                            .offset(x: -origin.x, y: -origin.y)
                    }
                    Chip(tab: tab, hand: carry.hand, origin: origin)
                }
            }
        }
        .allowsHitTesting(false)
        .animation(Motion.quick, value: carry.target)
        .animation(Motion.quick, value: carry.lifted)
    }

    /// Drawn in the window's own coordinates; the caller moves it into the
    /// layer's.
    @ViewBuilder
    private func mark(for target: DropTarget, areas: DropAreas) -> some View {
        switch target {
        case .favorites(let i):
            if let f = areas.favorites {
                if areas.favoriteStep == .zero {
                    outline(f)
                } else {
                    let columns = max(1, areas.favoriteColumns)
                    let x = f.minX + CGFloat(i % columns) * areas.favoriteStep.width - 2
                    let y = f.minY + CGFloat(i / columns) * areas.favoriteStep.height
                    Rectangle().fill(Palette.ink)
                        .frame(width: 2, height: areas.favoriteStep.height - 4)
                        .offset(x: x - 1, y: y)
                }
            }
        case .pins(let i):
            if let f = areas.pins {
                if browser.pinCount == 0 {
                    outline(f)
                } else {
                    let open = Set(browser.folders.filter(\.open).map(\.id))
                    let indent: CGFloat = Drops.pinLineFolder(browser.pinnedRows, at: i, open: open) == nil ? 0 : 14
                    line(in: f, at: i, indent: indent)
                }
            }
        case .today(let i):
            if let f = areas.today { line(in: f, at: i, indent: 0) }
        case .splitRow(let id):
            if let f = areas.splitRows[id] { outline(f) }
        case .page(let side):
            if let f = areas.page {
                let half = CGRect(x: side == .left ? f.minX : f.midX, y: f.minY, width: f.width / 2, height: f.height)
                ZStack {
                    Rectangle().fill(Palette.ink.opacity(0.06))
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Palette.muted)
                }
                .frame(width: half.width, height: half.height)
                .offset(x: half.minX, y: half.minY)
            }
        }
    }

    /// Between two rows: centred in the gap above row `i`.
    private func line(in frame: CGRect, at i: Int, indent: CGFloat) -> some View {
        Rectangle().fill(Palette.ink)
            .frame(width: max(0, frame.width - indent), height: 2)
            .offset(x: frame.minX + indent, y: frame.minY + CGFloat(i) * DropAreas.step - 2)
    }

    private func outline(_ frame: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(Palette.ink, lineWidth: 1.5)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}

/// The carried tab, just right of the hand.
private struct Chip: View {
    let tab: Tab
    @ObservedObject var hand: Carry.Hand
    let origin: CGPoint

    var body: some View {
        HStack(spacing: 6) {
            Mark(icon: tab.icon, letter: tab.monogram, size: 14)
            Text(String(tab.label.prefix(40)))
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .fixedSize()
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .offset(x: hand.point.x - origin.x + 10, y: hand.point.y - origin.y - 14)
        .transition(.opacity)
    }
}
