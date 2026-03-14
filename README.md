# Unified Taskbar

A [Dank Material Shell](https://danklinux.com) plugin that displays running applications grouped by workspace in pill-shaped containers on the DankBar.

## Features

- Windows organized by workspace in pill-shaped containers
- Multi-compositor support: Niri, Hyprland, Sway, DWL, Scroll, Miracle
- Click workspace pills to switch workspaces
- Click to focus windows, middle-click to close, right-click for context menu
- Optional app grouping with window count badges
- Compact icon-only mode
- Horizontal and vertical bar support

## Settings

| Setting | Description |
|---------|-------------|
| Compact Mode | Show only app icons without window titles |
| Group by App | Collapse multiple windows of the same app into one entry with a count badge |
| Show All Monitors | Show workspaces from all monitors instead of only the current one |

## Installation

### Via DMS Settings

Open settings (Mod + ,) → Plugins → Browse → search "Unified Taskbar"

### Via CLI

```bash
dms plugins install unifiedTaskbar
```

### Manual

```bash
git clone https://github.com/jslandau/dms-unified-taskbar.git \
  ~/.config/DankMaterialShell/plugins/UnifiedTaskbar
dms restart
```

## Requirements

- Dank Material Shell >= 1.2.0

## License

MIT
