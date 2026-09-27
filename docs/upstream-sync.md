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
