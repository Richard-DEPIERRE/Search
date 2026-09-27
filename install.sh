#!/bin/bash
# Builds this checkout and puts it in /Applications in place of the Search
# you use every day.
#
#   ./install.sh            build, test, quit Search, swap, open it again
#   ./install.sh --no-test  the same without swift test
#   ./install.sh back       put the previous build back
#
# The build it replaces is kept as build/Search-previous.zip, zipped rather
# than left as a second Search.app so Launch Services never has two apps
# with one identifier to choose between.
set -euo pipefail

cd "$(dirname "$0")"
TARGET="/Applications/Search.app"
BACKUP="build/Search-previous.zip"
ID="com.officecommun.search"

running() { [ "$(osascript -e "application id \"$ID\" is running")" = "true" ]; }

quit() {
  running || return 1
  osascript -e "tell application id \"$ID\" to quit"
  # Quitting saves the session; give it the time it needs.
  for _ in $(seq 1 30); do running || return 0; sleep 1; done
  echo "Search didn't quit within 30s — quit it by hand and run this again" >&2
  exit 1
}

if [ "${1:-}" = "back" ]; then
  [ -f "$BACKUP" ] || { echo "no $BACKUP to go back to" >&2; exit 1; }
  WAS=0; quit && WAS=1
  rm -rf "$TARGET"
  ditto -x -k "$BACKUP" /Applications
  echo "back to: $(defaults read "$TARGET/Contents/Info.plist" CFBundleVersion)"
  [ "$WAS" = 1 ] && open "$TARGET"
  exit 0
fi

[ -z "$(git status --porcelain --untracked-files=no)" ] \
  || { echo "uncommitted changes — commit or stash them first" >&2; exit 1; }

[ "${1:-}" = "--no-test" ] || swift test
./build.sh release
codesign --verify --deep "build/Search.app"

WAS=0; quit && WAS=1
if [ -d "$TARGET" ]; then
  rm -f "$BACKUP"
  ditto -c -k --keepParent "$TARGET" "$BACKUP"
  rm -rf "$TARGET"
fi
ditto "build/Search.app" "$TARGET"

echo "installed: $(defaults read "$TARGET/Contents/Info.plist" CFBundleVersion) from $(git rev-parse --short HEAD)"
echo "previous build kept in $BACKUP (./install.sh back)"
[ "$WAS" = 1 ] && open "$TARGET"
exit 0
