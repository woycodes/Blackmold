#!/usr/bin/env bash
# Assembles build/Blackmold.app from the SwiftPM executable.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

configuration="${1:-debug}"
swift build -c "$configuration"
bin="$(swift build -c "$configuration" --show-bin-path)"

app="$root/build/Blackmold.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$bin/Blackmold" "$app/Contents/MacOS/Blackmold"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$app/Contents/PkgInfo"

# BlackmoldKit's module, for compiling plugins against: the binary module and
# the text interface (which keeps working with other compiler versions).
kit="$app/Contents/Resources/PluginKit/BlackmoldKit.swiftmodule"
mkdir -p "$kit"
cp "$bin/BlackmoldKit.swiftmodule/"*.swiftmodule "$kit/" 2>/dev/null || true
config_dir="$(tr '[:lower:]' '[:upper:]' <<< "${configuration:0:1}")${configuration:1}"
interface="$(find "$root/.build" -name BlackmoldKit.swiftinterface -path "*/$config_dir/*" -not -path "*/Products/*" | head -1)"
arch_name="$(uname -m)"
if [[ -n "$interface" ]]; then
    cp "$interface" "$kit/$arch_name-apple-macos.swiftinterface"
else
    echo "warning: no BlackmoldKit.swiftinterface found; plugins will need the same compiler" >&2
fi

# A fixed signing identity keeps macOS permissions (Accessibility, camera,
# audio capture) across rebuilds. Ad-hoc signing changes the signature on
# every build, so macOS forgets those permissions each time.
identity="${BLACKMOLD_SIGN_IDENTITY:-iNotch Dev}"
# Self-signed identities show as "not trusted" and are left out of
# `find-identity -v`, yet codesign uses them fine, so list without -v.
if security find-identity -p codesigning | grep -q "\"$identity\""; then
    sign="$identity"
else
    sign="-"
    echo "note: no \"$identity\" signing identity, using ad-hoc (permissions reset on each build)"
fi

# Entitlements are needed for the Apple Events, calendar and camera prompts.
codesign --force --deep --sign "$sign" --options runtime \
    --entitlements "$root/Resources/Blackmold.entitlements" \
    "$app" >/dev/null 2>&1 || \
codesign --force --deep --sign "$sign" "$app"

echo "built $app"
