# Changelog

## v0.1.2

### 新增 / New

- **最近项目栏** — 浮层底部新增横向滚动条，展示最近使用的应用、文件和文件夹
  Recent Items Bar — A horizontal scroll bar at the bottom showing recently used apps, files, and folders
- **实时应用追踪** — 应用按最近激活时间排序，通过系统通知实时更新
  Real-time app tracking via NSWorkspace notifications
- **Spotlight 文件集成** — 通过 Spotlight 获取最近 7 天的文件和文件夹
  Recent files/folders from the past 7 days via NSMetadataQuery
- **悬停预览** — 底部栏悬停显示应用窗口截图或文件 QuickLook 缩略图
  Hover preview with live window capture (apps) or QuickLook thumbnail (files)
- **无窗口占位提示** — 圆环和底部栏中，后台运行但无可见窗口的应用显示图标 + "无打开窗口"
  No-window placeholder for apps running without visible windows
- **设置开关** — 在 设置 > 显示 > 最近项目 中开关底部栏
  Toggle in Settings > Display > Recent Items

### 修正 / Fixes

- **智能激活** — 点击无可见窗口的应用使用 `open(url)` 触发重新打开，而非 `activate()` 空操作
  Smart activation uses `open(url)` for apps with no visible windows
- **层级修复** — 预览窗口和关闭按钮现在渲染在最近项目栏之上，不再被遮挡
  Window previews render above the recent items bar (z-order fix)
- **本地化应用名** — 添加应用列表使用系统语言名称（中文系统显示"备忘录"而非"Notes"）
  Add Apps list shows system-localized names (e.g. "备忘录" instead of "Notes")
- **系统应用扫描** — 添加应用现在包含系统应用（访达、备忘录、计算器等）
  Add Apps now discovers system apps from `/System/Applications` and `/System/Library/CoreServices`

---

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
