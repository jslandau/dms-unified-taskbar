import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "unifiedTaskbar"

    ToggleSetting {
        settingKey: "compactMode"
        label: "Compact Mode"
        description: "Show only app icons without window titles"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "groupByApp"
        label: "Group by App"
        description: "Collapse multiple windows of the same app into one entry with a count badge"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "allMonitors"
        label: "Show All Monitors"
        description: "Show workspaces from all monitors instead of only the current one"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "reverseMonitorOrder"
        label: "Reverse Monitor Order"
        description: "Reverse the order in which monitors are displayed when showing all monitors"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "filledPills"
        label: "Filled Pills (Vertical)"
        description: "Use solid filled workspace pills instead of outlined borders"
        defaultValue: false
    }

    SliderSetting {
        settingKey: "iconPadding"
        label: "Icon Padding"
        minimum: 0
        maximum: 10
        defaultValue: 4
    }

    SliderSetting {
        settingKey: "itemSpacing"
        label: "Item Spacing"
        minimum: 0
        maximum: 10
        defaultValue: 2
    }
}
