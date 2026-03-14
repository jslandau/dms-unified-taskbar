import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.I3
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginComponent {
    id: root

    layerNamespacePlugin: "unified-taskbar"

    readonly property string screenName: parentScreen?.name ?? ""

    readonly property string effectiveScreenName: {
        if (!SettingsData.workspaceFollowFocus)
            return root.screenName;

        switch (CompositorService.compositor) {
        case "niri":
            return NiriService.currentOutput || root.screenName;
        case "hyprland":
            return Hyprland.focusedWorkspace?.monitor?.name || root.screenName;
        case "dwl":
            return DwlService.activeOutput || root.screenName;
        case "sway":
        case "scroll":
        case "miracle":
            const focusedWs = I3.workspaces?.values?.find(ws => ws.focused === true);
            return focusedWs?.monitor?.name || root.screenName;
        default:
            return root.screenName;
        }
    }

    readonly property bool groupByApp: pluginData.groupByApp ?? false
    readonly property bool compactMode: pluginData.compactMode ?? false
    readonly property bool allMonitors: pluginData.allMonitors ?? false

    readonly property real iconCellSize: widgetThickness - ((barConfig?.removeWidgetPadding ?? false) ? 0 : Theme.snap((barConfig?.widgetPadding ?? 12) * (widgetThickness / 30), 1)) * 2

    property int _desktopEntriesUpdateTrigger: 0
    property int _appIdSubstitutionsTrigger: 0

    function getWorkspaceList() {
        if (CompositorService.isNiri) {
            let workspaces;
            if (root.allMonitors) {
                workspaces = NiriService.allWorkspaces;
            } else if (!root.screenName || SettingsData.workspaceFollowFocus) {
                workspaces = NiriService.getCurrentOutputWorkspaces();
            } else {
                workspaces = NiriService.allWorkspaces.filter(ws => ws.output === root.effectiveScreenName);
            }
            return workspaces.length > 0 ? workspaces : [];
        } else if (CompositorService.isHyprland) {
            return Array.from(Hyprland.workspaces?.values || []).filter(ws => {
                if (ws.id < 0) return false;
                if (!root.allMonitors && root.screenName && ws.monitor?.name !== root.effectiveScreenName) return false;
                return true;
            }).sort((a, b) => a.id - b.id);
        } else if (CompositorService.isDwl) {
            if (!DwlService.dwlAvailable) return [];
            const output = DwlService.getOutputState(root.effectiveScreenName);
            if (!output || !output.tags || output.tags.length === 0) return [];
            if (SettingsData.dwlShowAllTags) {
                return output.tags.map(tag => ({
                    "tag": tag.tag, "state": tag.state,
                    "clients": tag.clients, "focused": tag.focused
                }));
            }
            const visibleTagIndices = DwlService.getVisibleTags(root.effectiveScreenName);
            return visibleTagIndices.map(tagIndex => {
                const tagData = output.tags.find(t => t.tag === tagIndex);
                return {
                    "tag": tagIndex, "state": tagData?.state ?? 0,
                    "clients": tagData?.clients ?? 0, "focused": tagData?.focused ?? false
                };
            });
        } else if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
            const workspaces = I3.workspaces?.values || [];
            return Array.from(workspaces).filter(ws => {
                if (!root.allMonitors && root.screenName && ws.output !== root.effectiveScreenName) return false;
                return true;
            }).sort((a, b) => (a.num ?? 0) - (b.num ?? 0));
        }
        return [];
    }

    function getWindowWorkspaceId(w) {
        if (CompositorService.isNiri) {
            return w.niriWorkspaceId ?? w.workspace_id;
        } else if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
            return w.workspace?.num;
        } else if (CompositorService.isDwl) {
            // DWL doesn't expose per-window tag membership through the Wayland
            // toplevel protocol. WorkspaceSwitcher.qml has the same limitation.
            // groupByWorkspace() handles this with a fallback: tags with
            // clients > 0 show all toplevels.
            return undefined;
        } else if (CompositorService.isHyprland) {
            const hyprlandToplevels = Array.from(Hyprland.toplevels?.values || []);
            const hyprToplevel = hyprlandToplevels.find(ht => ht.wayland === w);
            return hyprToplevel?.workspace?.id;
        }
        return undefined;
    }

    function getWorkspaceId(ws) {
        if (CompositorService.isNiri) {
            return ws.id;
        } else if (CompositorService.isHyprland) {
            return ws.id;
        } else if (CompositorService.isDwl) {
            return ws.tag;
        } else if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
            return ws.num;
        }
        return undefined;
    }

    function isWorkspaceActive(ws) {
        if (CompositorService.isNiri) {
            return ws.is_active === true;
        } else if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
            return ws.focused === true;
        } else if (CompositorService.isDwl) {
            return ws.state === 1;
        } else if (CompositorService.isHyprland) {
            const focusedWs = Hyprland.focusedWorkspace;
            return focusedWs ? (focusedWs.id === ws.id) : false;
        }
        return false;
    }

    function groupByWorkspace() {
        const workspaces = getWorkspaceList();
        const wins = CompositorService.sortedToplevels;
        const result = [];

        for (let i = 0; i < workspaces.length; i++) {
            const ws = workspaces[i];
            const wsId = getWorkspaceId(ws);
            if (wsId === undefined) continue;

            let wsWindows = [];
            if (CompositorService.isDwl) {
                // DWL fallback: no per-window tag matching available.
                // Show all toplevels for tags that have clients > 0.
                // This is the best approximation — matches WorkspaceSwitcher behavior.
                if (ws.clients > 0) {
                    wsWindows = Array.from(wins);
                }
            } else {
                for (let j = 0; j < wins.length; j++) {
                    const w = wins[j];
                    if (!w) continue;
                    const winWsId = getWindowWorkspaceId(w);
                    if (winWsId === wsId) {
                        wsWindows.push(w);
                    }
                }
            }

            if (wsWindows.length === 0) continue;

            const isActive = isWorkspaceActive(ws);

            let entries;
            if (root.groupByApp) {
                const appGroups = new Map();
                wsWindows.forEach((w) => {
                    const moddedId = Paths.moddedAppId(w.appId || "unknown");
                    if (!appGroups.has(moddedId)) {
                        appGroups.set(moddedId, {
                            "isGrouped": true,
                            "appId": moddedId,
                            "windows": [],
                            "toplevel": w
                        });
                    }
                    appGroups.get(moddedId).windows.push(w);
                });
                entries = Array.from(appGroups.values());
            } else {
                entries = wsWindows.map(w => ({
                    "isGrouped": false,
                    "appId": Paths.moddedAppId(w.appId || "unknown"),
                    "windows": [w],
                    "toplevel": w
                }));
            }

            result.push({
                "workspace": ws,
                "workspaceId": wsId,
                "entries": entries,
                "isActive": isActive
            });
        }
        return result;
    }

    function switchToWorkspace(ws) {
        if (!ws) return;
        if (CompositorService.isNiri) {
            NiriService.switchToWorkspace(ws.idx);
        } else if (CompositorService.isHyprland) {
            Hyprland.dispatch(`workspace ${ws.id}`);
        } else if (CompositorService.isDwl) {
            DwlService.setTags(root.effectiveScreenName, 1 << ws.tag, 0);
        } else if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
            I3.dispatch(`workspace number ${ws.num}`);
        }
    }

    readonly property var groupedWorkspaces: {
        CompositorService.toplevelsChanged;
        NiriService.allWorkspaces;
        Hyprland.workspaces;
        I3.workspaces;
        DwlService.stateChanged;
        return groupByWorkspace();
    }

    property var _pendingContextMenu: null

    Loader {
        id: windowContextMenuLoader
        active: false
        onLoaded: {
            if (root._pendingContextMenu && item) {
                item.currentWindow = root._pendingContextMenu.window;
                item.showAt(root._pendingContextMenu.x, root._pendingContextMenu.y, root.isVertical, root.axis?.edge);
                root._pendingContextMenu = null;
            }
        }
        sourceComponent: PanelWindow {
            id: contextMenuWindow

            property var currentWindow: null
            property bool isVisible: false
            property point anchorPos: Qt.point(0, 0)
            property bool isVertical: false
            property string edge: "bottom"

            function showAt(x, y, vertical, barEdge) {
                screen = root.parentScreen;
                anchorPos = Qt.point(x, y);
                isVertical = vertical ?? false;
                edge = barEdge ?? "bottom";
                isVisible = true;
                visible = true;
                if (screen) {
                    TrayMenuManager.registerMenu(screen.name, contextMenuWindow);
                }
            }

            function close() {
                isVisible = false;
                visible = false;
                windowContextMenuLoader.active = false;
                if (screen) {
                    TrayMenuManager.unregisterMenu(screen.name);
                }
            }

            visible: false
            color: "transparent"

            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            Component.onDestruction: {
                if (screen) {
                    TrayMenuManager.unregisterMenu(screen.name);
                }
            }

            Connections {
                target: PopoutManager
                function onPopoutOpening() {
                    contextMenuWindow.close();
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: contextMenuWindow.close()
            }

            Rectangle {
                x: {
                    const left = 10;
                    const right = contextMenuWindow.width - width - 10;
                    const want = contextMenuWindow.anchorPos.x - width / 2;
                    return Math.max(left, Math.min(right, want));
                }
                y: contextMenuWindow.anchorPos.y
                width: 100
                height: 32
                color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
                radius: Theme.cornerRadius
                border.width: 1
                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: ctxCloseMouseArea.containsMouse ? Theme.widgetBaseHoverColor : "transparent"
                }

                StyledText {
                    anchors.centerIn: parent
                    text: I18n.tr("Close")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.widgetTextColor
                }

                MouseArea {
                    id: ctxCloseMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (contextMenuWindow.currentWindow) {
                            contextMenuWindow.currentWindow.close();
                        }
                        contextMenuWindow.close();
                    }
                }
            }
        }
    }

    // Compute the BasePill padding so we can compensate with negative margins
    readonly property real _pillPadding: (barConfig?.removeWidgetPadding ?? false) ? 0 : Theme.snap((barConfig?.widgetPadding ?? 12) * (widgetThickness / 30), 1)

    horizontalBarPill: Component {
        Item {
            // Report narrower implicit width so BasePill's padding fills to edge
            implicitWidth: Math.max(0, hLayout.implicitWidth - root._pillPadding * 2)
            implicitHeight: root.widgetThickness

            Row {
                id: hLayout
                spacing: Theme.spacingXS
                anchors.centerIn: parent

                Repeater {
                    model: ScriptModel {
                        values: root.groupedWorkspaces
                        objectProp: "workspaceId"
                    }

                    delegate: Rectangle {
                        id: wsPill

                        property var wsData: modelData
                        property bool isActive: wsData ? wsData.isActive : false

                        width: innerLayout.implicitWidth + Theme.spacingS * 2
                        height: root.widgetThickness
                        radius: Theme.cornerRadius * 1.5
                        color: "transparent"
                        border.width: isActive ? 2 : 1
                        border.color: isActive ? Theme.primary : Theme.withAlpha(Theme.outline, 0.4)

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            acceptedButtons: Qt.LeftButton
                            onClicked: root.switchToWorkspace(wsPill.wsData ? wsPill.wsData.workspace : null)
                        }

                        Row {
                            id: innerLayout
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            Repeater {
                                model: ScriptModel {
                                    values: wsPill.wsData ? wsPill.wsData.entries : []
                                }

                                delegate: appEntryDelegate
                            }
                        }
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.iconCellSize
            implicitHeight: Math.max(0, vLayout.implicitHeight - root._pillPadding * 2)

            Column {
                id: vLayout
                spacing: Theme.spacingXS
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: ScriptModel {
                        values: root.groupedWorkspaces
                        objectProp: "workspaceId"
                    }

                    delegate: Rectangle {
                        id: wsPillV

                        property var wsData: modelData
                        property bool isActive: wsData ? wsData.isActive : false

                        width: root.iconCellSize
                        height: innerLayoutV.implicitHeight + Theme.spacingS * 2
                        radius: Theme.cornerRadius * 1.5
                        color: "transparent"
                        border.width: isActive ? 2 : 1
                        border.color: isActive ? Theme.primary : Theme.withAlpha(Theme.outline, 0.4)

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            acceptedButtons: Qt.LeftButton
                            onClicked: root.switchToWorkspace(wsPillV.wsData ? wsPillV.wsData.workspace : null)
                        }

                        Column {
                            id: innerLayoutV
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            Repeater {
                                model: ScriptModel {
                                    values: wsPillV.wsData ? wsPillV.wsData.entries : []
                                }

                                delegate: appEntryDelegate
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: appEntryDelegate

        Item {
            id: appEntry

            property var entryData: modelData
            property var toplevelData: entryData ? entryData.toplevel : null
            property bool isGrouped: entryData ? (entryData.isGrouped && entryData.windows.length > 1) : false
            property int windowCount: entryData ? entryData.windows.length : 0
            property string appId: entryData ? entryData.appId : ""
            readonly property string effectiveAppId: appId
            property string windowTitle: toplevelData ? (toplevelData.title || "(Unnamed)") : "(Unnamed)"
            property bool isFocused: {
                if (!entryData) return false;
                for (let i = 0; i < entryData.windows.length; i++) {
                    if (entryData.windows[i].activated || entryData.windows[i].is_focused) return true;
                }
                return false;
            }
            readonly property real entryIconSize: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)

            width: root.compactMode ? entryIconSize + Theme.spacingXS * 2 : entryIconSize + Theme.spacingXS * 3 + 120
            height: Math.round((root.iconCellSize + root.widgetThickness) / 2)

            Rectangle {
                id: entryBackground
                anchors.fill: parent
                radius: Theme.cornerRadius * 1.5
                color: {
                    if (appEntry.isFocused) {
                        return entryMouseArea.containsMouse ? Theme.primarySelected : Theme.withAlpha(Theme.primary, 0.5);
                    }
                    return entryMouseArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.15) : Theme.withAlpha(Theme.surfaceText, 0.07);
                }

                IconImage {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: root.compactMode ? Math.round((parent.width - appEntry.entryIconSize) / 2) : Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    width: appEntry.entryIconSize
                    height: appEntry.entryIconSize
                    source: {
                        root._desktopEntriesUpdateTrigger;
                        root._appIdSubstitutionsTrigger;
                        if (!appEntry.effectiveAppId)
                            return "";
                        const desktopEntry = DesktopEntries.heuristicLookup(appEntry.effectiveAppId);
                        return Paths.getAppIcon(appEntry.effectiveAppId, desktopEntry);
                    }
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    visible: status === Image.Ready
                }

                DankIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: root.compactMode ? Math.round((parent.width - appEntry.entryIconSize) / 2) : Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    size: appEntry.entryIconSize
                    name: "sports_esports"
                    color: Theme.widgetTextColor
                    visible: !appIcon.visible && Paths.isSteamApp(appEntry.effectiveAppId)
                }

                Text {
                    anchors.centerIn: parent
                    visible: !appIcon.visible && !Paths.isSteamApp(appEntry.effectiveAppId)
                    text: {
                        root._desktopEntriesUpdateTrigger;
                        if (!appEntry.effectiveAppId)
                            return "?";
                        const desktopEntry = DesktopEntries.heuristicLookup(appEntry.effectiveAppId);
                        const appName = Paths.getAppName(appEntry.effectiveAppId, desktopEntry);
                        return appName.charAt(0).toUpperCase();
                    }
                    font.pixelSize: 10
                    color: Theme.widgetTextColor
                }

                StyledText {
                    anchors.left: appIcon.right
                    anchors.leftMargin: Theme.spacingXS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.compactMode
                    text: appEntry.windowTitle
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: Theme.widgetTextColor
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: root.compactMode ? -2 : 2
                    anchors.bottomMargin: -2
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.primary
                    visible: appEntry.isGrouped && appEntry.windowCount > 1
                    z: 10

                    StyledText {
                        anchors.centerIn: parent
                        text: appEntry.windowCount > 9 ? "9+" : appEntry.windowCount
                        font.pixelSize: 9
                        color: Theme.surface
                    }
                }

                DankRipple {
                    id: entryRipple
                    cornerRadius: Theme.cornerRadius * 1.5
                }
            }

            MouseArea {
                id: entryMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: mouse => {
                    const pos = mapToItem(entryBackground, mouse.x, mouse.y);
                    entryRipple.trigger(pos.x, pos.y);
                }
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        if (appEntry.isGrouped && appEntry.windowCount > 1) {
                            let currentIndex = -1;
                            for (let i = 0; i < appEntry.entryData.windows.length; i++) {
                                if (appEntry.entryData.windows[i].activated) {
                                    currentIndex = i;
                                    break;
                                }
                            }
                            const nextIndex = (currentIndex + 1) % appEntry.entryData.windows.length;
                            appEntry.entryData.windows[nextIndex].activate();
                        } else if (appEntry.toplevelData) {
                            appEntry.toplevelData.activate();
                        }
                    } else if (mouse.button === Qt.MiddleButton) {
                        if (appEntry.toplevelData) {
                            if (typeof appEntry.toplevelData.close === "function") {
                                appEntry.toplevelData.close();
                            }
                        }
                    } else if (mouse.button === Qt.RightButton) {
                        const toplevel = appEntry.entryData ? appEntry.entryData.toplevel : null;
                        const globalPos = appEntry.mapToGlobal(appEntry.width / 2, 0);
                        const screenX = root.parentScreen ? root.parentScreen.x : 0;
                        const screenY = root.parentScreen ? root.parentScreen.y : 0;
                        let menuX, menuY;
                        if (root.isVertical) {
                            const relativeY = globalPos.y - screenY;
                            menuX = root.axis?.edge === "left"
                                ? (root.barThickness + root.barSpacing + Theme.spacingXS)
                                : (root.parentScreen.width - root.barThickness - root.barSpacing - Theme.spacingXS);
                            menuY = relativeY;
                        } else {
                            const relativeX = globalPos.x - screenX;
                            const screenHeight = root.parentScreen ? root.parentScreen.height : 1080;
                            const isBottom = root.axis?.edge === "bottom";
                            menuX = relativeX;
                            menuY = isBottom
                                ? (screenHeight - root.barThickness - root.barSpacing - 32 - Theme.spacingXS)
                                : (root.barThickness + root.barSpacing + Theme.spacingXS);
                        }
                        root._pendingContextMenu = {
                            "window": toplevel,
                            "x": menuX,
                            "y": menuY
                        };
                        windowContextMenuLoader.active = true;
                    }
                }
            }
        }
    }
}
