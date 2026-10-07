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
  <img src="https://img.shields.io/badge/later_wave-11_of_11-8b5cf6?style=flat-square" alt="Later wave: 11 of 11" />
  <img src="https://img.shields.io/badge/further_ideas-7_of_26-8b5cf6?style=flat-square" alt="Further ideas: 7 of 26" />
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
- **First version** — preview, type recognition, search, duplicate folding, snippets with the same type filters, undo on the toast, secret skip, app exclusions, and a first-run splash that explains the shortcut and Accessibility. Fifteen of fifteen.
- **Match Maccy** — seven of seven, including pin, pause, ignore-next-copy, and number keys.
- **Later wave** — clip transforms, multi-paste, snippet collections, fill-in templates, a pinned panel with compact rows, storage rules, optional abbreviations, a local archive, on-device OCR, opt-in encrypted folder sync, Universal Clipboard toggle, and Shortcuts actions. Eleven of eleven.
- **Tests** — history, search, classification, transforms, line split, colors, secret detection, syntax highlighting, paste targets, pasteboard policy, snippet templates, abbreviations, storage rules, local archive, image OCR, and sync crypto.

### Not in this version

A one-time Maccy history import and most further ideas stay unchecked. The later wave above is in the app.

---

## What's next

The first version and later wave are in the app. What remains in [`docs/clipboard-features.md`](./docs/clipboard-features.md) is further ideas — pick those up once daily use feels solid. Sync stays off until you enable it and choose a folder.

| Wave | Focus |
| --- | --- |
| **Match Maccy** | Hotkey and menu-bar icon, search-as-you-type, number keys, pin, delete and clear, pause and ignore-next-copy, concealed pasteboard types |
| **First version** | Panel, preview, type recognition, filters, shortcut footer and context menu, paste-target awareness, a separate snippets list, undo on the toast, secret skip, app exclusions, source and time, duplicate folding, drag-out images and files, paused icon, first-run splash |
| **Later wave** | Clip transforms and multi-paste, snippet boards, `{{field}}` fill-in templates, keep-open pin, compact rows, storage rules, opt-in abbreviations, local archive, on-device OCR, opt-in encrypted folder sync, Universal Clipboard toggle, Shortcuts (latest clip, search, save as snippet) |
| **Further** | One-shot paste, named slots (⌃⌥1–5), menu of recent items, Frequent, edit-before-paste, and split lines are in the app. Still open: line tools, copy bursts, per-app defaults, recording-aware privacy, a one-time Maccy history import |

Daily use and the further-ideas list are next — not another later-wave checkbox.

---

## Product surface

Full wording and checkboxes live in the catalog. This is the map.

| Area | Shipped | Still later |
| --- | --- | --- |
| **See it** | Preview pane, type recognition (text, rich text, code, link, email, color, image, file), drag-out thumbnails, source app and Today / Yesterday / Older | — |
| **Find it** | Type, pin, and Frequent chips on history; type and pin chips on snippets; operators like `type:image`, `from:today`, `board:Support`, and `abbr:addr`; duplicate folding; on-device OCR for text inside screenshots | — |
| **Paste it** | Return copies. Option-Return pastes. Shift-Option-Return pastes plain text. Command-Option-Return pastes once and restores the previous clipboard. Named slots (⌃⌥1–5) paste a saved register with the panel closed. Terminals get plain text. A secure field is copied, not typed into. Edit for Paste changes the preview only; Edit Clip updates the stored clip. Split lines turns a multi-line clip into one history row per line and leaves the original | — |
| **Transforms** | HTML to Markdown, pretty JSON, unwrap lines, and strip tracking parameters. Each copies a new version and leaves the stored clip alone | — |
| **Multi-paste** | Several clips paste in the order they were copied, joined with a newline, a comma, or a separator you type | — |
| **Reuse it** | Snippets live apart from history. Boards group them. `{{name}}` fields open a fill-in form before paste. Marked abbreviations expand while typing | — |
| **Privacy** | App exclusions, Universal Clipboard toggle, secret skip, a menu-bar icon that shows pause, Mac data protection, separate text and image expiry, storage readout and trim | — |
| **Window** | Library window plus a quick panel, pin to keep it open while pasting, compact or comfortable rows, one undo toast, first-run splash, hideable shortcut footer | — |
| **Carry it** | Export and import a `.stowarchive` file you choose. Export can leave clips out; import can add new items only or replace everything. Opt-in encrypted sync through a folder you choose (history and snippets separately; secrets never sync). Shortcuts actions for latest clip, search, and save as snippet | — |

### How the window should feel

- **Open.** The menu bar opens recent clips; More clips… opens the library. ⌘⇧C toggles the quick panel. Search is focused. Nothing is selected until you choose a clip.
- **Read.** Two lines per clip: a type mark, a preview, then the source app and time. The preview pane shows the whole clip, including images.
- **Act.** The shortcut footer lists Paste, Plain, Once, Copy, Pin, and Delete. The same actions are on the right-click menu, along with Edit Clip or Edit Snippet. Rows do not show those buttons.

### Leave these out

A required account, a shared team clipboard, a plugin store, and an assistant that rewrites every copy. Global text expansion that fires for every keystroke is also a poor default; Stow only expands abbreviations you mark on a snippet.

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

Stow appears in the Dock and the menu bar. The default shortcut is **⌘⇧C**, which toggles the quick panel. The first launch explains that shortcut and the Accessibility permission paste needs. A click in the menu bar opens recent clips; More clips… opens the library. Nothing is selected until you choose a clip. Return copies it. Option-Return pastes it back. Shift-Option-Return pastes plain text.

```bash
xcodebuild -project Stow.xcodeproj -scheme Stow -destination 'platform=macOS' -derivedDataPath build test
```

Check a box in [`docs/clipboard-features.md`](./docs/clipboard-features.md) only after that behavior works, and update the Done counts plus the matching badge in this README.

---

## Known limitations

Specific, and current:

- **Paste needs Accessibility.** The clip is written to the clipboard either way. The keystroke that pastes it into the previous app needs that permission. Abbreviation expansion while typing needs it too.
- **Not notarized.** This is a local build. macOS may ask you to allow it the first time you open it.
- **Large copies are trimmed.** Text is stored up to one million characters. An image over 12 MB is kept at a reduced size.
- **No import path from Maccy yet.** "Import a Maccy history" is listed under Further ideas.
- **Sync is off by default.** Enable it in Settings, choose a shared folder, and set the same passphrase on each Mac. History stays local until you do.
- **OCR is local and best-effort.** Text inside new image clips is indexed on the Mac in the background; older screenshots are backfilled on launch.

---

## Documentation

| Doc | Role |
| --- | --- |
| [`docs/clipboard-features.md`](./docs/clipboard-features.md) | Feature spec and status tracker: Maccy behaviors, first version, later wave, further ideas |

---

## Author

**Nehang Patel** · University of Southern California

[GitHub](https://github.com/NehangPatel23) · [LinkedIn](https://www.linkedin.com/in/nehangpatel/)
