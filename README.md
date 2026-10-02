<p align="center">
  <img src="brand/app-icon.png" alt="Stow" width="96" height="96" />
</p>

<h1 align="center">Stow</h1>

<p align="center">
  <strong>On-device clipboard history for macOS, ready in a keystroke.</strong>
</p>

<p align="center">
  <a href="./docs/clipboard-features.md">Feature catalog</a>
  &nbsp;·&nbsp;
  <a href="#current-status">Current status</a>
  &nbsp;·&nbsp;
  <a href="#getting-started">Getting started</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-pre--alpha-6b7280?style=flat-square" alt="Status: pre-alpha" />
  <img src="https://img.shields.io/badge/platform-macOS-0ea5e9?style=flat-square" alt="Platform: macOS" />
  <img src="https://img.shields.io/badge/history-on_this_Mac-14b8a6?style=flat-square" alt="History stays on this Mac" />
  <img src="https://img.shields.io/badge/first_version-15_of_15-8b5cf6?style=flat-square" alt="First version: 15 of 15" />
  <img src="https://img.shields.io/badge/later_wave-2_of_11-8b5cf6?style=flat-square" alt="Later wave: 2 of 11" />
</p>

---

## Overview

Stow is a Dock and menu-bar clipboard manager for macOS. The library window holds the history, ⌘⇧C opens a quick panel, the selected item is shown in full, and paste returns focus to the previous application. History is stored on the Mac, and the app runs without an account.

The core interaction follows Maccy: incremental search, pinning, pause, and exclusion of concealed pasteboard types, including copies from password managers. Stow presents that history in a panel, with a complete preview, recognition of each clip’s type, and a snippet library kept separate from history.

Every addition is held to the same standard. It must be quicker to use than scrolling a truncated menu. Transforms and synchronization run only when explicitly requested. Password-manager copies are never written to the database.

---

## Current Status

Honest snapshot against [`docs/clipboard-features.md`](./docs/clipboard-features.md).

### In the repo

- **Dock and menu-bar app** — library window, ⌘⇧C quick panel, local SQLite history, and paste back into the previous app. Password-manager and concealed pasteboard types are ignored.
- **First version** — preview, type recognition, search, duplicate folding, snippets with the same filters and day groups, undo on the toast, secret skip, app exclusions, and a first-run splash that explains the shortcut and Accessibility. Fifteen of fifteen.
- **Match Maccy** — seven of seven, including pin, pause, ignore-next-copy, and number keys.
- **Later wave, started** — clip transforms (HTML to Markdown, pretty JSON, unwrap lines, strip tracking) and multi-paste. Two of eleven.
- **Tests** — history, search, classification, transforms, colors, secret detection, syntax highlighting, paste targets, and pasteboard policy.

### Not in this version

OCR, snippet collections, a panel that stays open while pasting, storage rules, sync, and a Maccy import stay unchecked. Transforms and multi-paste are already in the app.

---

## What's next

The first version is in the app, along with clip transforms and multi-paste. What remains in [`docs/clipboard-features.md`](./docs/clipboard-features.md) waits until those two feel solid in daily use. Snippets stay a separate list until they grow into boards. OCR and sync stay off.

| Wave | Focus |
| --- | --- |
| **Match Maccy** | Hotkey and menu-bar icon, search-as-you-type, number keys, pin, delete and clear, pause and ignore-next-copy, concealed pasteboard types |
| **First version** | Panel, preview, type recognition, filters, shortcut footer and context menu, paste-target awareness, a separate snippets list, undo on the toast, secret skip, app exclusions, source and time, duplicate folding, drag-out images and files, paused icon, first-run splash |
| **Later, in the app** | Clip transforms and multi-paste, in copy order, with the join prompt on the current window |
| **Later, still open** | OCR, collections, templates, abbreviations, a pinnable panel, encrypted retention, an export file, optional sync, Shortcuts |
| **Further** | Slots, edit-before-paste (Edit Clip, which updates the stored clip, is already in the app), copy bursts, per-app defaults, recording-aware privacy, a one-time Maccy history import |

The paste loop, transforms, and multi-paste are in the app. The next increment is still the rest of the later wave: collections, a panel that stays open while you paste, and storage rules. OCR and sync stay later, and both run only when you ask for them.

---

## Product surface

Full wording and checkboxes live in the catalog. This is the map.

| Area | Shipped | Still later |
| --- | --- | --- |
| **See it** | Preview pane, type recognition (text, rich text, code, link, email, color, image, file), drag-out thumbnails, source app and Today / Yesterday / Older | — |
| **Find it** | Type and pin chips on history and snippets, operators like `type:image` and `from:today`, duplicate folding | On-device OCR for text inside screenshots |
| **Paste it** | Return copies. Option-Return pastes. Shift-Option-Return pastes plain text. Terminals get plain text. A secure field is copied, not typed into. Right-click can edit the stored clip | — |
| **Transforms** | HTML to Markdown, pretty JSON, unwrap lines, and strip tracking parameters. Each copies a new version and leaves the stored clip alone | — |
| **Multi-paste** | Several clips paste in the order they were copied, joined with a newline, a comma, or a separator you type | — |
| **Reuse it** | Snippets live apart from history, so Clear history leaves them. They pin, filter, and show the day | Collections, fill-in fields, abbreviations you opt into per snippet |
| **Privacy** | App exclusions, secret skip, a menu-bar icon that shows pause | Encryption, separate expiry for text and images, a storage trim |
| **Window** | Library window plus a quick panel, one undo toast after delete or clear, first-run splash, hideable shortcut footer | Compact or comfortable rows, pin the panel open across pastes |
| **Carry it** | — | Export file, opt-in encrypted sync, Universal Clipboard toggle, Shortcuts actions |

### How the window should feel

- **Open.** The menu bar opens the library. ⌘⇧C toggles the quick panel. Search is focused. Nothing is selected until you choose a clip.
- **Read.** Two lines per clip: a type mark, a preview, then the source app and time. The preview pane shows the whole clip, including images.
- **Act.** The shortcut footer lists Paste, Plain, Copy, Pin, and Delete. The same actions are on the right-click menu, along with Edit Clip. Rows do not show those buttons.

### Leave these out

A required account, a shared team clipboard, a plugin store, and an assistant that rewrites every copy. Text expansion that fires in every text field is also a poor default.

---

## Tech stack

| Layer | What is actually here |
| --- | --- |
| Platform | macOS 14 Dock and menu-bar app |
| UI | AppKit panel and status item, SwiftUI views |
| Language | Swift 6 |
| Storage | SQLite in Application Support, images beside the database |
| Spec | [`docs/clipboard-features.md`](./docs/clipboard-features.md) |

---

## Getting started

### Clone

```bash
git clone https://github.com/NehangPatel23/Stow.git
cd Stow
```

### Build and run

```bash
xcodebuild -project Stow.xcodeproj -scheme Stow -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Stow.app
```

Stow appears in the Dock and the menu bar. The default shortcut is **⌘⇧C**, which toggles the quick panel. The first launch explains that shortcut and the Accessibility permission paste needs. A click in the menu bar opens the library. Nothing is selected until you choose a clip. Return copies it. Option-Return pastes it back. Shift-Option-Return pastes plain text.

```bash
xcodebuild -project Stow.xcodeproj -scheme Stow -destination 'platform=macOS' -derivedDataPath build test
```

Check a box in [`docs/clipboard-features.md`](./docs/clipboard-features.md) only after that behavior works, and update the Done counts plus the first-version badge in this README.

---

## Known limitations

Specific, and current:

- **Paste needs Accessibility.** The clip is written to the clipboard either way. The keystroke that pastes it into the previous app needs that permission.
- **Not notarized.** This is a local build. macOS may ask you to allow it the first time you open it.
- **Large copies are trimmed.** Text is stored up to one million characters. An image over 12 MB is kept at a reduced size.
- **No import path from Maccy yet.** "Import a Maccy history" is listed under Further ideas.
- **Sync is off.** History stays on this Mac until a later-wave export or opt-in sync exists.

---

## Documentation

| Doc | Role |
| --- | --- |
| [`docs/clipboard-features.md`](./docs/clipboard-features.md) | Feature spec and status tracker: Maccy behaviors, first version, later wave, further ideas |

---

## Author

**Nehang Patel** · University of Southern California

[GitHub](https://github.com/NehangPatel23) · [LinkedIn](https://www.linkedin.com/in/nehangpatel/)
