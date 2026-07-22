import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // ---- Theme (monochrome, matches the rest) ----
    readonly property color bg:     "#121212"
    readonly property color bgAlt:  "#262626"
    readonly property color fg:     "#e6e6e6"
    readonly property color fgDim:  "#8a8a8a"
    readonly property color errorColor: "#e06c75"
    readonly property string fontFamily: "CaskaydiaMono Nerd Font Propo"

    // Live clock for the lock screen.
    SystemClock {
        id: lockClock
        enabled: true
        precision: SystemClock.Minutes
    }

    // Auth state.
    property string password: ""
    property string statusText: ""
    property bool authenticating: false

    // PAM authentication.
    PamContext {
        id: pam

        onResponseRequiredChanged: {
            if (responseRequired) pam.respond(root.password);
        }

        onCompleted: (result) => {
            root.authenticating = false;
            if (result === PamResult.Success) {
                lock.locked = false; // unlock
            } else {
                root.password = "";
                root.statusText = (result === PamResult.MaxTries)
                    ? "Too many attempts" : "Incorrect password";
            }
        }

        onError: (err) => {
            root.authenticating = false;
            root.password = "";
            root.statusText = "Authentication error";
        }
    }

    function tryUnlock() {
        if (root.authenticating || root.password === "") return;
        root.authenticating = true;
        root.statusText = "";
        pam.start();
    }

    WlSessionLock {
        id: lock
        locked: true

        // Quit the process once unlocked so the lock releases cleanly.
        onLockedChanged: if (!locked) Qt.quit()

        surface: WlSessionLockSurface {
            color: root.bg

            // Wallpaper behind a dim.
            Image {
                anchors.fill: parent
                source: "file://" + Quickshell.env("HOME") + "/Pictures/wallpaper.png"
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                color: "#cc000000"
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                // Big clock.
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(lockClock.date, "hh:mm")
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 140
                    font.bold: true
                }

                // Smaller date.
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(lockClock.date, "dddd, d MMMM yyyy")
                    color: root.fgDim
                    font.family: root.fontFamily
                    font.pixelSize: 24
                    font.bold: true
                }

                // Password input.
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 40
                    width: 360
                    height: 54
                    radius: 12
                    color: root.bgAlt
                    border.color: pwInput.activeFocus ? root.fg : "transparent"
                    border.width: 2

                    TextInput {
                        id: pwInput
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        verticalAlignment: TextInput.AlignVCenter
                        focus: true
                        echoMode: TextInput.Password
                        passwordCharacter: "\u2022"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: 20
                        font.bold: true
                        enabled: !root.authenticating

                        text: root.password
                        onTextChanged: root.password = text

                        Keys.onReturnPressed: root.tryUnlock()
                        Keys.onEnterPressed: root.tryUnlock()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pwInput.text === "" && !root.authenticating
                            text: "Password"
                            color: root.fgDim
                            font.family: root.fontFamily
                            font.pixelSize: 20
                            font.bold: true
                        }
                    }

                    Component.onCompleted: pwInput.forceActiveFocus()
                }

                // Status / error line.
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    text: root.authenticating ? "Authenticating…" : root.statusText
                    color: root.authenticating ? root.fgDim : root.errorColor
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }
            }
        }
    }
}
