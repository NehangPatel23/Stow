# Clipboard Manager Features

Status catalog for Stow. Maccy keeps a local clipboard history and gets out of the way. Stow keeps that speed and privacy, then makes each clip readable, reusable, and safe to keep. Baseline for the behaviors below: [maccy.app](https://maccy.app) and the [p0deje/Maccy](https://github.com/p0deje/Maccy) readme.

Check a box when that behavior ships. Leave the description in place so the spec stays readable after the box is checked.

> **Product rule.** Every extra feature has to be faster than scrolling a truncated menu. History stays on the Mac. Transforms and sync happen only when the user asks. Password-manager copies stay out of the database.

## Snapshot

Update the Done column when you check boxes.

| Track | Scope | Items | Done |
| --- | --- | ---: | ---: |
| Match Maccy | Behaviors the first paste loop still has to have | 7 | 7 |
| First version | Build before daily paste feels right | 15 | 15 |
| Later wave | Add after the first version is trustworthy | 11 | 11 |
| Further ideas | After history, preview, and paste beat Maccy | 26 | 5 |

## Match Maccy first

These are the behaviors people already expect from the official app. Shipping the richer panel without them would feel like a downgrade.

- [x] **Shortcut and menu-bar icon.** Open from a global hotkey or the menu bar, then return to the app you were in.
- [x] **Search as you type.** The list filters immediately. Return copies, Option-Return pastes, Shift-Option-Return pastes plain text.
- [x] **Numeric shortcuts.** The first results stay reachable with the number keys, without walking the list.
- [x] **Pin.** A pinned item stays at the top until you unpin it.
- [x] **Delete and clear.** Remove one item, clear unpinned history, or clear everything.
- [x] **Pause and ignore next copy.** Stop recording, or skip a single copy, when you are about to handle something sensitive.
- [x] **Concealed pasteboard types.** Ignore transient, concealed, auto-generated, and known password-manager types so secrets a password manager clears are not kept.

## Features worth adding

Green in the original catalog is the first version. Blue is the later wave. Those two waves are the labels below.

### See it

- [x] **Preview pane** — First. A selected clip shows in full beside the list. Maccy only reveals the rest of a truncated row after a hover delay.
- [x] **Content recognition** — First. Mark each row as text, rich text, code, link, email, color, image, or file. Code gets syntax highlighting. A color shows a swatch and copies as hex, RGB, or HSL.
- [x] **Images and files you can drag out** — First. Thumbnails show dimensions and size. Drag an image or a file clip straight into Finder, Mail, or a browser instead of pasting blindly.
- [x] **Source and time** — First. Each row names the app that copied it and groups history as Today, Yesterday, and Older, so a long list stays scannable.

### Find it

- [x] **Structured search** — First. Filter chips for type and pinned items, plus operators such as `type:image`, `app:Safari`, `from:today`, `board:Support`, and `abbr:addr`. Matches are highlighted in the row.
- [x] **Duplicate folding** — First. The same text copied five times appears once, with a count. Opening it shows the recent copies if you need an older one.
- [x] **On-device OCR** — Later. Text inside screenshots is indexed on the Mac, so a search for an error message finds the image that contains it.

### Paste it

- [x] **Visible row actions** — First. Paste, plain-text paste, copy, pin, and delete are on the shortcut footer and the right-click menu. The row itself has no buttons. Keyboard shortcuts still work.
- [x] **Paste-target awareness** — First. Terminals and code editors get plain text. If the front field is a secure password field, the app copies the clip and does not type into it.
- [x] **Clip transforms** — Later. Explicit actions, never automatic rewrites: HTML to Markdown, pretty-print JSON, unwrap lines, and strip tracking parameters from a URL. A button appears only when that rewrite applies, and it copies the result. The stored clip stays as it was.
- [x] **Multi-paste** — Later. ⌘-click toggles clips and ⇧-click extends the range. Right-click pastes them in the order they were copied, joins them with a comma, or joins them with a separator you type. The prompt stays on the current window. The list itself stays newest first.

### Reuse it

- [x] **Snippets library** — First. Saved text lives apart from history. Clearing history does not delete a support reply, an address, or a git command you pinned on purpose. Snippets use the same type filters, including Pinned. With boards enabled they group as Pinned, each board, and Unfiled.
- [x] **Collections and reorder** — Later. Group snippets into small boards (Support, Git, Design). Drag a snippet onto another, or use ⌥⌘↑ / ⌥⌘↓ and the context menu, to reorder. Filter with board chips or `board:Support`. History and snippets stay separate libraries.
- [x] **Fill-in templates** — Later. A snippet can contain fields such as `{{name}}`, `{{ticket}}`, and `{{date}}`. Pasting opens a small form, then pastes the filled text. `date` and `time` start filled in.
- [x] **Optional abbreviations** — Later. An abbreviation expands only for snippets you mark, after you type it and a delimiter such as space or return. Secure fields and Stow itself are skipped. A Settings toggle can turn expansion off without clearing the marks.

### Privacy

- [x] **App exclusions in Settings** — First. Pick apps that should never be recorded, and a one-hour pause for the front app. Password-manager and concealed pasteboard types stay ignored, as in Maccy.
- [x] **Secret skip** — First. Private-key blocks, card numbers, and long token-like strings are not stored. The menu-bar icon shows a quiet skipped-copy state you can override for that one item.
- [x] **Paused state you can see** — First. Pause, pause for an hour, and ignore-next-copy change the menu-bar icon. Maccy can do these actions, but the paused state is easy to miss.
- [x] **Storage rules** — Later. History is encrypted with the Mac's data protection. Text and images can expire on different schedules, with a storage readout and a one-click trim.

### Window

- [x] **Panel, not a menu** — First. The menu bar shows recent clips; More clips… opens the library window. ⌘⇧C opens a floating quick panel with search already focused. A menu alone truncates rows; these windows have room for a list and a preview.
- [x] **Undo** — First. Deleting a clip or clearing history shows one in-window toast with an undo icon for about six seconds. Accidental clears are the failure people remember.
- [x] **First-run and shortcut footer** — First. Launch opens with a short splash, then one screen explains the hotkey and the Accessibility permission required to paste. A hideable footer lists the shortcuts. There is no permission banner inside the history window.
- [x] **Density and a pinned panel** — Later. Compact or comfortable rows in Settings. The pin control in the header, or Settings, keeps the panel open while you paste several clips instead of dismissing after every choice.

### Carry it

- [x] **Local archive** — Later. Export and import a file you choose. Export can leave clips out; import can add new items only or replace everything. History does not leave the Mac unless you save that file.
- [x] **Opt-in sync** — Later. Encrypted sync across your own Macs is off until you enable it. Snippets and history can sync separately. Items flagged as secrets never sync.
- [x] **Universal Clipboard and Shortcuts** — Later. A toggle includes or ignores copies arriving from an iPhone. Shortcuts actions cover latest clip, search, and save as snippet.

## How the window should feel

| Moment | Behavior |
| --- | --- |
| Open | Stow is a Dock app and a menu-bar app. The menu bar opens recent clips; More clips… opens the library near the size of the screen. ⌘⇧C toggles a quick panel. Search is focused. Nothing is selected until you click a clip. |
| Read | Each row shows a type mark, a preview, then the source app and time. The preview pane shows the whole clip, including images and readable rich text. |
| Act | Return copies. Option-Return pastes into the previous app. Shift-Option-Return pastes plain text. The footer lists those shortcuts. Right-click adds Edit Clip or Edit Snippet, Save as Snippet on history, and Delete. |

## Build order

Ship a trustworthy history before snippets, OCR, or sync. The first version is the panel, preview, type recognition, filters, visible actions, paste-target awareness, a separate snippets list, undo, secret skip, and app exclusions.

The later wave is in the app: clip transforms, multi-paste, collections, fill-in templates, a pinned compact panel, storage rules, optional abbreviations, a local archive, on-device OCR, opt-in encrypted folder sync, a Universal Clipboard toggle, and Shortcuts actions for latest clip, search, and save as snippet.

## Further ideas

These wait until history, preview, and paste already feel better than Maccy. Check one only after the first-version boxes above are done.

<details>
<summary>Slots (4)</summary>

- [x] **One-shot paste.** Paste an older clip once and leave the system clipboard on whatever you copied last.
- [x] **Named slots.** Keep a few clips in slots, like registers, and paste a slot with its own shortcut while the panel stays closed.
- [x] **Menu of recent items.** The menu-bar icon opens the last several clips for a click, so a mouse path never needs the full panel.
- [x] **Sort by use.** A Frequent view ranks clips by how often you paste them, separate from the order you copied them.

</details>

<details>
<summary>Edit (7)</summary>

- [ ] **Edit before paste.** Change the text in the preview, then paste that version. The original history row stays as it was. Edit Clip, which is already in the app, is different: it updates the stored clip.
- [ ] **Split lines.** Turn a multi-line copy into one clip per line, so a pasted list can be used one entry at a time.
- [ ] **Line tools.** Change case, sort lines, drop duplicate lines, trim whitespace, or turn lines into a comma-separated list.
- [ ] **Length in the preview.** Show characters, words, and lines on text clips. Writers can check a passage without pasting it into a counter.
- [ ] **Do the obvious thing.** A link can open, an email can start a message, an address can open in Maps, and a date can become a calendar event.
- [ ] **Keep the page URL.** When a browser copied both the selection and the page URL, store both. One action pastes the selection as a Markdown link.
- [ ] **Inline result.** A copied sum, currency amount, or simple unit conversion shows the result in the preview. The stored clip stays the original text.

</details>

<details>
<summary>Session (3)</summary>

- [ ] **Copy bursts.** Copies from the same app a few seconds apart collapse into one session. You can expand the session and paste the whole group.
- [ ] **Diff two clips.** Pick two text clips and see what changed before you paste either one.
- [ ] **Notes and snippet history.** Add a short note to a snippet. Editing a snippet keeps the previous wording so you can restore it.

</details>

<details>
<summary>Context (3)</summary>

- [ ] **Per-app and Focus defaults.** The front app or the active Focus can choose the collection you see first and whether paste is plain or rich.
- [ ] **Selection chip.** After you select text, a small chip offers plain copy and save-as-snippet. The full panel stays closed.
- [ ] **Desktop widget.** A widget shows a handful of snippets. Control Center gets a pause switch next to the menu-bar icon.

</details>

<details>
<summary>Trust (6)</summary>

- [ ] **Hide contents while presenting.** When the screen is being recorded or shared, the panel shows titles only until sharing stops.
- [ ] **Touch ID after idle.** Opening history after the Mac has been idle can require Touch ID. The menu-bar app itself keeps running.
- [ ] **Short-code expiry.** A copied six-digit code deletes itself after about a minute. You choose the pattern and the lifetime.
- [ ] **Ignore patterns.** A list of patterns you write, such as one-time codes or tracking links, is never stored.
- [x] **Skip our own copies.** Pasting from this app does not create another history row of the same clip.
- [ ] **Large-copy cap.** A huge image or file is stored as a reference with a size warning, or skipped, so one copy cannot fill the disk.

</details>

<details>
<summary>Access (2)</summary>

- [ ] **Import a Maccy history.** A one-time import reads the local Maccy database you already have, so switching apps keeps your pins and recent text.
- [ ] **Accessible panel.** VoiceOver names every action, reduced motion removes extra animation, rows can grow, and the panel reopens on the display where you left it.

</details>

## Leave these out

A required account, a shared team clipboard, a plugin store, and an assistant that rewrites every copy. Global text expansion that fires for every keystroke is also a poor default; abbreviations stay opt-in per snippet. Those products are slower, and they put clipboard contents somewhere the user did not choose.
