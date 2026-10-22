<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/readme-header-en-dark.png">
    <img alt="Flotilla" src="docs/resources/readme-header-en-light.png" width="100%">
  </picture>
</p>

<div align="center">

English | [简体中文](README-ZH.md)

Group apps, files, folders, and web pages in your Mac's Dock.

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
      alt="The Essentials group open above the Dock, showing apps and a folder in a grid, with an arrow pointing to the group icon"
      src="docs/resources/screenshot-panel-en-light.jpg"
      width="482"
    >
  </picture>
</p>

## About

The Dock's own folders can only sit on the right side, and each one is tied to a folder on disk. Flotilla puts groups on the left, next to your apps. A group can hold apps, files, folders, and web pages without moving anything or creating folders on disk.

Click a group icon and it opens in a grid that looks and animates just like a Dock folder.

## Features

- **Groups within groups**: subgroups open right in the same panel

- **Browse folders in place**: like a Dock stack, a folder opens in the panel with file thumbnails

- **Group icon previews**: the group icon shows its first few items, up to four

- **Drag and drop**: drop apps, files, and folders onto a group icon in the Dock to add them, and drag items in the panel to reorder or remove them

- **Keeps track of your items**: apps and files still open after you move or rename them

- **Menu bar app**: Flotilla runs from the menu bar, so it doesn't add its own icon to the Dock

- **Eight languages**: English, Simplified Chinese, Traditional Chinese, Japanese, Korean, German, French, and Spanish

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-stack-en-dark.jpg">
    <img
      alt="The Wallpapers folder open in the panel, showing image thumbnails and Open in Finder at the end"
      src="docs/resources/screenshot-stack-en-light.jpg"
      width="738"
    >
  </picture>
</p>

## Installation

Flotilla needs a Mac with Apple silicon running macOS 15 or later.

1. Download the latest `Flotilla-X.Y.Z.zip` from the [website](https://flotilla.rakuyo.dev/download/) or [GitHub Releases](https://github.com/rakuyoMo/Flotilla/releases)
2. Unzip it and drag Flotilla into your Applications folder
3. Open Flotilla

### First launch

Flotilla isn't notarized by Apple, so macOS blocks it the first time you open it. Click **Done**, then:

1. Open **System Settings › Privacy & Security**
2. Scroll down to **Security**, find the message about Flotilla, and click **Open Anyway**
3. Confirm with your login password

If you'd rather use Terminal, remove the quarantine attribute instead, then open Flotilla:

```bash
xattr -d com.apple.quarantine /Applications/Flotilla.app
```

### Updates

Flotilla checks for updates automatically. You can check right away, change how often it checks, or turn automatic checks off under **Software Update** in Settings.

## Permissions

Flotilla uses Accessibility access to read the Dock's interface, so the panel can line up with its group icon and open as soon as you release the mouse button.

Without it, Flotilla still works, but the panel opens near the pointer and may not line up with the group icon. It also takes a little longer to appear.

Grant access when macOS asks, or turn it on later in **System Settings › Privacy & Security › Accessibility**. On macOS 27, that page is **Privacy & Security › Device Control and Data Access**.

Flotilla is ad-hoc signed, so you may need to turn this permission on again after an update.

## Getting started

Click the sailing ship in the menu bar and choose **Settings…** to manage your groups.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-settings-en-dark.png">
    <img
      alt="The settings window with the Essentials group expanded and General settings below"
      src="docs/resources/screenshot-settings-en-light.png"
      width="732"
    >
  </picture>
</p>

### Create a group

1. Under **Groups**, click **New Group**, type a name, and press Return. The Dock restarts for a moment, then the group icon shows up next to your apps
   - To create a subgroup, select its parent first. Subgroups show up in their parent's panel instead of the Dock

2. Select the group and click **Add…** to add apps, files, folders, or web pages

3. You can also drag apps, files, and folders onto a group in the settings window or onto its icon in the Dock. Web pages can be dragged from your browser into the settings window

### Manage groups

In the settings window, drag items to reorder them or move them into another group, and right-click an item for more options, including **Delete**. Deleting a group deletes everything in it too, without asking first.

You can also remove an item right from the panel: drag it out and let go once **Remove** appears.

Either way, your apps and files themselves stay where they are.

Dragging a group icon out of the Dock only removes the icon. The group stays in the settings window, marked **Not in Dock**, until you right-click it and choose **Add to Dock**.

## How it works

### Dock tiles

The left side of the Dock only takes apps, so Flotilla gives each top-level group a placeholder app with the group's name and icon, and adds that to the Dock. Clicking the icon launches the placeholder app, which opens a `flotilla://` URL to tell Flotilla to open or close the panel.

### Dock preferences

Flotilla adds these tiles by editing the Dock preferences (`com.apple.dock`). It only touches its own entries in `persistent-apps`, the app section of the Dock, and leaves your other icons and Dock settings alone.

To apply a change, Flotilla ends the Dock process and macOS restarts it. Group icon updates need a restart too, for example when your Mac switches between light and dark mode.

Each time Flotilla launches, it backs up `com.apple.dock` before its first change. The 5 most recent backups are kept in `~/Library/Application Support/Flotilla/Backups/`.

### Data and settings

Flotilla keeps your groups, the placeholder apps, and the Dock backups in `~/Library/Application Support/Flotilla`, and its settings in the `com.rakuyo.flotilla` preferences domain.

### Network access

Flotilla only goes online to fetch a web page's title when you add or edit one, and to check for and download updates from GitHub Releases.

## Building from source

You'll need [mise](https://mise.jdx.dev) and the Xcode Command Line Tools 26 or later. You don't need the full Xcode app.

```bash
# Build the debug version
mise run build

# Build the release version, bundle it as build/Flotilla.app, and ad-hoc sign it
mise run bundle

# Launch the bundled app
open build/Flotilla.app
```

You can ignore the two `ld: warning: search path ... not found` warnings during the build.

## Development

### Tests

```bash
swift test
```

If it fails with `plugin for module 'TestingMacros' not found`, run it again. In a git worktree it fails every time, so pass the plugin directory explicitly:

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

### Code style

The code style follows [RakuyoKit/swift](https://github.com/RakuyoKit/swift):

```bash
# Format the code
mise run swift:format

# Check the code style
mise run swift:lint
```

### Running the bundled app

Only one copy of Flotilla can run at a time, so quit your installed Flotilla before launching `build/Flotilla.app`.

Local builds are ad-hoc signed, so you may need to grant Accessibility access again after rebuilding.

### Logs

Flotilla writes its logs under the `com.rakuyo.flotilla` subsystem:

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.rakuyo.flotilla"'
```

### Website

The [website](https://flotilla.rakuyo.dev/) source is in `website/`, and it's deployed to GitHub Pages. The build fetches release information with `gh`, so run `gh auth login` first. The "官网" section of [AGENTS.md](AGENTS.md) has the details.

```bash
# Assemble the website into build/site/
mise run site:build

# Assemble it and preview it at http://localhost:8000/
mise run site:preview
```

## Contributing

Before opening a pull request, make sure `mise run swift:lint` and `swift test` both pass. CI runs the same checks, then builds and bundles the app.

Branch names, commit messages, and other conventions are in [AGENTS.md](AGENTS.md), and [docs/requirements](docs/requirements) describes how each feature should work. Both are written in Chinese.

## Friends

[LINUX DO](https://linux.do)

## License

Flotilla is licensed under the [GNU General Public License v3.0](LICENSE). It uses Sparkle for updates, and Sparkle's license ships with the app at `Contents/Resources/Sparkle-LICENSE.txt`.
