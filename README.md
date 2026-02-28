<p align="center">
  <img src="Sources/Orby/Resources/OrbyLogo.png" width="128" height="128" alt="Orby Logo">
</p>

<h1 align="center">Orby</h1>

<p align="center">
  <strong>A circular app switcher for macOS</strong><br>
  Navigate running apps with an intuitive radial interface right at your cursor.
</p>

<p align="center">
  <a href="https://github.com/dxiongya/orby/releases">Download</a> &middot;
  <a href="README_CN.md">中文文档</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/github/license/dxiongya/orby" alt="License">
  <img src="https://img.shields.io/github/v/release/dxiongya/orby" alt="Release">
</p>

---

## What is Orby?

Orby is a lightweight macOS menu bar utility that reimagines app switching. Instead of a flat list, it arranges your applications in a **circular layout** around your cursor, so you can visually find and switch to any app or window in one gesture.

**Why Orby?**

- **Spatial memory** — Apps appear in the same relative position, building muscle memory over time
- **Two modes** — Auto-detect running apps, or curate a fixed set of pinned apps that persist even when closed
- **Window-level control** — Expand any app to see all its windows with live previews
- **Zero clutter** — Lives in the menu bar, appears only when you need it, disappears when you don't
- **Keyboard-first** — Hotkeys, quick launch bindings, and modifier reveals keep your hands on the keyboard

## Features

### Circular App Switcher

Press **Option + Tab** to summon Orby. Your apps appear in a ring around your cursor. Click any app to switch instantly.

- Adaptive layout: 1 ring for up to 16 apps, 2 concentric rings for more
- Smart edge avoidance — the circle repositions near screen edges, menu bar, and dock
- Non-hovered apps gently push away when you expand one, keeping the view clean

### App Source Modes

Choose how Orby populates the circle:

- **Running Apps** (default) — Automatically shows all currently running applications. Apps appear and disappear as they launch or quit.
- **Manual Edit** — Curate a fixed set of pinned apps. Non-running apps appear dimmed with a dashed border; click to launch them. Closing a pinned app keeps it in the circle as inactive rather than removing it.

Switch between modes in **Settings > Apps**. In Manual Edit mode, use the visual Layout Preview to add, remove, and drag-reorder your pinned apps.

### Window Preview

Hover over an app bubble to reveal all its open windows in a smaller arc. Pause briefly and a **live preview** thumbnail appears.

- Pinch on trackpad to zoom the preview (1x to 2.5x)
- Configurable preview delay (0.1s – 2.0s)
- Can be toggled off in Settings

### Quick Launch (Option + 1–9)

Bind your most-used apps or specific windows to number keys for instant global access.

1. Right-click any bubble in Orby
2. Select **Bind to Option + [Number]**
3. Press **Option + Number** anytime to jump straight there

Bindings persist across sessions and auto-expire when the target app closes.

### App Tagging

Color-code your apps with tags for quick visual recognition.

- 10 built-in colors: Red, Blue, Green, Orange, Purple, Pink, Yellow, Gray, Cyan, Mint
- 5 default presets: Work, Personal, Dev, Design, Chat
- Create custom tags via right-click or Settings
- Tags persist across sessions

### Sub-Window Reorder

Long-press a sub-window bubble and drag to rearrange the order. Your custom order persists until the app is relaunched.

- Choose **clockwise** or **counter-clockwise** sort direction in Settings (applies to both apps and sub-windows)
- New windows automatically appear at the end of the arc

### Close Mode

Long-press any bubble to enter **Close Mode** — all bubbles start wobbling. Tap any wobbling bubble to close that app or window. Press **Escape** to exit without closing anything.

### Keyboard Mode

Enable **Pure Keyboard Navigation** in Settings for a fully mouse-free workflow.

- Orby always appears **centered on screen**
- **← →** arrow keys cycle focus between apps; the focused app enlarges and pushes neighbors apart
- **Space** activates the focused app (single window) or expands sub-windows (multi-window)
- **1–6** jump directly to neighbor apps: 1, 2, 3 = left neighbors, 4, 5, 6 = right neighbors
- In **sub-window mode**, the same controls (← → Space 1–6) remap to individual windows
- **Escape** goes back one layer: sub-windows → main apps → close Orby

A built-in guide appears automatically the first time you enable Keyboard Mode. You can re-open it from Settings at any time.

### Hold Option to Reveal Names

While Orby is open, hold the **Option** key to instantly display all window titles across every app. Release to hide them.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Option + Tab** | Toggle Orby (default, customizable) |
| **Option + 1–9** | Quick launch bound app/window |
| **Hold Option** | Show all window names |
| **Long Press** | Enter Close Mode |
| **Escape** | Close Orby / Exit Close Mode |
| **Command + ,** | Open Settings |

### Keyboard Mode

| Key | Action |
|-----|--------|
| **← →** | Cycle focus between apps/windows |
| **Space** | Activate app or expand sub-windows |
| **1–6** | Jump to neighbor (1-3 left, 4-6 right) |
| **Escape** | Back one layer / Close Orby |

### Mouse & Trackpad

| Gesture | Action |
|---------|--------|
| **Hover** | Expand app windows / Show preview |
| **Click** | Switch to app or window |
| **Right-click** | Context menu (tag / quick launch) |
| **Long press** | Enter Close Mode |
| **Long press + Drag** (sub-window) | Reorder sub-windows |
| **Pinch** | Zoom window preview |

## Installation

### Download

Download the latest `.dmg` or `.zip` from the [Releases](https://github.com/dxiongya/orby/releases) page.

1. Open `Orby-macOS.dmg`
2. Drag **Orby.app** to your Applications folder
3. Launch Orby

### Build from Source

**Requirements:** macOS 13.0+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
git clone https://github.com/dxiongya/orby.git
cd orby
brew install xcodegen
xcodegen generate
open Orby.xcodeproj
```

Then build and run with **Cmd + R** in Xcode.

## Permissions

Orby requires two macOS permissions on first launch. A built-in guide will walk you through granting them.

| Permission | Purpose |
|-----------|---------|
| **Accessibility** | Global hotkey detection and window management |
| **Screen Recording** | Window preview thumbnails |

Grant them in **System Settings > Privacy & Security**.

## Settings

Access via the menu bar icon > **Settings...** or **Cmd + ,**. Settings are organized into four tabs:

### General
- **Hotkey Bindings** — Add, remove, or re-record hotkey combinations (keyboard or mouse + modifiers)
- **Keyboard Mode** — Enable pure keyboard navigation with built-in usage guide
- **Quick Launch** — View and remove Option + Number bindings

### Apps
- **App Source** — Switch between "Running Apps" (auto-detect) and "Manual Edit" (curated list)
- **Layout Preview** — Visual circular preview of pinned apps; drag to reorder, hover to delete
- **Add Apps** — Search installed applications and pin them to the circle

### Display
- **Window Preview** — Toggle on/off, adjust preview delay
- **Animation Speed** — Separate sliders for main app and sub-window entrance animations (0.5x – 3.0x)
- **Sort Direction** — Choose clockwise or counter-clockwise arrangement for apps and sub-windows

### Tags
- **Tag Presets** — Manage color-coded tag categories

## System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

## Troubleshooting

**Hotkey not responding?**
Check that Accessibility permission is granted in System Settings > Privacy & Security > Accessibility.

**Window previews not showing?**
Ensure Screen Recording permission is granted. You can also toggle previews on in Settings and adjust the delay.

**Some windows missing?**
Windows smaller than 100px are filtered out. Minimized windows are detected but marked accordingly.

**Permission reset needed?**
Use the menu bar > "Open Accessibility Settings..." to jump directly to the settings pane.

## Contributing

Contributions are welcome! Feel free to open issues and pull requests.

## License

[MIT](LICENSE)
