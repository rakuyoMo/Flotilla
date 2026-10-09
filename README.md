# Flotilla

English | [简体中文](README-ZH.md)

Flotilla adds groups to the macOS Dock, so you can sort multiple apps into them. Just like the right side of the Dock, a group can also hold files, Finder folders, and web pages.

Click a group and it expands from the Dock to show its contents. Click an item to open it; a Finder folder expands further, like a Dock stack.

The interface follows the system language:

- Available in English, Simplified Chinese, Traditional Chinese, Japanese, and Korean; other languages fall back to English
- The app is shown as 归帆 in Simplified Chinese, 歸帆 in Traditional Chinese, 帰帆 in Japanese, and Flotilla in other languages

## Requirements

macOS 15 or later.

## Installation

1. Download the latest `Flotilla-X.Y.Z.zip` from the [Releases](https://github.com/rakuyoMo/Flotilla/releases) page
2. Double-click to unzip it, then drag `Flotilla.app` into the Applications folder
3. Open Flotilla

### First launch

Flotilla is not notarized by Apple. The first time you open it, macOS says that Apple cannot verify it is free of malware, and refuses to open it.

Click **Done** to close the alert, then allow the app to open:

1. Open **System Settings › Privacy & Security**
2. Scroll down to **Security**, and click **Open Anyway** on the line saying the app was blocked
   - This button only appears for an hour after you try to open Flotilla
3. Confirm with your login password when prompted

After that, Flotilla opens like any other app.

Alternatively, remove the quarantine attribute in Terminal, then open it directly:

```bash
xattr -d com.apple.quarantine /Applications/Flotilla.app
```

## Permissions

### Accessibility

Flotilla uses Accessibility to read the Dock's interface, in order to:

- Find where a group's tile (its icon in the Dock) is on screen, so the panel and its tail line up with the tile
- Detect clicks on a tile and expand on mouse-up, with the same timing as the Dock's built-in folders

Flotilla still works without this permission, except that:

- The panel is placed at the mouse location of the click, and may not line up exactly with the tile
- The panel appears only after the Dock launches the tile, slightly later than with the permission

Granting the permission:

- Without the permission, macOS prompts for it the first time a tile is clicked after each launch of Flotilla
- It is granted in **System Settings › Privacy & Security › Accessibility**
  - On macOS 27, this page is **Privacy & Security › Device Control and Data Access**

Flotilla is ad-hoc signed. After switching to a new version, the previous grant may stop working, and the permission needs to be granted again.

### Files and folders

The first time the panel expands a Finder folder in Documents, Desktop, Downloads, or a similar location, macOS asks whether to allow access.

Flotilla needs to read a folder's contents to expand it in the panel.

## Changes to your system

### Dock preferences

Flotilla adds its tiles to the Dock by modifying the Dock preferences (`com.apple.dock`):

- It only adds, removes, and changes its own tiles, which live in `persistent-apps`, the app section on the left side of the Dock; other tiles and other Dock settings are left untouched
- After each change, it terminates the Dock process; macOS relaunches the Dock automatically, and the change takes effect
- Before its first change in each run, it exports the entire `com.apple.dock` preferences as a backup
  - Location: `~/Library/Application Support/Flotilla/Backups/com.apple.dock-<yyyyMMdd-HHmmss>.plist`
  - Only the 5 most recent backups are kept

### Data and settings

Data is stored in `~/Library/Application Support/Flotilla`:

- `folders.json`: the group data
- `DockTiles/`: placeholder apps that put each top-level group into the Dock
- `Backups/`: backups of the Dock preferences

Settings are stored in the preferences domain `com.rakuyo.flotilla`.

## Building from source

Only the Xcode Command Line Tools and [mise](https://mise.jdx.dev) are needed; Xcode is not required.

The Command Line Tools must be version 26 or later, which ships with Swift 6.2 and the macOS 26 SDK: `Package.swift` declares `swift-tools-version: 6.1`, but `NSGlassEffectView`, which the panel uses on macOS 26, is only available in the macOS 26 SDK.

Within the limits of the Command Line Tools, the project is set up as follows:

- It is managed by Swift Package Manager
- The UI is built entirely in AppKit code: the plugin that implements SwiftUI's macros is not included
- Tests use Swift Testing: XCTest is not included
- There are no asset catalogs, storyboards, or xibs: `actool` and `ibtool` are not included

See the "Command Line Tools 的限制" section of [AGENTS.md](AGENTS.md) (in Chinese) for details.

```bash
# Build the debug version
mise run build

# Build the release version, bundle it as build/Flotilla.app, and ad-hoc sign it
mise run bundle

# Launch the bundled app
open build/Flotilla.app
```

The two `ld: warning: search path ... not found` warnings during the build can be ignored: they point to directories that the Command Line Tools don't include.

## Development

### Tests

```bash
swift test
```

- If it occasionally fails with `plugin for module 'TestingMacros' not found`, run it again; this happens more often right after `mise run swift:format`
- In a git worktree, it fails every time; pass the plugin directory explicitly:

  ```bash
  swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
  ```

### Code style

The code style follows [RakuyoKit/swift](https://github.com/RakuyoKit/swift).

```bash
# Format the code
mise run swift:format

# Check the code style
mise run swift:lint
```

### Logs

In zsh, `log` is a builtin command, so write the full path `/usr/bin/log` to view the system log:

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.rakuyo.flotilla"'
```

### Accessibility while developing

- The bundled app is ad-hoc signed; after re-bundling, the previous Accessibility grant may stop working, and the permission needs to be granted again
- Which grant applies depends on how Flotilla is launched, so the two launch methods can be used to test the paths with and without the permission:
  - When `build/Flotilla.app/Contents/MacOS/Flotilla` is run directly from Terminal, the process inherits Terminal's Accessibility grant
  - When launched with `open build/Flotilla.app`, Flotilla's own grant applies

### Single instance

When an instance with the same bundle ID is already running, a newly launched copy activates it and quits immediately.

Quit any installed Flotilla before launching `build/Flotilla.app`.

### Dock preferences

Back up the Dock preferences before modifying them while debugging:

```bash
defaults export com.apple.dock <file>
```

## License

[GNU General Public License v3.0](LICENSE)
