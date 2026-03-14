import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "unifiedTaskbar"

    StyledText {
        width: parent.width
        text: "Display"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

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
}
