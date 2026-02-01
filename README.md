# DropZone

Floating drop target for macOS. Stash files while you work, then drag them back out.

## Features
- Overlay appears near the cursor during a file drag
- Trigger: during a file drag, hold Shift for ~0.25s or shake the cursor; press Shift to toggle manually
- Drop to stash; items keep the panel pinned while non-empty
- Drag items out; Shift-drag to export everything at once
- Instant actions: New Folder (create + move), Move To, Reveal in Finder

## Requirements
- macOS 26.0+
- Swift 5.10 toolchain

## Build
- Open `DropZone.xcodeproj` and Run
- Optional: regenerate the project with `xcodegen` using `project.yml`

## Notes
- Session-only for now (persistence disabled; items reset on launch)
