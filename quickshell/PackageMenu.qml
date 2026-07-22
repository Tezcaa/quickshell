import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

PanelWindow {
    id: menu

    signal requestClose()

    // Fullscreen overlay (transparent) so we can center the box.
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-packages"

    // ---- Theme (monochrome, matches launcher) ----
    readonly property color bg:        "#121212"
    readonly property color bgAlt:     "#262626"
    readonly property color accent:    "#3a3a3a"
    readonly property color fg:        "#e6e6e6"
    readonly property color fgDim:     "#8a8a8a"
    readonly property int   rowHeight: 56
    readonly property string fontFamily: "CaskaydiaMono Nerd Font Propo"

    // Terminal used to run the interactive scripts.
    readonly property string terminal: "ghostty"
    readonly property string scriptDir: Quickshell.env("HOME") + "/Scripts"

    // ---- Actions ----
    property string query: ""

    readonly property var actions: [
        { name: "Install packages", desc: "repos + AUR", script: "installpkg", arg: "all" },
        { name: "Remove packages",  desc: "uninstall",   script: "removepkg",  arg: ""    },
        { name: "Install web app",  desc: "browser app",  script: "webapp-install", arg: "" },
        { name: "Remove web app",   desc: "browser app",  script: "webapp-remove",  arg: "" },
    ]

    readonly property var filtered: {
        const q = query.trim().toLowerCase();
        if (q === "") return actions;
        return actions.filter(a =>
            a.name.toLowerCase().includes(q) || a.desc.toLowerCase().includes(q));
    }

    onFilteredChanged: list.currentIndex = filtered.length > 0 ? 0 : -1

    function run(action) {
        if (!action) return;
        const cmd = [menu.terminal, "--confirm-close-surface=false", "-e", menu.scriptDir + "/" + action.script];
        if (action.arg !== "") cmd.push(action.arg);
        Quickshell.execDetached(cmd);
        menu.requestClose();
    }

    // Transparent full-screen catcher; click outside the box closes.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            onClicked: menu.requestClose()
        }
    }

    // The menu box.
    Rectangle {
        id: box
        width: 460
        height: content.implicitHeight + 32
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 200
        radius: 16
        color: menu.bg
        border.color: menu.bgAlt
        border.width: 1

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 12

            // Search field
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 10
                color: menu.bgAlt

                TextField {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    focus: true
                    placeholderText: "Package manager…"
                    color: menu.fg
                    placeholderTextColor: menu.fgDim
                    font.pixelSize: 18
                    font.family: menu.fontFamily
                    font.bold: true
                    verticalAlignment: TextInput.AlignVCenter
                    background: null

                    onTextChanged: menu.query = text

                    Keys.onEscapePressed: menu.requestClose()
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onReturnPressed: menu.run(list.currentItem ? list.currentItem.action : null)
                    Keys.onEnterPressed: menu.run(list.currentItem ? list.currentItem.action : null)
                }
            }

            // Actions list (always shown)
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 400)
                clip: true
                model: menu.filtered
                currentIndex: 0
                keyNavigationWraps: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2

                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property var action: modelData

                    width: ListView.view.width
                    height: menu.rowHeight
                    radius: 10
                    color: ListView.isCurrentItem ? menu.accent : "transparent"

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: list.currentIndex = row.index
                        onClicked: menu.run(row.action)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: row.action.name
                                elide: Text.ElideRight
                                font.pixelSize: 16
                                font.bold: true
                                font.family: menu.fontFamily
                                color: menu.fg
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.action.desc
                                elide: Text.ElideRight
                                font.pixelSize: 12
                                font.family: menu.fontFamily
                                font.bold: true
                                color: menu.fgDim
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: "No results"
                    color: menu.fgDim
                    font.pixelSize: 16
                    font.family: menu.fontFamily
                    font.bold: true
                }
            }
        }
    }

    Component.onCompleted: search.forceActiveFocus()
}
