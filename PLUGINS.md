# Writing Blackmold plugins

A plugin adds something to the notch: an activity on its ears, a short
notice, a page of the open notch, a row in search, links it answers. The FL
Studio, Claude Code and Gemini features are plugins written this way; their
folders in `Plugins/` are complete examples, and `Plugins/HelloWorld.blackmoldplugin`
is the smallest one to start from.

## The files

A plugin is a folder whose name ends in `.blackmoldplugin`:

```
MyPlugin.blackmoldplugin/
├── plugin.json
└── MyPlugin.swift        (one or more .swift files)
```

`plugin.json`:

```json
{
  "id": "com.you.myplugin",
  "name": "My Plugin",
  "version": "1.0",
  "author": "you",
  "description": "One line about what it shows.",
  "principalClass": "MyPlugin"
}
```

`principalClass` names the class that adopts `BlackmoldPlugin`.

## Installing

Settings › Plugins › **Install Plugin…**, or copy the folder to
`~/Library/Application Support/Blackmold/Plugins` and press **Reload**.

Blackmold builds the plugin with the Swift compiler from Xcode's Command Line
Tools (`xcode-select --install`), the first time and whenever a file in the
folder changes. Build errors show under the plugin in Settings. To check a
plugin from the terminal:

```
Scripts/check-plugin.sh path/to/MyPlugin.blackmoldplugin
```

Plugins run inside Blackmold, with its permissions. Install only plugins you trust.

## The smallest plugin

```swift
import BlackmoldKit
import SwiftUI

final class MyPlugin: BlackmoldPlugin {
    init() {}

    func start(_ host: PluginHost) {
        host.peek(PluginActivity(left: {
            Image(systemName: "hand.wave.fill").frame(width: 24, height: 24)
        }, right: {
            Text("Hello").font(.system(size: 11, weight: .semibold))
        }), for: 2.5)
    }
}
```

## BlackmoldKit

### `BlackmoldPlugin`

| | |
|---|---|
| `init()` | Blackmold makes the plugin once. |
| `start(_ host:)` | Set up here: keep the host, add pages, start watching things. |
| `stop()` | The plugin was turned off: stop timers, hide what it shows. |
| `settingsView` | Optional `AnyView` shown under the plugin in Settings › Plugins. |

Everything runs on the main actor.

### `PluginHost`

| | |
|---|---|
| `show(_ activity:)` | Shows a `PluginActivity` on the closed notch, or removes it with `nil`. The highest `priority` of all plugins wins; music is below every plugin, a recording and the lock screen above. |
| `peek(_:for:)` | Shows an activity for a few seconds, like the charger notice. |
| `addPage(_:)` | Adds a `PluginPage` to the open notch. |
| `open(page:untilVisited:)` | Opens the notch on one of your pages. |
| `close()` | Closes the notch. |
| `beginTyping()` / `endTyping()` | Lets the notch take the keyboard and stay open while a text field is used. |
| `onURL(host:_:)` | Gets `blackmold://<host>/…` links, for scripts and hooks (`open -g blackmold://myplugin/ping`). |
| `addSearchAction(_:)` | Adds a "<what was typed> – <label>" row to search. |
| `tick()` | A light haptic tap. |
| `notch` | Sizes of the notch (`NotchSize`), for lining up with the ears. |
| `defaults` | A `UserDefaults` of your own. |
| `isOpen`, `openPage` | Whether the notch is open, and on which of your pages. |

### `PluginActivity`

A view for each ear, and optionally a line under the notch (the notch grows a
row for it, like a lyric):

```swift
PluginActivity(priority: 10, left: { … }, right: { … })
PluginActivity(priority: 10, left: { … }, right: { … }, line: { Text("Done") })
```

Views can read your own `@Observable` models; they update by themselves.

### `PluginPage`

```swift
var page = PluginPage(id: "main", title: "My Page", symbol: "star",
                      takesKeyboard: false,
                      height: { NotchSize.pageHeight },      // can follow your state
                      isPreferred: { false }) {              // hover opens here while true
    MyPageView()
}
page.leftEar = { AnyView(Image(systemName: "star")) }     // drawn in the open notch's ears
host.addPage(page)
```

`NotchSize.pageWidth`, `pageInset`, `pageHeight`, `tallPageHeight`,
`contentTop` and `textRowHeight` are the notch's own measurements.

### Helpers

`Motion` (the notch's springs), `PopIn()` (a view modifier that pops in),
`DoneCheck()` (the green check), `.buttonStyle(.zoom)` (grows on hover) and
`TimeFormatting.short(_:)`.

## Compatibility

Plugins are built for macOS 15 and later on the Mac's own architecture.
BlackmoldKit is compiled with library evolution, so a plugin keeps building
against newer versions of Blackmold as long as the parts it uses stay.
