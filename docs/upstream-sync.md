# Upstream sync

What this fork has taken from upstream (driceroland/Search), and what it
has chosen not to take. The weekly `weekly-upstream-sync` task reads this
file: a commit listed under Skipped is not offered again, unless it has
been moved to Revisit.

Each review adds a dated section, newest first:

```
## YYYY-MM-DD — PR #n
Taken: <short SHAs> — <theme>
Skipped: <short SHAs> — <theme> — <one-line reason>
Revisit: <short SHAs> — <theme> — <what would change the answer>
```

Two things stay fork-only whatever upstream does:

- `Updater.fetch` doesn't read the real feed. That feed names upstream's
  builds, and the updater would swap the fork's features out.
- `install.sh` builds this checkout and swaps it into /Applications.
  `./install.sh back` puts the previous build back.

Upstream features that stay dormant in the fork, because the fork has its own:

- Upstream's Split View (`TabSplit`, `pairs`, `PairStage`, bench verb `pair`)
  is compiled in but always off (`Preferences.splitView`), with no switch in
  Settings. The fork's split view is `Split`/`splits`/`SplitStage` and the
  bench verb `split`. The session file keeps each in its own key: `splits`
  for the fork's, `pairs` for upstream's.
- Upstream's tab groups are always off (`Preferences.usesTabGroups`), with no
  switch in Settings or What's New. The column groups pins in folders instead.

## 2026-09-28 — PR #12
Taken: e10e5ec…fd33667 (all 214 commits, merged at fd33667) — several windows; imports (Arc, Firefox, Zen, Helium, Comet, Opera, files); extensions compatibility and security; privacy, passwords, passkeys; browsing UX and shortcuts; bookmarks; downloads, video, full screen and speed; AI add-on groundwork (off); updater and release scripts; docs.
Taken, dormant: 18ac5ab e1fa4c8 ff02162 1004cc9 d576aa2 — upstream's Split View — merged so later upstream work applies, but kept off; the fork's split view wins.
Taken, dormant: 198ada8 59bdeb1 a98f426 85a923f 7e759ba cd13d97 05f1b70 1d48d4e d16e2b8 f98e3bf 764cde5 — tab groups — kept off; the fork's folders win.
Taken, fork wins: 992b6ed — pins the same in every window — pins.json carries each pin's shelf (favorite or pin); which folder a pin is in stays each window's own.
Taken, fork wins: 3136322 — a double-click on the live pin — goes home in upstream; in the fork a favorite's double-click changes its letter and a pin row's renames it, and Back to Pinned Page is in the menu.
Skipped: 9484800 (grid part) — squares fill their rows evenly — the fork's favorites grid is its own (3 columns, carried with Carry); the fix doesn't apply as written.
Skipped: 18ac5ab (strip part) — dropping a tab onto a page to pair it (TabDrag) — upstream's Split View is off; the fork drops into its splits through Carry.
Revisit: 9484800 — even rows for the favorites grid — worth porting onto the fork's grid if favorites get past six.
Revisit: dedca00 — "A dragged pin carries its own travel" — landed upstream after this review; next week's review picks it up.
