# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-09-17

### Added
- Clipboard history for text, rich text, images, links and files, stored locally in SQLite.
- Bottom-anchored glass panel on the display under the cursor, toggled with ⌘⇧V or the menu bar icon.
- Type-to-search, arrow-key navigation, ⌘1–9 quick selection, ⌥ for plain-text copies.
- Pinning, per-card delete, filters, hover preview for long text, drag-out to other apps.
- Settings window: recordable shortcut, retention window, storage cap, panel height, excluded apps.
- Privacy guards: concealed/transient pasteboard types, secure keyboard input, excluded apps, pause.
- Image compression (JPEG 0.7 / PNG for transparency), 2048 px downscale, 256 px thumbnails.
- 7-day rolling retention and 500 MB cap with oldest-first eviction; pinned items exempt.
- Launch at Login via SMAppService, first-run welcome, "Copied" confirmation.
- Optional Sparkle updates, enabled only when a signing key and feed URL are configured.
