//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root

    // Whether the launcher is currently shown.
    property bool launcherVisible: false

    // Whether the package menu is currently shown.
    property bool packagesVisible: false

    // Whether the control center is currently shown.
    property bool controlCenterVisible: false

    // Toggle / show / hide the launcher from the CLI:
    //   qs ipc call launcher toggle
    //   qs ipc call launcher show
    //   qs ipc call launcher hide
    IpcHandler {
        target: "launcher"

        function toggle(): void { root.launcherVisible = !root.launcherVisible; }
        function show(): void { root.launcherVisible = true; }
        function hide(): void { root.launcherVisible = false; }
    }

    // Toggle / show / hide the package menu from the CLI:
    //   qs ipc call packages toggle
    IpcHandler {
        target: "packages"

        function toggle(): void { root.packagesVisible = !root.packagesVisible; }
        function show(): void { root.packagesVisible = true; }
        function hide(): void { root.packagesVisible = false; }
    }

    // Toggle / show / hide the control center from the CLI:
    //   qs ipc call controlcenter toggle
    IpcHandler {
        target: "controlcenter"

        function toggle(): void { root.controlCenterVisible = !root.controlCenterVisible; }
        function show(): void { root.controlCenterVisible = true; }
        function hide(): void { root.controlCenterVisible = false; }
    }

    // Only construct the (heavy) launcher window while it is visible.
    LazyLoader {
        active: root.launcherVisible
        component: Launcher {
            onRequestClose: root.launcherVisible = false
        }
    }

    LazyLoader {
        active: root.packagesVisible
        component: PackageMenu {
            onRequestClose: root.packagesVisible = false
        }
    }

    // Keep the control center loaded in the background so its weather is
    // already fetched and it opens instantly. Only its visibility is toggled.
    ControlCenter {
        panelVisible: root.controlCenterVisible
        onRequestClose: root.controlCenterVisible = false
    }

    // Notification popups (replaces mako).
    Notifications {}
}
