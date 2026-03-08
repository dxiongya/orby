# Changelog

## v0.1.3

### 新增 / New

- **Dock 预览 (Dock Peek)** — 悬停 macOS Dock 图标即可弹出浮动窗口预览面板，灵感来自 DockDoor
  Dock Peek — Hover any Dock icon to see a floating preview panel with window thumbnails, inspired by DockDoor
- **窗口缩略图** — 实时捕获并展示每个窗口的缩略图，已最小化窗口显示遮罩标识
  Live window thumbnails with minimized window overlay indicator
- **红绿灯按钮** — 悬停缩略图时显示关闭/最小化/全屏按钮，操作后预览自动刷新
  Traffic light buttons (close/minimize/fullscreen) on thumbnail hover with auto-refresh
- **点击激活** — 点击缩略图即可激活窗口并自动关闭预览
  Click thumbnail to activate window and dismiss preview
- **Dock 位置适配** — 支持底部、左侧和右侧 Dock 布局
  Supports bottom, left, and right Dock positions

### 改进 / Improvements

- **设置面板重构** — 标签页重新组织：通用→快捷键、显示→外观、标签合并入应用、新增 Dock 预览标签页
  Settings tabs reorganized: General→Shortcuts, Display→Appearance, Tags merged into Apps, new Dock Peek tab
- **无窗口状态** — Dock 预览中无打开窗口的应用显示紧凑的空状态提示
  Compact empty state for apps with no open windows in Dock Peek

### 修正 / Fixes

- **预览消失逻辑** — 修复鼠标离开 Dock 区域后预览面板不消失的问题
  Fixed preview panel not dismissing when mouse leaves dock area
- **瞬间消失修复** — 增加 Grace Period 避免预览刚出现就消失
  Added grace period to prevent premature dismiss after panel shows
- **图标切换闪烁** — 修复在 Dock 图标之间快速移动时的异常闪烁
  Fixed flickering when moving quickly between dock icons
- **面板尺寸** — 使用 SwiftUI fittingSize 消除预览面板右侧多余空白
  Eliminated excess right-side spacing using SwiftUI fittingSize

---

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
