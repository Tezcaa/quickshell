import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

PanelWindow {
    id: launcher

    signal requestClose()

    // Fullscreen overlay so we can dim the background and center the box.
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-launcher"

    // ---- Theme (monochrome) ----
    readonly property color bg:        "#121212"
    readonly property color bgAlt:     "#262626"
    readonly property color accent:    "#3a3a3a"
    readonly property color fg:        "#e6e6e6"
    readonly property color fgDim:     "#8a8a8a"
    readonly property int   rowHeight: 56
    readonly property string fontFamily: "CaskaydiaMono Nerd Font Propo"

    // ---- App data / filtering ----
    property string query: ""

    // Apps to hide from the launcher. Matches (case-insensitive) against either
    // the desktop entry id (e.g. "htop", "org.gnome.Calculator") or the display
    // name (e.g. "Avahi Zeroconf Browser"). Add entries as you like.
    readonly property var hiddenApps: [
        "htop",
        "nvtop",
        "avahi-discover",
        "bssh",
        "bvnc",
        "qv4l2",
        "qvidcap",
        "xterm",
        "uxterm",
        "cmake-gui",
        "lstopo",
        "nautilus-autorun-software",
        "org.freedesktop.Xwayland",
        "org.gnome.Zenity",
        "org.gnupg.pinentry-qt",
        "xdg-desktop-portal-gnome",
        "xdg-desktop-portal-gtk",
        "user-dirs-update-gtk",
    ]

    function isHidden(app) {
        if (!app) return true;
        const id = (app.id || "").toLowerCase();
        const idBase = id.replace(/\.desktop$/, "");
        const name = (app.name || "").toLowerCase();
        for (const h of hiddenApps) {
            const hl = ("" + h).toLowerCase();
            if (id === hl || idBase === hl || name === hl) return true;
        }
        return false;
    }

    readonly property var allApps: {
        const list = DesktopEntries.applications.values
            .filter(a => a && !a.noDisplay && !isHidden(a));
        return list.sort((a, b) => a.name.localeCompare(b.name));
    }

    readonly property bool searching: query.trim() !== ""

    readonly property var filtered: {
        const q = query.trim().toLowerCase();
        if (q === "") return [];
        // rank: startsWith name > word-boundary > substring name (names only)
        const scored = [];
        for (const app of allApps) {
            const name = (app.name || "").toLowerCase();
            let score = -1;
            if (name.startsWith(q)) score = 0;
            else if (name.includes(" " + q)) score = 1;
            else if (name.includes(q)) score = 2;
            if (score >= 0) scored.push({ app, score });
        }
        scored.sort((a, b) => a.score - b.score || a.app.name.localeCompare(b.app.name));
        return scored.map(s => s.app);
    }

    onFilteredChanged: list.currentIndex = filtered.length > 0 ? 0 : -1

    // Terminal used to run apps with Terminal=true (e.g. btop, nvim).
    readonly property string terminal: "ghostty"

    function launch(app) {
        if (!app) return;
        if (app.runInTerminal) {
            // command is the parsed exec argv without field codes.
            const cmd = [launcher.terminal, "-e"].concat(Array.from(app.command));
            Quickshell.execDetached(cmd);
        } else {
            app.execute();
        }
        launcher.requestClose();
    }

    // Transparent full-screen catcher; click outside the box closes.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            onClicked: launcher.requestClose()
        }
    }

    // The launcher box.
    Rectangle {
        id: box
        width: 460
        height: content.implicitHeight + 32
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 200
        radius: 16
        color: launcher.bg
        border.color: launcher.bgAlt
        border.width: 1

        // Swallow clicks so they don't hit the dimmer behind.
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
                color: launcher.bgAlt

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: "\uf002" // fallback shows nothing if no nerd font; harmless
                        visible: false
                    }

                    TextField {
                        id: search
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        focus: true
                        placeholderText: "Search applications…"
                        color: launcher.fg
                        placeholderTextColor: launcher.fgDim
                        font.pixelSize: 18
                        font.family: launcher.fontFamily
                        font.bold: true
                        verticalAlignment: TextInput.AlignVCenter
                        background: null

                        onTextChanged: launcher.query = text

                        Keys.onEscapePressed: launcher.requestClose()
                        Keys.onDownPressed: list.incrementCurrentIndex()
                        Keys.onUpPressed: list.decrementCurrentIndex()
                        Keys.onReturnPressed: launcher.launch(list.currentItem ? list.currentItem.app : null)
                        Keys.onEnterPressed: launcher.launch(list.currentItem ? list.currentItem.app : null)
                    }
                }
            }

            // Results (only while searching)
            ListView {
                id: list
                visible: launcher.searching
                Layout.fillWidth: true
                Layout.preferredHeight: visible
                    ? Math.min(Math.max(contentHeight, launcher.rowHeight), 400)
                    : 0
                clip: true
                model: launcher.filtered
                currentIndex: 0
                keyNavigationWraps: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2

                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property var app: modelData

                    width: ListView.view.width
                    height: launcher.rowHeight
                    radius: 10
                    color: ListView.isCurrentItem ? launcher.accent : "transparent"

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: list.currentIndex = row.index
                        onClicked: launcher.launch(row.app)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 14

                        Item {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36

                            Image {
                                id: iconImg
                                anchors.fill: parent
                                sourceSize.width: 36
                                sourceSize.height: 36
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: false
                                source: Quickshell.iconPath(row.app.icon, "application-x-executable")
                            }

                            MultiEffect {
                                anchors.fill: parent
                                source: iconImg
                                saturation: -1.0
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: row.app.name || ""
                                elide: Text.ElideRight
                                font.pixelSize: 16
                                font.bold: true
                                font.family: launcher.fontFamily
                                color: launcher.fg
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.app.comment || ""
                                elide: Text.ElideRight
                                font.pixelSize: 12
                                font.family: launcher.fontFamily
                                font.bold: true
                                color: launcher.fgDim
                            }
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: "No results"
                    color: launcher.fgDim
                    font.pixelSize: 16
                    font.family: launcher.fontFamily
                    font.bold: true
                }
            }
        }
    }

    // Make sure the text field has focus when shown.
    Component.onCompleted: search.forceActiveFocus()
}
