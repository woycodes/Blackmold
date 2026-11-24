#!/usr/bin/env bash
# Compiles a .blackmoldplugin folder the way Blackmold does, and prints any
# errors. Uses BlackmoldKit from a built Blackmold.app.
#   Scripts/check-plugin.sh path/to/My.blackmoldplugin [path/to/Blackmold.app]
set -euo pipefail

plugin="${1:?usage: $0 path/to/My.blackmoldplugin [Blackmold.app]}"
app="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/Blackmold.app}"
kit="$app/Contents/Resources/PluginKit"
[[ -d "$kit" ]] || { echo "no PluginKit in $app; build the app first" >&2; exit 1; }

principal="$(/usr/bin/plutil -extract principalClass raw -o - "$plugin/plugin.json")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/entry.swift" <<SWIFT
import BlackmoldKit
@_cdecl("blackmold_plugin_create")
public func _blackmoldPluginCreate() -> UnsafeMutableRawPointer {
    var box: UnsafeMutableRawPointer?
    MainActor.assumeIsolated { box = Unmanaged.passRetained(PluginBox($principal())).toOpaque() }
    return box!
}
SWIFT

xcrun swiftc -parse-as-library -emit-library -swift-version 5 \
    -target "$(uname -m)-apple-macos15.0" -module-name PluginCheck -I "$kit" \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    -o "$work/plugin.dylib" "$plugin"/*.swift "$work/entry.swift"
echo "ok: $(basename "$plugin") builds"
