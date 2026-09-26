import Foundation

// Split view: two to four tabs side by side, each a full-height column. A
// split is a lasting group beside the row of tabs — the row itself doesn't
// change — and these are its rules. Nothing here knows about pages or views,
// so the rules are tested on their own (Tests/SearchTests).

/// Tabs shown side by side, left to right, each as wide as its fraction.
struct Split: Codable, Identifiable, Equatable {
    var id: UUID
    var tabs: [UUID]
    var widths: [Double]
}

/// A split as the session keeps it: tab ids aren't saved, so its tabs are
/// their places in the list the session wrote.
struct SavedSplit: Codable, Equatable {
    var tabs: [Int]
    var widths: [Double]
}

enum Splits {
    /// Four columns is as many as a Mac screen reads side by side.
    static let most = 4
    /// No pane narrower than this share, however a divider is dragged.
    static let minimum = 0.12

    static func split(containing tab: UUID, in splits: [Split]) -> Split? {
        splits.first { $0.tabs.contains(tab) }
    }

    /// A tab added as a pane right of `beside`: into its split at an even
    /// share, the others giving up theirs in proportion, or as a new pair at
    /// halves. Nil when that split is full. A tab in another split leaves it.
    static func adding(_ tab: UUID, beside: UUID, to splits: [Split]) -> [Split]? {
        guard tab != beside else { return nil }
        var splits = removing(tab, from: splits)
        guard let s = splits.firstIndex(where: { $0.tabs.contains(beside) }) else {
            let result = splits + [Split(id: UUID(), tabs: [beside, tab], widths: [0.5, 0.5])]
            return tidy(result, existing: Set(result.flatMap(\.tabs)))
        }
        guard splits[s].tabs.count < most, let at = splits[s].tabs.firstIndex(of: beside) else { return nil }
        let n = Double(splits[s].tabs.count + 1)
        splits[s].widths = splits[s].widths.map { $0 * (n - 1) / n }
        splits[s].tabs.insert(tab, at: at + 1)
        splits[s].widths.insert(1 / n, at: at + 1)
        let result = splits
        return tidy(result, existing: Set(result.flatMap(\.tabs)))
    }

    /// A pane taken out: its width goes to the panes beside it, in proportion
    /// to theirs. A split left with one pane is no split.
    static func removing(_ tab: UUID, from splits: [Split]) -> [Split] {
        splits.compactMap { split in
            guard let at = split.tabs.firstIndex(of: tab) else { return split }
            var split = split
            let freed = split.widths.indices.contains(at) ? split.widths[at] : 0
            split.tabs.remove(at: at)
            if split.widths.indices.contains(at) { split.widths.remove(at: at) }
            guard split.tabs.count >= 2, split.widths.count == split.tabs.count else {
                return split.tabs.count >= 2 ? tidy([split], existing: Set(split.tabs)).first : nil
            }
            let near = [at - 1, at].filter { split.widths.indices.contains($0) }
            let share = near.reduce(0) { $0 + split.widths[$1] }
            for i in near { split.widths[i] += share > 0 ? freed * split.widths[i] / share : freed / Double(near.count) }
            return split
        }
    }

    /// A tab swapped for another in its place — a page handed from a website
    /// to an extension's own, or back — keeps its place in its split.
    static func replacing(_ old: UUID, with new: UUID, in splits: [Split]) -> [Split] {
        splits.map { split in
            var split = split
            split.tabs = split.tabs.map { $0 == old ? new : $0 }
            return split
        }
    }

    /// A divider dragged to `fraction` of the split's width: only the two
    /// panes either side of it change, and neither below the minimum.
    static func resizing(_ id: UUID, divider: Int, to fraction: Double, in splits: [Split]) -> [Split] {
        splits.map { split in
            guard split.id == id, divider >= 0, fraction.isFinite, split.widths.indices.contains(divider + 1) else { return split }
            var split = split
            let before = split.widths[..<divider].reduce(0, +)
            let both = split.widths[divider] + split.widths[divider + 1]
            // Two panes already narrower together than twice the minimum share what they have,
            // instead of the bounds crossing.
            let floor = min(minimum, both / 2)
            let at = min(max(fraction, before + floor), before + both - floor)
            split.widths[divider] = at - before
            split.widths[divider + 1] = both - (at - before)
            return split
        }
    }

    /// Every pane the same width: a double-click on a divider.
    static func evened(_ id: UUID, in splits: [Split]) -> [Split] {
        splits.map { split in
            guard split.id == id else { return split }
            var split = split
            split.widths = Array(repeating: 1 / Double(split.tabs.count), count: split.tabs.count)
            return split
        }
    }

    /// The splits as they can be shown: only tabs that exist, each in one
    /// split, two to four to a split, widths that add up. A hand-edited or
    /// cut-short session comes back whole rather than as a page area that
    /// doesn't add up.
    static func tidy(_ splits: [Split], existing: Set<UUID>) -> [Split] {
        var seen = Set<UUID>()
        return splits.compactMap { split in
            var split = split
            var kept: [(UUID, Double)] = []
            let widthsFit = split.widths.count == split.tabs.count && split.widths.allSatisfy { $0.isFinite && $0 > 0 }
            for (i, tab) in split.tabs.enumerated() where existing.contains(tab) && !seen.contains(tab) && kept.count < most {
                seen.insert(tab)
                kept.append((tab, widthsFit ? split.widths[i] : 1))
            }
            guard kept.count >= 2 else { return nil }
            let total = kept.reduce(0) { $0 + $1.1 }
            var widths = kept.map { $0.1 / total }
            // Narrow panes are raised to the minimum, and what they need is
            // taken from the panes above it, in proportion to how far above:
            // every pane ends at the minimum or more, the widths still add up,
            // and tidying again changes nothing. Four panes at the minimum
            // take less than half, so there is always enough to take.
            let low = widths.indices.filter { widths[$0] < minimum - 1e-9 }
            if !low.isEmpty {
                let need = low.reduce(0) { $0 + (minimum - widths[$1]) }
                let high = widths.indices.filter { !low.contains($0) }
                let excess = high.reduce(0) { $0 + (widths[$1] - minimum) }
                for i in low { widths[i] = minimum }
                if excess > 0 { for i in high { widths[i] -= need * (widths[i] - minimum) / excess } }
            }
            split.tabs = kept.map(\.0)
            split.widths = widths
            return split
        }
    }

    /// The pane focus goes to when `tab` leaves: the one to its left, or to
    /// its right when it was first.
    static func neighbour(of tab: UUID, in splits: [Split]) -> UUID? {
        guard let split = split(containing: tab, in: splits), let at = split.tabs.firstIndex(of: tab) else { return nil }
        return at > 0 ? split.tabs[at - 1] : split.tabs.count > 1 ? split.tabs[1] : nil
    }

    /// The splits as places in the list the session writes. A tab it doesn't
    /// write drops out, its share going to the rest.
    static func saved(_ splits: [Split], order: [UUID]) -> [SavedSplit] {
        let place = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return splits.compactMap { split in
            let kept = zip(split.tabs, split.widths).compactMap { tab, width in place[tab].map { ($0, width) } }
            guard kept.count >= 2 else { return nil }
            let total = kept.reduce(0) { $0 + $1.1 }
            return SavedSplit(tabs: kept.map(\.0), widths: kept.map { total > 0 ? $0.1 / total : 1 / Double(kept.count) })
        }
    }

    /// Saved splits back onto the tabs the session brought back. `order` has
    /// nil where an entry brought no tab back; places that land there drop.
    static func restored(_ saved: [SavedSplit], order: [UUID?]) -> [Split] {
        let splits = saved.map { saved -> Split in
            let pairs = saved.tabs.enumerated().compactMap { i, place -> (UUID, Double)? in
                guard order.indices.contains(place), let tab = order[place] else { return nil }
                let width = saved.widths.indices.contains(i) ? saved.widths[i] : .nan
                return (tab, width)
            }
            return Split(id: UUID(), tabs: pairs.map(\.0), widths: pairs.map(\.1))
        }
        return tidy(splits, existing: Set(order.compactMap { $0 }))
    }
}
