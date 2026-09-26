import AppKit
import SwiftUI

// Split view on screen: the split's tabs side by side, each a column as wide
// as its share, with a divider to drag between them. The pane you are on is
// the tab you are on; a click in another makes it so. See Splits.swift for
// the rules this only draws.

/// What sits over the page you are on — the link under the pointer, find,
/// the accounts for a sign-in field — on the one page, or on the focused
/// pane of a split, never across all of them.
struct PageOverlays: ViewModifier {
    @ObservedObject var browser: Browser
    let tab: Tab

    func body(content: Content) -> some View {
        content
            .overlay {
                if browser.prefs.showsLinks { LinkBubble(status: browser.linkStatus) }
            }
            .overlay(alignment: .topTrailing) {
                if browser.finding {
                    FindBar(browser: browser)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                if let asked = browser.suggesting, asked.tab == tab.id {
                    AccountList(browser: browser, asked: asked)
                        .transition(.opacity)
                }
            }
            .animation(Motion.quick, value: browser.suggesting)
    }
}

/// The split on screen: its panes left to right, dividers between.
struct SplitStage: View {
    @ObservedObject var browser: Browser
    let split: Split

    /// The space between two panes, which is also where a divider is held.
    static let gap: CGFloat = 6
    /// The page's own rounding, for the ring on the pane you are on. Page
    /// doesn't round its page, so neither does this.
    static let corner: CGFloat = 0

    @State private var monitor: Any?

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - CGFloat(split.tabs.count - 1) * SplitStage.gap)
            HStack(spacing: 0) {
                ForEach(Array(split.tabs.enumerated()), id: \.element) { index, id in
                    if index > 0 {
                        SplitDivider(
                            drag: { x in
                                let before = Double(index - 1) * Double(SplitStage.gap) + Double(SplitStage.gap) / 2
                                browser.resizeSplit(split.id, divider: index - 1, to: (Double(x) - before) / Double(usable))
                            },
                            even: { browser.evenSplit(split.id) }
                        )
                    }
                    if let tab = browser.tabs.first(where: { $0.id == id }) {
                        pane(tab)
                            .frame(width: usable * CGFloat(split.widths.indices.contains(index) ? split.widths[index] : 1 / Double(split.tabs.count)))
                    }
                }
            }
            .coordinateSpace(name: "split")
        }
        .onAppear(perform: watchClicks)
        .onDisappear(perform: stopWatching)
    }

    @ViewBuilder
    private func pane(_ tab: Tab) -> some View {
        if tab.id == browser.activeID {
            Page(tab: tab)
                .modifier(PageOverlays(browser: browser, tab: tab))
                .overlay {
                    // The pane you are on, marked without dimming the others:
                    // they're there to be read.
                    RoundedRectangle(cornerRadius: SplitStage.corner, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
        } else {
            Page(tab: tab)
        }
    }

    /// A click in a pane makes it the one you are on. Looked at, never taken:
    /// the page still gets its click. What the view under the click really
    /// is decides, not just where the panes sit — a peek over the split, or
    /// one of its buttons, is not a pane even where it overlaps one.
    private func watchClicks() {
        guard monitor == nil else { return }
        let browser = browser
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            // Whatever is drawn on top decides — a peek over the split, its
            // buttons, a sheet — so the view under the click is asked for,
            // not just where the panes are.
            guard let root = event.window?.contentView else { return event }
            let point = root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            guard let hit = root.hitTest(point) else { return event }
            let panes = browser.activeSplit?.tabs ?? []
            for tab in browser.tabs where panes.contains(tab.id) {
                if let web = tab.built, hit === web || hit.isDescendant(of: web) {
                    browser.focusPane(tab)
                    break
                }
            }
            return event
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Between two panes: dragged, it moves the line between them; a
/// double-click evens every pane.
private struct SplitDivider: View {
    let drag: (CGFloat) -> Void
    let even: () -> Void

    @State private var hovering = false

    var body: some View {
        Color.clear
            .frame(width: SplitStage.gap)
            .overlay {
                Capsule()
                    .fill(Palette.ink.opacity(hovering ? 0.28 : 0.1))
                    .frame(width: 2, height: 36)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("split"))
                    .onChanged { drag($0.location.x) }
            )
            .onTapGesture(count: 2, perform: even)
            .animation(Motion.quick, value: hovering)
    }
}

/// On a tab in a split, wherever the tab is drawn: small, and quiet.
struct SplitMark: View {
    var size: CGFloat = 9

    var body: some View {
        Image(systemName: "rectangle.split.2x1")
            .font(.system(size: size))
            .foregroundStyle(Palette.muted)
            .accessibilityLabel("In a split")
    }
}
