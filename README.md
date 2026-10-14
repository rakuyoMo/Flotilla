<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/readme-header-en-dark.png">
    <img alt="Flotilla" src="docs/resources/readme-header-en-light.png" width="100%">
  </picture>
</p>

<div align="center">

English | [简体中文](README-ZH.md)

Groups for the macOS Dock: sort apps, files, Finder folders, and web pages into them,
and open each group as a grid right above the Dock, just like a Dock folder.

[![Website](https://img.shields.io/badge/website-flotilla.rakuyo.dev-0089C2)](https://flotilla.rakuyo.dev/)
[![CI](https://github.com/rakuyoMo/Flotilla/actions/workflows/ci.yml/badge.svg)](https://github.com/rakuyoMo/Flotilla/actions/workflows/ci.yml)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-panel-en-dark.jpg">
    <img
      alt="The Essentials group expanded above the Dock as a grid of apps and a Finder folder, its tail pointing at the group's tile"
      src="docs/resources/screenshot-panel-en-light.jpg"
      width="482"
    >
  </picture>
</p>

## About

The Dock's own folders can only live on the right side of the Dock, and each one is a folder on disk.

Flotilla puts groups in the app section on the left side instead. A group is kept by Flotilla rather than as a folder on disk, so the apps you sort into it stay where they are. Like the right side of the Dock, a group can also hold files, Finder folders, and web pages.

Click a group and it expands above the Dock as a grid. Its look, animation, and position follow the Dock's own folders in grid view, one to one.

The app is shown as 归帆 in Simplified Chinese, 歸帆 in Traditional Chinese, 帰帆 in Japanese, and Flotilla in other languages.

## Features

- **Groups among your apps**: each top-level group gets its own tile in the app section of the Dock, named after the group
- **Apps, files, Finder folders, and web pages**: mix them freely in a group; files open in their default app, web pages in your default browser
- **Nested groups**: put groups inside groups; click a sub-group in the panel to step into it, and the back button returns
- **A grid like the Dock's folders**: click a tile and the group expands above the Dock, its tail pointing at the tile
- **Finder folders open like stacks**: click a Finder folder to browse it in the same panel, with file thumbnails and **Open in Finder** at the end of the grid; a setting shows hidden files too
- **Live group icons**: a tile shows the icons of the group's first few items, as many as you choose up to four, and follows the system's light or dark appearance
- **Drag and drop to add**: drop apps, files, and Finder folders onto a group's tile in the Dock, or drop them and web pages onto a group in the settings window
- **Rearrange right in the panel**: drag items to reorder them; drag one out of the panel and hold until **Remove** appears to take it out of the group, as you would with an icon in the Dock
- **Keeps track of moves and updates**: items follow apps and files that are moved or renamed, and an app still opens the installed copy after it updates
- **Stays out of the way**: Flotilla runs in the background with a menu bar icon; opening a panel doesn't add Flotilla to the Dock or take focus from the app you're using
- **Five languages**: English, Simplified Chinese, Traditional Chinese, Japanese, and Korean, following the system language; other languages fall back to English

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-stack-en-dark.jpg">
    <img
      alt="The Wallpapers Finder folder expanded in the panel, with thumbnails of its images and Open in Finder at the end"
      src="docs/resources/screenshot-stack-en-light.jpg"
      width="738"
    >
  </picture>
</p>

## Installation

Flotilla requires macOS 15 or later, on a Mac with Apple silicon.

1. Download the latest `Flotilla-X.Y.Z.zip` from the [website](https://flotilla.rakuyo.dev/download/) or the [Releases](https://github.com/rakuyoMo/Flotilla/releases) page
2. Double-click to unzip it, then drag `Flotilla.app` into the Applications folder
   - Finder shows it under its name for the system language, such as 归帆 in Simplified Chinese
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

## Getting started

Flotilla lives in the menu bar as a sailing ship icon. Click it and choose **Settings…** to open the settings window; **Quit Flotilla** is in the same menu.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-settings-en-dark.png">
    <img
      alt="The settings window, with the Essentials group expanded under Groups and the General section below"
      src="docs/resources/screenshot-settings-en-light.png"
      width="732"
    >
  </picture>
</p>

### Create a group

1. Under **Groups**, click **New Group**, type a name, and press Return
   - A tile for the group appears in the app section of the Dock; the Dock restarts briefly to show it
   - To create a group inside another one, select that group first; it shows up in the parent's panel rather than as a tile of its own
2. Select the group, click **Add…**, and choose what to add:
   - **Add Apps…**: pick apps
   - **Add Files…**: pick files and Finder folders
   - **Add Web Page…**: enter an address and, optionally, a title; when the title is left blank, Flotilla fetches it from the page
3. Or drag items in:
   - Drag apps, files, and Finder folders from Finder, or a web page from your browser, onto the group in the settings window
   - Drag apps, files, and Finder folders onto the group's tile in the Dock; web pages can only be added in the settings window

### Use the panel

- Click a group's tile to open the panel, and click an item to open it
- Click a sub-group or a Finder folder to step into it; the back button takes you up one level
- Click the tile again, click anywhere else, or press Esc to close the panel
- Drag an item within a group to reorder it
- Drag an item out of the panel and hold it there until **Remove** appears, then let go to take it out of the group
  - Only the group changes; the app or file itself is left untouched
  - Letting go before **Remove** appears puts the item back

### Manage groups

In the settings window:

- Double-click a group to rename it
- Drag rows to reorder them, or to move them into another group
- Right-click or Control-click a row for more actions:
  - Group: **Add to Dock**, **Delete**
  - App, file, or Finder folder: **Show in Finder**, **Delete**
  - Web page: **Open in Default Browser**, **Edit…**, **Delete**
- **Delete** removes a group together with everything in it, without asking
- Finder folders show their location after the name, and web pages show their address

To remove a group's tile, drag it out of the Dock like any other app. Flotilla doesn't put it back on its own: the group is marked **Not in Dock**, and **Add to Dock** in its menu brings the tile back.

### Settings

Under **General**:

- **Icons shown in group icon**: how many item icons a tile shows, from 0 to 4; with 0, the tile shows only the group icon itself
- **Finder folders: Show hidden files**: show hidden files when a Finder folder expands in the panel
- **Accessibility permission**: whether it is granted, with a button to **Open System Settings**; see [Accessibility](#accessibility)

## How it works

### Dock tiles

The Dock only holds apps and files, so Flotilla generates a placeholder app for each top-level group and adds it to the Dock; its icon is the group icon.

Clicking the tile launches the placeholder. It opens a `flotilla://` URL without bringing any app to the front, then quits, and Flotilla opens or closes the panel. If Flotilla isn't running, macOS launches it first.

Items dropped onto the tile are handed to Flotilla the same way.

### Dock preferences

Flotilla adds its tiles to the Dock by modifying the Dock preferences (`com.apple.dock`):

- It only adds, removes, and changes its own tiles, which live in `persistent-apps`, the app section on the left side of the Dock; other tiles and other Dock settings are left untouched
- After each change, it terminates the Dock process; macOS relaunches the Dock automatically, and the change takes effect
  - Updating a tile's icon is also such a change, so the Dock restarts when a group's preview changes, or when the system switches between light and dark appearance
- Before its first change in each run, it exports the entire `com.apple.dock` preferences as a backup
  - Location: `~/Library/Application Support/Flotilla/Backups/com.apple.dock-<yyyyMMdd-HHmmss>.plist`
  - Only the 5 most recent backups are kept

### Data and settings

Data is stored in `~/Library/Application Support/Flotilla`:

- `folders.json`: the group data
- `DockTiles/`: placeholder apps that put each top-level group into the Dock
- `Backups/`: backups of the Dock preferences

Settings are stored in the preferences domain `com.rakuyo.flotilla`.

### Network access

Flotilla goes online only to fetch a web page's title in the **Add Web Page…** and **Edit…** dialogs.

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

### Website

The [website](https://flotilla.rakuyo.dev/) is built from `website/` and deployed to GitHub Pages; see the "官网" section of [AGENTS.md](AGENTS.md) (in Chinese) for details.

```bash
# Assemble the website into build/site/
mise run site:build

# Assemble it and preview it at http://localhost:8000/
mise run site:preview
```

Assembling fetches the releases with `gh`, so log in with `gh auth login` first.

## Contributing

- Before opening a pull request, make sure `mise run swift:lint` and `swift test` pass; CI runs them as well, along with a build and a bundle
- Collaboration conventions, such as branch names and commit messages, are in [AGENTS.md](AGENTS.md) (in Chinese)
- The behavior of each feature is specified in [docs/requirements](docs/requirements) (in Chinese)

## License

Flotilla is licensed under the [GNU General Public License v3.0](LICENSE).
