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

##Preview

<img width="1916" height="584" alt="Screenshot 2026-09-17 at 1 01 11 PM" src="https://github.com/user-attachments/assets/6198c0bd-f829-4c52-9e1c-a0ca6d66000f" />

## Download

**Homebrew** (recommended):

```sh
brew tap armaansg/tap
brew install --cask --no-quarantine clipboard-manager
```

`--no-quarantine` skips the Gatekeeper prompt described below; drop it once releases are signed.

**Manual:** grab the latest `.dmg` from the [Releases page](../../releases/latest), open it, and drag
**Clipboard Manager** into **Applications**. Then launch it from Applications (or Spotlight).

**First launch on an unsigned build.** Until releases are signed with an Apple Developer ID, macOS
will say it "cannot verify that this app is free of malware" and refuse to open it. That is
Gatekeeper, not a fault in the download. To approve it once:

1. Try to open the app and dismiss the warning.
2. Open **System Settings → Privacy & Security**, scroll down to the Security section.
3. Click **Open Anyway** next to the Clipboard Manager message, then confirm.

Or from a terminal: `xattr -dr com.apple.quarantine /Applications/ClipboardManager.app`.

Every release ships a `SHA256SUMS` file if you want to verify the download.

## Building from source

Requires Xcode 16 or newer from the Mac App Store.

```sh
git clone https://github.com/armaansg/ClipboardManager.git
cd ClipboardManager
Scripts/build-release.sh      # builds a Release copy, installs to /Applications, launches it
```

If the script says `xcodebuild requires Xcode`, point the command-line tools at Xcode once:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Or open
`ClipboardManager.xcodeproj` in Xcode and press Run.

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

## Releasing (maintainers)

Releases are built by GitHub Actions. Tag a commit and push the tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The **Release** workflow builds the app, packages a `.dmg` and `.zip`, writes `SHA256SUMS`, and
publishes a GitHub Release with everything attached. The tag sets the version number.

The same thing locally: `Scripts/release.sh` writes the artifacts to `dist/`.

### Homebrew tap

The cask lives in [armaansg/homebrew-tap](https://github.com/armaansg/homebrew-tap)
(`Casks/clipboard-manager.rb`). With a `TAP_GITHUB_TOKEN` repository secret (a fine-grained personal
access token with *Contents: write* on the tap repo), the Release workflow bumps the cask's version and
checksum on every tagged release. To do it by hand:

```sh
Scripts/update-cask.sh ../homebrew-tap/Casks/clipboard-manager.rb 1.0.1 <sha256 of the dmg>
```

### Signing and notarization

Without an Apple Developer account the build is ad-hoc signed and users must approve it once (see
Download). With one, add these repository secrets and the workflow signs and notarizes automatically:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | your *Developer ID Application* certificate exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | the password you set when exporting the `.p12` |
| `SIGNING_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` (from `security find-identity -v -p codesigning`) |
| `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD` | Apple ID, team ID, and an [app-specific password](https://support.apple.com/102654) for notarization |

### In-app updates (Sparkle)

Optional. Once set up, users get update prompts instead of re-downloading.

1. Build once so Swift Package Manager fetches Sparkle, then run
   `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`.
2. Put the printed public key into `Supporting/Info.plist` as `SUPublicEDKey`, and set `SUFeedURL` to
   `https://github.com/armaansg/ClipboardManager/releases/latest/download/appcast.xml`.
3. Export the private key (`generate_keys -x key.txt`) and add its contents as the `SPARKLE_PRIVATE_KEY` secret.

The Release workflow then attaches a signed `appcast.xml` to every release. Until steps 1–2 are done
the updater stays disabled and "Check for Updates…" explains why. Update checks are the only network
activity in the app, and they are off unless the user turns them on.

## For developers

The project has a unit-test target covering the pasteboard reader, capture processor, image pipeline,
history store (dedupe, retention, cap), and the panel view model (search, selection). CI runs it on every push.

```sh
# run the tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager -destination 'platform=macOS' test

# build and run the app

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
ClipboardManagerTests/   XCTest unit tests
Supporting/Info.plist    LSUIElement agent app
.github/workflows/       ci.yml (build + tests on every push), release.yml (tag → GitHub Release)
Scripts/                 build-release.sh (local install), release.sh (dmg/zip, optional signing + notarization + appcast),
                         make-icon.swift (regenerates the app icon), debug-command.swift
```

Built with Swift and SwiftUI, AppKit where the platform requires it. The only dependency is
[Sparkle](https://sparkle-project.org) for optional software updates, pulled in via Swift Package Manager.
