# Blackmold

Blackmold turns the notch on your MacBook into something useful. Hover over it
and it opens into a small panel with your music, calendar, voice memos and
more. When something happens, like a song change or a finished render, the
notch grows little wings and shows you, then tucks itself away again.

It looks like part of macOS. Black at the camera, rounded like the hardware,
moving with soft springs.

## What it does

### Music
Play, pause, skip, scrub and change the volume for Music or Spotify. The album
cover and a spectrum that moves with the sound sit beside the camera while a
song plays. Tap the cover to switch on synced lyrics, and the current line
appears under the notch, letter by letter.

### Search
Press ⌘Space and a search field drops out of the notch in liquid glass. Type to
find apps and files, press ⌘1, ⌘2 or ⌘4 to jump to Applications, Files or your
clipboard history, or click the mic and say what you're looking for. You pick
the shortcuts yourself in Settings, and you can switch search off. To use
⌘Space, turn off Spotlight's shortcut first.

### Calendar
Today's date and events next to a month you can flip through. Add an event
without leaving the notch.

### Voice Memos
Record from the notch and keep going while you work: a red dot and a timer stay
on the closed notch. Turn on noise reduction and RNNoise cleans up the
background as you record.

### Mirror
A quick look at your camera before a call.

### Calculator
A small calculator that saves its results into the Calculator app's history.

### Game controllers
Connect a DualSense and the notch shows it, with its battery, a disconnect
button and its light bar colour.

### Notices
Blackmold replaces the volume and brightness overlays, and shows a short notice
for Focus modes, headphones, the charger, Low Power Mode and files arriving by
AirDrop. Drag files onto the notch to send them with AirDrop. Locking and
unlocking your Mac plays a small padlock animation.

### Look and feel
Switch on Liquid Glass to give every page the same glass as search, or turn the
background blur off. Swipe on the notch with two fingers to open it, change
pages or skip songs.

## Plugins

You can teach Blackmold new tricks. A plugin is a folder with a short
`plugin.json` and a few Swift files. Drop it into Settings › Plugins and
Blackmold builds it and loads it. Plugins can show things on the notch's ears,
pop up short notices, add their own pages, add rows to search and answer
`blackmold://` links from scripts.

These four come in the `Plugins` folder:

- **FL Studio Renders**: a fruit being sliced and a progress ring while FL
  Studio renders, then a check when it finishes.
- **Claude Code**: what Claude Code is doing, with a timer while it thinks and
  the tokens it has written while it works. It also tells you when a usage
  limit has reset.
- **Gemini**: ask Gemini from the notch with your own API key. Type, talk,
  share a photo or start a live voice chat. It also adds "Ask Gemini" to
  search.
- **Hello World**: the smallest plugin, made to copy and build on.

Read [PLUGINS.md](PLUGINS.md) to write your own.

## Requirements

- A Mac with Apple silicon, running macOS 15 or later. Liquid Glass needs
  macOS 26; older versions get a frosted look instead.
- Xcode's Command Line Tools, for building plugins: `xcode-select --install`.

Blackmold asks for permissions as you use the features: Accessibility for the
volume keys and FL Studio, the camera for Mirror, the microphone for voice
memos and dictation, and your calendar for Calendar.

## Building

```bash
Scripts/build-app.sh
```

This puts `Blackmold.app` in `build/`. To make a numbered release and keep a
copy of it in `Versions/`, run `Scripts/release.sh minor` for new features or
`Scripts/release.sh patch` for fixes.

## Credits

Made by [woycodes](https://github.com/woycodes).

Noise reduction uses [RNNoise](https://github.com/xiph/rnnoise) from Xiph.org.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
