import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    // ---- Theme (monochrome, matches the rest) ----
    readonly property color bg:     "#121212"
    readonly property color bgAlt:  "#262626"
    readonly property color bgAlt2: "#1c1c1c"
    readonly property color fg:     "#e6e6e6"
    readonly property color fgDim:  "#8a8a8a"
    readonly property color critical: "#e06c75"
    readonly property string fontFamily: "CaskaydiaMono Nerd Font Propo"

    readonly property int defaultTimeout: 5000 // ms for popups without a timeout

    // Active popups shown on screen.
    property var popups: []

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionIconsSupported: false

        onNotification: (notif) => {
            // Keep the notification alive so we can render + act on it.
            notif.tracked = true;
            const arr = root.popups.slice();
            arr.push(notif);
            root.popups = arr;
        }
    }

    function dismiss(notif) {
        const arr = root.popups.filter(n => n !== notif);
        root.popups = arr;
        if (notif) notif.dismiss();
    }

    // Top-right stack of toast windows.
    PanelWindow {
        id: layerWindow
        visible: root.popups.length > 0

        anchors { top: true; right: true }
        margins { top: 12; right: 12 }
        implicitWidth: 380
        implicitHeight: Math.max(1, column.implicitHeight)
        exclusiveZone: 0
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        ColumnLayout {
            id: column
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.left: parent.left
            spacing: 10

            Repeater {
                model: root.popups

                Rectangle {
                    id: toast
                    required property var modelData
                    readonly property var notif: modelData

                    Layout.fillWidth: true
                    implicitHeight: toastCol.implicitHeight + 28
                    radius: 14
                    color: root.bg
                    border.width: 2
                    border.color: notif && notif.urgency === NotificationUrgency.Critical
                        ? root.critical : root.bgAlt

                    // Auto-dismiss timer.
                    Timer {
                        running: true
                        interval: {
                            if (!toast.notif) return root.defaultTimeout;
                            const t = toast.notif.expireTimeout;
                            if (t < 0) return root.defaultTimeout;   // -1 = server default
                            if (t === 0) return 0;                    // 0 = never expire
                            return t;
                        }
                        repeat: false
                        onTriggered: if (interval > 0) root.dismiss(toast.notif)
                    }

                    // Click anywhere (except buttons) dismisses.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: root.dismiss(toast.notif)
                    }

                    ColumnLayout {
                        id: toastCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8

                        // Header: app name + close.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: (toast.notif && toast.notif.appName) ? toast.notif.appName : "Notification"
                                color: root.fgDim
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                text: "\uf00d" // close x
                                color: root.fgDim
                                font.family: root.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onClicked: root.dismiss(toast.notif)
                                }
                            }
                        }

                        // Body row: optional image + text.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Image {
                                visible: source != ""
                                Layout.preferredWidth: 48
                                Layout.preferredHeight: 48
                                Layout.alignment: Qt.AlignTop
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                source: {
                                    if (!toast.notif) return "";
                                    if (toast.notif.image) return toast.notif.image;
                                    if (toast.notif.appIcon) return Quickshell.iconPath(toast.notif.appIcon, "");
                                    return "";
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: (toast.notif && toast.notif.summary) ? toast.notif.summary : ""
                                    color: root.fg
                                    elide: Text.ElideRight
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    font.family: root.fontFamily
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: (toast.notif && toast.notif.body) ? toast.notif.body : ""
                                    color: root.fgDim
                                    textFormat: Text.MarkdownText
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 6
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                            }
                        }

                        // Action buttons.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 8
                            visible: toast.notif && toast.notif.actions.length > 0

                            Repeater {
                                model: toast.notif ? toast.notif.actions : []

                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: 8
                                    color: root.bgAlt

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.text
                                        color: root.fg
                                        elide: Text.ElideRight
                                        font.family: root.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            modelData.invoke();
                                            root.dismiss(toast.notif);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
