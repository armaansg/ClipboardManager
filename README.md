# Clipboard Manager for macOS

A free, local-only clipboard history manager for macOS. It quietly remembers what you copy
(text, rich text, images, links, files) and shows it in a translucent panel at the bottom of your
screen when you press **⌘⇧V**. Pick an item and it goes back on your clipboard, ready to paste
with ⌘V in whatever app you were using.

- **Private by design.** Nothing leaves your Mac: no network access, no accounts, no analytics.
- **Password-safe.** Items marked as concealed by password managers (1Password, Bitwarden, Keychain, …) are never stored.
- **No scary permissions.** It does not ask for Accessibility or Screen Recording.
- **Lightweight.** Menu-bar-only, near-zero idle CPU, 7-day rolling history capped at 500 MB (both adjustable).
- **Fast to use.** Type to search, ⌘1–9 to grab a card, drag cards straight into other apps.

Requires macOS 14 Sonoma or later on Apple Silicon. On macOS 26 Tahoe the panel uses Liquid Glass.

## Getting it

There is no packaged download yet, so you build it yourself. It takes about two minutes.

1. Install Xcode from the Mac App Store (Xcode 16 or newer) and open it once to finish setup.
2. Clone this repository:
   ```sh
   git clone https://github.com/<your-username>/ClipboardManager.git
   cd ClipboardManager
   ```
3. Build and install to `/Applications`:
   ```sh
   Scripts/build-release.sh
   ```
   The script builds a Release copy, installs it as `/Applications/ClipboardManager.app`, and launches it.

If Xcode is installed but the script says `xcodebuild requires Xcode`, point the tools at it once:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Alternatively open `ClipboardManager.xcodeproj` in Xcode and press Run. The app is ad-hoc signed,
which is fine for running on your own Mac; a signed and notarized download is planned.

## First run

A welcome window tells you the app lives in the menu bar and shows the shortcut. After that, the
clipboard icon in the menu bar is the whole UI: there is no window and no Dock icon.

- Press **⌘⇧V** (or left-click the menu bar icon) to open the panel. Press it again, press Esc,
  click anywhere else, or pick an item to close it.
- **Right-click** the menu bar icon for the menu: pause recording, clear history, storage used,
  Launch at Login, open the storage folder, **Settings…**, Check for Updates, quit.
- Enable **Launch at Login** so it starts with your Mac. This only works from the
  `/Applications` copy, which is where the install script puts it.

> **Shortcut conflict.** ⌘⇧V is "Paste and Match Style" in many apps. While this app runs, the
> global shortcut wins. Change it in Settings → General if that bothers you.

## Using the panel

| Action | How |
| --- | --- |
| Open / close | ⌘⇧V, or left-click the menu bar icon |
| Search | just start typing; Delete edits, Esc clears |
| Pick an item | click a card, ← / → then Return, or ⌘1 … ⌘9 for the first nine cards |
| Copy text without formatting | hold ⌥ while picking (or flip the default in Settings) |
| Drag into another app | drag a card out of the panel: text, link, image file, or file |
| Pin / unpin | hover a card and click the pin |
| Delete | hover a card and click the trash, or select with arrows and press ⌘Delete |
| Filter | "Filter" button at the top right: All, Text, Images, Links, Files, Pinned |
| Peek at long text | hover a text card for a moment |

Pinned items sit at the far left, behind a divider, and never expire. Everything else is newest
first. Copying something you already have moves it to the front instead of duplicating it. A short
"Copied" confirmation appears after you pick something.

## Settings

Right-click the menu bar icon → **Settings…** (or ⌘, while the menu is open).

- **General:** record a new shortcut (click the field and press the keys), Launch at Login,
  plain-text copying by default, panel height.
- **History:** how many days to keep unpinned items, the storage cap, storage used, clear buttons.
- **Exclusions:** apps whose copies are never recorded. Add password managers or terminals that
  don't flag their clipboard data. Recording also pauses automatically whenever a secure text field
  (password entry) has keyboard focus.
- **Updates:** optional automatic update checks (off by default; see below).

The compiled-in default shortcut lives in `ClipboardManager/App/AppConfig.swift` if you want to
change what a fresh install starts with.

## What gets stored, and where

- Database: `~/Library/Application Support/ClipboardManager/history.sqlite`
- Images, thumbnails, rich-text data: `~/Library/Application Support/ClipboardManager/blobs/`
- Unpinned items expire after 7 days (checked at launch and hourly). Pinned items never expire.
- The store is capped at 500 MB; the oldest unpinned items go first.
- Images are downscaled to a 2048 px longest edge and saved as JPEG, or PNG when they have real
  transparency. Anything still over 10 MB is skipped. Cards show 256 px thumbnails.
- Skipped on purpose: blank text, items flagged `org.nspasteboard.ConcealedType`,
  `TransientType`, or `AutoGeneratedType`, and anything copied while recording is paused.

"Open Storage Folder" in the menu shows you everything; delete the folder to start over.

## Uninstalling

Quit from the menu bar, then delete `/Applications/ClipboardManager.app` and
`~/Library/Application Support/ClipboardManager`. If Launch at Login was on, turn it off in the
menu first or remove the entry in System Settings → General → Login Items.

## Distributing it (signing, notarization, updates)

Your own builds are ad-hoc signed and run fine locally. To hand the app to other people you need a
Developer ID certificate, notarization, and (optionally) a Sparkle update feed. `Scripts/release.sh`
does all of it:

```sh
# one time: create a notarytool profile and Sparkle keys
xcrun notarytool store-credentials notary --apple-id you@example.com --team-id TEAMID
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys   # paste the public key into Supporting/Info.plist (SUPublicEDKey)
# set SUFeedURL in Supporting/Info.plist to where appcast.xml will live

SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=notary \
APPCAST_DOWNLOAD_PREFIX=https://github.com/you/ClipboardManager/releases/download/v1.0/ \
Scripts/release.sh
```

This produces `dist/ClipboardManager-<version>.zip` (notarized and stapled) and `dist/appcast.xml`.
Until a public key and feed URL are present in `Info.plist`, the in-app updater stays disabled and
"Check for Updates…" explains why. Update checks are the only network activity in the app and are
off unless the user turns them on.

## For developers

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/ClipboardManager.app

# Debug builds can be driven from the terminal (no synthetic input needed):
swift Scripts/debug-command.swift show|hide|toggle|status|pause|resume|retention|clear [all]|type <text>|quick <n>|settings|welcome
log stream --level info --predicate 'subsystem == "dev.armaan.ClipboardManager"' --style compact
```

```
ClipboardManager/
  App/        AppDelegate (entry point, wiring), AppConfig (defaults), AppSettings (UserDefaults),
              UpdateManager (Sparkle wrapper), WelcomeTipController (first run)
  Settings/   Settings window: shortcut recorder, history, exclusions, updates
  MenuBar/    NSStatusItem, menu, Launch at Login (SMAppService)
  Hotkey/     Carbon RegisterEventHotKey wrapper (no Accessibility needed)
  Clipboard/  300 ms change-count poller, pasteboard reader/writer, capture processor
  Storage/    SQLite wrapper, HistoryStore (dedupe + retention), BlobStore, ClipItem
  Images/     compression, downscaling, thumbnails
  Panel/      non-activating NSPanel, glass backdrop, controller, SwiftUI panel + cards, hover preview, Copied HUD
  Support/    caches, formatters, code-detection heuristic
Supporting/Info.plist    LSUIElement agent app
Scripts/                 build-release.sh (local install), release.sh (signed + notarized + appcast),
                         make-icon.swift (regenerates the app icon), debug-command.swift
```

Built with Swift and SwiftUI, AppKit where the platform requires it. The only dependency is
[Sparkle](https://sparkle-project.org) for optional software updates, pulled in via Swift Package Manager.
