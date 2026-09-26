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
    let hand = Hand()

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
        let home: CGRect? = switch source {
        case .favorite: areas.favorites
        case .pin: areas.pins
        case .today: areas.today
        case .pane: nil
        }
        let out = home.map { !$0.insetBy(dx: -6, dy: -6).contains(point) } ?? true
        if self.tab?.id != tab.id { self.tab = tab }
        if self.source != source { self.source = source }
        hand.point = point
        if lifted != out { lifted = out }
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
