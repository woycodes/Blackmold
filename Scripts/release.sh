#!/usr/bin/env bash
# Raises the version, builds, and keeps a copy of that version's app in Versions/.
#   Scripts/release.sh minor   a new feature   0.2.0 -> 0.3.0
#   Scripts/release.sh patch   a revision      0.2.0 -> 0.2.1
# The build number goes up by one every time.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

plist="Resources/Info.plist"
kind="${1:-patch}"
current="$(plutil -extract CFBundleShortVersionString raw "$plist")"
build="$(plutil -extract CFBundleVersion raw "$plist")"
IFS=. read -r major minor patch <<<"$current"

case "$kind" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) echo "usage: $0 major|minor|patch [debug|release]" >&2; exit 1 ;;
esac

next="$major.$minor.$patch"
next_build=$((build + 1))
plutil -replace CFBundleShortVersionString -string "$next" "$plist"
plutil -replace CFBundleVersion -string "$next_build" "$plist"

"$root/Scripts/build-app.sh" "${2:-debug}"

mkdir -p Versions
copy="Versions/Blackmold $next.app"
rm -rf "$copy"
ditto build/Blackmold.app "$copy"
echo "Blackmold $next ($next_build) -> $copy"
