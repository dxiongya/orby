# Changelog

## v0.1.1

### New: Smart Suggestions Mode

A third App Source mode that learns from your usage habits and automatically suggests the apps you're most likely to need.

- **Usage-based scoring** — Ranks apps by time of day, day of week, frequency, and recency
- **Location context** (optional) — Suggests different apps based on where you are (e.g., work vs. home), using approximate location with no data leaving your Mac
- **30-minute cache** — Suggestions stay stable within a 30-minute window; only running status is refreshed
- **Minimum 6 apps** — Always shows at least 6 apps, filling remaining slots with running apps if needed
- **Cold start fallback** — Shows running apps until enough usage data is collected
- **Privacy-first** — All usage data stored locally in `~/Library/Application Support/Orby/`, never uploaded
- **Clear history** — One-click button in Settings to wipe all usage data and start fresh

### Changes

- App Source picker updated to 3-segment: Running Apps / Manual Edit / Smart
- Close Mode in Smart mode keeps bubbles visible (same behavior as Manual Edit)
- Usage tracking added to all app activation paths (click, keyboard Space, number shortcuts)
- Onboarding guide updated to introduce all three modes
- Added `NSLocationWhenInUseUsageDescription` to Info.plist for optional location feature

---

## v0.0.6

- Animation speed controls (main app & sub-window, 0.5x–3.0x)
- Drag reorder for sub-windows (long-press + drag)
- Performance & security fixes

## v0.0.5

- App Source Modes: Running Apps (auto) and Manual Edit (pinned)
- Settings overhaul with tabbed interface

## v0.0.4

- Sub-app layout and ordering
- Single instance guard
- Version display in menu bar

## v0.0.3

- Keyboard Mode with full arrow/space/number navigation
- Keyboard guide overlay
- Quick Launch symbol input fix

## v0.0.2

- Quick Launch (Option + 1–9)
- App tagging with color-coded labels
- Hold Option to reveal window names

## v0.0.1

- Initial release
- Circular app switcher with adaptive layout
- Window preview with pinch-to-zoom
- Close Mode (long-press to quit apps/windows)
- Menu bar integration
