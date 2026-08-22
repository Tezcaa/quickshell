import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: cc

    signal requestClose()

    // Whether the panel is shown. When false the window is hidden but the
    // component stays loaded (weather already fetched) so it appears instantly.
    property bool panelVisible: true

    // Re-check status each time the panel is opened.
    onPanelVisibleChanged: if (panelVisible) { refreshUpdates(); refreshRate(); refreshMouseBattery(); refreshSysres(); }

    visible: panelVisible

    // Fullscreen transparent overlay so click-outside closes.
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: panelVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-controlcenter"

    // ---- Theme (monochrome, matches launcher) ----
    readonly property color bg:        "#121212"
    readonly property color bgAlt:     "#262626"
    readonly property color bgAlt2:    "#1c1c1c"
    readonly property color accent:    "#3a3a3a"
    readonly property color fg:        "#e6e6e6"
    readonly property color fgDim:     "#8a8a8a"
    readonly property color critical:  "#e06c75"
    readonly property string fontFamily: "CaskaydiaMono Nerd Font Propo"

    // Live clock.
    SystemClock {
        id: clock
        enabled: true
        precision: SystemClock.Seconds
    }

    // ---- Media (MPRIS) ----
    // Control any MPRIS-compatible player, but ignore browser players.
    // Prefer one that is currently playing, otherwise fall back to the first
    // available real player.
    function isBrowserPlayer(dbus, ident) {
        const browsers = [
            "chromium", "chrome", "firefox", "brave", "edge", "opera",
            "vivaldi", "qutebrowser", "waterfox", "librewolf", "zen"
        ];
        const name = (dbus + " " + ident).toLowerCase();
        for (const b of browsers) {
            if (name.indexOf(b) >= 0) return true;
        }
        return false;
    }

    readonly property var mediaPlayer: {
        const list = Mpris.players.values;
        if (!list || list.length === 0) return null;
        for (const p of list) {
            if (!p) continue;
            const dbus = ("" + (p.dbusName || "")).toLowerCase();
            const ident = ("" + (p.identity || "")).toLowerCase();
            if (isBrowserPlayer(dbus, ident)) continue;
            if (p.isPlaying) return p;
        }
        for (const p of list) {
            if (!p) continue;
            const dbus = ("" + (p.dbusName || "")).toLowerCase();
            const ident = ("" + (p.identity || "")).toLowerCase();
            if (isBrowserPlayer(dbus, ident)) continue;
            return p;
        }
        return null;
    }
    readonly property bool hasMedia: mediaPlayer !== null

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0) return "--:--";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    // Polled position/length because MPRIS players do not continuously signal
    // position changes. The seek itself still works via the player API.
    property real currentPosition: 0
    property real currentLength: 0

    Timer {
        id: positionTimer
        interval: 500
        running: cc.hasMedia && cc.mediaPlayer.positionSupported
        repeat: true
        onTriggered: {
            if (cc.hasMedia) {
                cc.currentPosition = cc.mediaPlayer.position;
                cc.currentLength = cc.mediaPlayer.length;
            } else {
                cc.currentPosition = 0;
                cc.currentLength = 0;
            }
        }
    }

    // ---- Audio (Pipewire) ----
    readonly property var audioSink: Pipewire.defaultAudioSink

    // Keep the default sink's audio data (volume/mute) live.
    PwObjectTracker {
        objects: {
            const list = [];
            if (cc.audioSink) list.push(cc.audioSink);
            return list;
        }
    }

    // ---- Audio sample rate ----
    readonly property var sampleRates: [0, 44100, 48000, 96000, 192000]
    property int sampleRate: 0
    property bool sampleRateForced: false

    function rateLabel(rate) {
        if (rate === 0) return "Auto";
        return (rate / 1000).toFixed(1).replace(/\.0$/, "") + "k";
    }

    function setRate(rate) {
        const arg = rate === 0 ? "auto" : ("" + rate);
        Quickshell.execDetached([Quickshell.env("HOME") + "/Scripts/samplerate", arg]);
        rateRefreshTimer.restart();
    }

    Process {
        id: rateProc
        command: [Quickshell.env("HOME") + "/Scripts/samplerate", "status"]
        stdout: StdioCollector {
            id: rateOut
            onStreamFinished: {
                // Output: "<forced 0|1> <effective rate>"
                const parts = ("" + rateOut.text).trim().split(/\s+/);
                cc.sampleRateForced = parts[0] === "1";
                const n = parseInt(parts[1]);
                cc.sampleRate = isNaN(n) ? 0 : n;
            }
        }
    }

    function refreshRate() { if (!rateProc.running) rateProc.running = true; }

    Timer {
        id: rateRefreshTimer
        interval: 500
        repeat: false
        onTriggered: cc.refreshRate()
    }

    // Current date parts (derived from the live clock).
    readonly property int curYear:  parseInt(Qt.formatDateTime(clock.date, "yyyy"))
    readonly property int curMonth: parseInt(Qt.formatDateTime(clock.date, "M")) - 1
    readonly property int curDay:   parseInt(Qt.formatDateTime(clock.date, "d"))

    // Calendar view state (month currently shown).
    property int viewYear:  curYear
    property int viewMonth: curMonth

    function shiftMonth(delta) {
        let m = viewMonth + delta;
        let y = viewYear;
        while (m < 0)  { m += 12; y -= 1; }
        while (m > 11) { m -= 12; y += 1; }
        viewMonth = m;
        viewYear = y;
    }

    // Build a 6x7 grid of day numbers (0 = blank) for a given month.
    function monthCells(year, month) {
        const first = new Date(year, month, 1);
        const startDay = (first.getDay() + 6) % 7; // Monday = 0
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const cells = [];
        for (let i = 0; i < startDay; i++) cells.push(0);
        for (let d = 1; d <= daysInMonth; d++) cells.push(d);
        while (cells.length < 42) cells.push(0);
        return cells;
    }

    // ---- Weather (ARSO - vreme.arso.gov.si) ----
    property string wxTemp: ""
    property string wxHumidity: ""
    property string wxDesc: "Loading…"
    property string wxIcon: ""
    property string wxLoc: ""
    property bool   wxError: false
    property var    wxForecast: []
    property var    wxHourly: []
    property bool   showForecast: false

    // ARSO location to query.
    readonly property string wxLocation: "Idrija"

    // Translate ARSO Slovenian condition text to English.
    function siToEn(s) {
        if (!s) return "";
        const map = {
            "jasno": "Clear",
            "pretežno jasno": "Clear",
            "delno oblačno": "Cloudy",
            "zmerno oblačno": "Cloudy",
            "pretežno oblačno": "Cloudy",
            "oblačno": "Overcast",
            "megla": "Fog",
            "dež": "Rain",
            "plohe": "Showers",
            "možnost neviht": "Storms",
            "nevihte": "Storms",
            "sneg": "Snow",
            "sneženje": "Snow",
            "dežuje": "Rain",
        };
        const key = ("" + s).toLowerCase().trim();
        return map[key] || (s.charAt(0).toUpperCase() + s.slice(1));
    }

    // Decode ARSO's combined icon string (e.g. "overcast_lightTSRA_night")
    // which encodes both cloud cover AND precipitation, into English text.
    // Falls back to the plain cloud text when there's no precipitation part.
    function decodeCondition(iconStr, cloudsText) {
        const cloud = cc.siToEn(cloudsText);
        if (!iconStr) return cloud;

        // Strip the day/night suffix and the cloud-cover prefix.
        let s = ("" + iconStr).replace(/_(day|night)$/i, "");
        // Known cloud prefixes in ARSO icon names.
        const prefixes = ["clear", "partCloudy", "prevCloudy", "modCloudy", "overcast"];
        for (const p of prefixes) {
            if (s.toLowerCase().startsWith(p.toLowerCase())) {
                s = s.slice(p.length);
                break;
            }
        }
        s = s.replace(/^_/, ""); // remaining weather token, e.g. "lightTSRA"
        if (s === "") return cloud;

        // Intensity prefix.
        let intensity = "";
        const lower = s.toLowerCase();
        if (lower.startsWith("light")) { intensity = "Light "; s = s.slice(5); }
        else if (lower.startsWith("mod")) { intensity = ""; s = s.slice(3); }
        else if (lower.startsWith("heavy")) { intensity = "Heavy "; s = s.slice(5); }

        // Phenomenon codes (order matters: check compound codes first).
        const code = s.toUpperCase();
        let phenom = "";
        if (code.indexOf("TSRA") >= 0) phenom = "storm";
        else if (code.indexOf("TS") >= 0) phenom = "storm";
        else if (code.indexOf("RASN") >= 0) phenom = "sleet";
        else if (code.indexOf("SHRA") >= 0) phenom = "showers";
        else if (code.indexOf("RA") >= 0) phenom = "rain";
        else if (code.indexOf("SN") >= 0) phenom = "snow";
        else if (code.indexOf("SHSN") >= 0) phenom = "snow";
        else if (code.indexOf("FG") >= 0) return "Fog";
        else if (code.indexOf("DZ") >= 0) phenom = "drizzle";
        else return cloud;

        // Show only the precipitation, e.g. "Light rain".
        const label = intensity + phenom;
        return label.charAt(0).toUpperCase() + label.slice(1);
    }

    // Map ARSO's combined icon string to a Nerd Font weather glyph.
    // Precipitation takes priority; otherwise cloud cover (day/night aware).
    function conditionIcon(iconStr) {
        if (!iconStr) return "\ue374"; // wi-na
        const s = ("" + iconStr).toLowerCase();
        const night = s.indexOf("night") >= 0;

        // Precipitation (highest priority).
        if (s.indexOf("tsra") >= 0 || s.indexOf("ts") >= 0) return "\ue31d"; // thunderstorm
        if (s.indexOf("rasn") >= 0) return "\ue3ad"; // sleet
        if (s.indexOf("shra") >= 0) return "\ue319"; // showers
        if (s.indexOf("ra") >= 0)   return "\ue318"; // rain
        if (s.indexOf("sn") >= 0)   return "\ue31a"; // snow
        if (s.indexOf("dz") >= 0)   return "\ue319"; // drizzle -> showers
        if (s.indexOf("fg") >= 0)   return "\ue313"; // fog

        // Cloud cover.
        if (s.indexOf("overcast") >= 0)  return "\ue312"; // cloudy
        if (s.indexOf("prevcloudy") >= 0) return night ? "\ue37e" : "\ue302"; // mostly cloudy
        if (s.indexOf("modcloudy") >= 0)  return night ? "\ue37e" : "\ue302";
        if (s.indexOf("partcloudy") >= 0) return night ? "\ue37e" : "\ue302"; // partly cloudy
        if (s.indexOf("clear") >= 0)      return night ? "\ue32b" : "\ue30d"; // moon / sun

        return "\ue374";
    }

    Process {
        id: weatherProc
        command: ["curl", "-s", "--max-time", "12",
            "https://vreme.arso.gov.si/api/1.0/location/?location=" + cc.wxLocation]
        stdout: StdioCollector {
            id: weatherOut
            onStreamFinished: {
                try {
                    const data = JSON.parse(weatherOut.text);
                    cc.wxLoc = cc.wxLocation;

                    // Current conditions from the latest observation.
                    const obsFeat = data.observation.features[0].properties;
                    const obs = obsFeat.days[0].timeline[obsFeat.days[0].timeline.length - 1];
                    cc.wxTemp = obs.t;
                    cc.wxHumidity = obs.rh;
                    cc.wxDesc = cc.decodeCondition(obs.clouds_icon_wwsyn_icon, obs.clouds_shortText);
                    cc.wxIcon = cc.conditionIcon(obs.clouds_icon_wwsyn_icon);

                    // Daily forecast (min/max) from forecast24h.
                    const f24 = data.forecast24h.features[0].properties;
                    const days = [];
                    for (const d of f24.days.slice(0, 8)) {
                        const tl = d.timeline[0];
                        days.push({
                            day: Qt.formatDateTime(new Date(d.date), "ddd"),
                            date: Qt.formatDateTime(new Date(d.date), "d MMM"),
                            max: tl.txsyn || "",
                            min: tl.tnsyn || "",
                            desc: cc.decodeCondition(tl.clouds_icon_wwsyn_icon, tl.clouds_shortText),
                            icon: cc.conditionIcon(tl.clouds_icon_wwsyn_icon)
                        });
                    }
                    cc.wxForecast = days;

                    // Hourly forecast (next hours) from forecast1h.
                    const f1 = data.forecast1h.features[0].properties;
                    const hours = [];
                    for (const d of f1.days) {
                        for (const tl of d.timeline) {
                            hours.push({
                                hour: Qt.formatDateTime(new Date(tl.valid), "HH:mm"),
                                temp: tl.t || "",
                                desc: cc.decodeCondition(tl.clouds_icon_wwsyn_icon, tl.clouds_shortText),
                                icon: cc.conditionIcon(tl.clouds_icon_wwsyn_icon)
                            });
                            if (hours.length >= 12) break;
                        }
                        if (hours.length >= 12) break;
                    }
                    cc.wxHourly = hours;

                    cc.wxError = false;
                } catch (e) {
                    cc.wxError = true;
                    cc.wxDesc = "Unavailable";
                }
            }
        }
    }

    function refreshWeather() { weatherProc.running = true; }

    Component.onCompleted: { refreshWeather(); refreshUpdates(); refreshRate(); refreshSysres(); }

    // Refresh weather every 15 minutes while open.
    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        onTriggered: cc.refreshWeather()
    }

    // ---- Available updates ----
    readonly property string scriptDir: Quickshell.env("HOME") + "/Scripts"
    property int updateCount: 0
    property bool checkingUpdates: false
    property bool rebootNeeded: false

    Process {
        id: updateProc
        command: [cc.scriptDir + "/update-count"]
        stdout: StdioCollector {
            id: updateOut
            onStreamFinished: {
                const n = parseInt(("" + updateOut.text).trim());
                cc.updateCount = isNaN(n) ? 0 : n;
                cc.checkingUpdates = false;
            }
        }
    }

    Process {
        id: rebootProc
        command: [cc.scriptDir + "/reboot-needed"]
        stdout: StdioCollector {
            id: rebootOut
            onStreamFinished: {
                cc.rebootNeeded = ("" + rebootOut.text).trim() === "1";
            }
        }
    }

    function refreshUpdates() {
        if (!updateProc.running) {
            cc.checkingUpdates = true;
            updateProc.running = true;
        }
        if (!rebootProc.running) rebootProc.running = true;
    }

    // ---- Mouse battery (Logitech PRO X 2 via Solaar) ----
    property int mouseBatteryPct: -1

    Process {
        id: solaarBatteryProc
        command: [cc.scriptDir + "/solaar-mouse-battery"]
        stdout: StdioCollector {
            id: solaarBatteryOut
            onStreamFinished: {
                const raw = ("" + solaarBatteryOut.text).trim();
                if (raw === "N/A") {
                    cc.mouseBatteryPct = -1;
                    return;
                }
                const n = parseInt(raw);
                cc.mouseBatteryPct = (isNaN(n) || n < 0 || n > 100) ? -1 : n;
            }
        }
    }

    function refreshMouseBattery() {
        if (!solaarBatteryProc.running) solaarBatteryProc.running = true;
    }

    function mouseBatteryIcon() {
        const pct = cc.mouseBatteryPct;
        if (pct < 0) return "\uf244"; // unknown -> empty
        if (pct <= 10) return "\uf244"; // battery-empty
        if (pct <= 35) return "\uf243"; // battery-quarter
        if (pct <= 60) return "\uf242"; // battery-half
        if (pct <= 85) return "\uf241"; // battery-three-quarters
        return "\uf240"; // battery-full
    }

    function runUpdate() {
        Quickshell.execDetached(["ghostty", "--confirm-close-surface=false",
            "-e", cc.scriptDir + "/update-all"]);
        cc.requestClose();
    }

    // ---- Power actions ----
    function powerReboot()   { Quickshell.execDetached(["systemctl", "reboot"]); }
    function powerShutdown() { Quickshell.execDetached(["systemctl", "poweroff"]); }
    function powerLogout()   { Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"]); }

    // ---- System resources ----
    property real cpuPercent: 0
    property real ramPercent: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real gpuPercent: 0

    Process {
        id: sysresProc
        command: [cc.scriptDir + "/sysres"]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = "" + sysresProc.stdout.text;
                for (const line of txt.split('\n')) {
                    const parts = line.split(':');
                    if (parts.length < 2) continue;
                    const key = parts[0];
                    const val = parseFloat(parts[1]);
                    if (isNaN(val)) continue;
                    switch (key) {
                        case "cpu": cc.cpuPercent = val; break;
                        case "ram":
                            cc.ramPercent = val;
                            cc.ramUsedGb = parseFloat(parts[2]) || 0;
                            cc.ramTotalGb = parseFloat(parts[3]) || 0;
                            break;
                        case "gpu": cc.gpuPercent = val; break;
                    }
                }
            }
        }
    }

    function refreshSysres() { if (!sysresProc.running) sysresProc.running = true; }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: cc.refreshSysres()
    }

    // ---- Calculator ----
    property string calcDisplay: "0"
    property real calcPrevious: 0
    property string calcOperator: ""
    property bool calcComputedResult: false

    function calcPress(key) {
        if (key === "C") {
            cc.calcDisplay = "0";
            cc.calcPrevious = 0;
            cc.calcOperator = "";
            cc.calcComputedResult = false;
            return;
        }
        if (key === "=") {
            cc.calcCompute(true);
            return;
        }
        if (["+", "-", "*", "/"].indexOf(key) >= 0) {
            if (cc.calcOperator !== "" && !cc.calcComputedResult) {
                cc.calcCompute(false);
            }
            cc.calcPrevious = parseFloat(cc.calcDisplay) || 0;
            cc.calcDisplay = "0";
            cc.calcOperator = key;
            cc.calcComputedResult = false;
            calcInput.selectAll();
            return;
        }
    }

    function calcCompute(final) {
        const current = parseFloat(cc.calcDisplay) || 0;
        let result = 0;
        switch (cc.calcOperator) {
            case "+": result = cc.calcPrevious + current; break;
            case "-": result = cc.calcPrevious - current; break;
            case "*": result = cc.calcPrevious * current; break;
            case "/": result = current === 0 ? 0 : cc.calcPrevious / current; break;
            default: result = current;
        }
        cc.calcDisplay = "" + result;
        cc.calcPrevious = result;
        if (final) cc.calcOperator = "";
        cc.calcComputedResult = true;
        calcInput.selectAll();
    }

    function calcTyping() {
        if (cc.calcComputedResult) {
            cc.calcComputedResult = false;
            cc.calcDisplay = calcInput.text === "" ? "0" : calcInput.text;
        } else {
            cc.calcDisplay = calcInput.text;
        }
    }

    // Re-check for updates every 30 minutes.
    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        onTriggered: cc.refreshUpdates()
    }

    // Refresh mouse battery every 60 seconds.
    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        onTriggered: cc.refreshMouseBattery()
    }

    // Close on Escape.
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: cc.requestClose()
    }

    // Click-outside catcher.
    MouseArea {
        anchors.fill: parent
        onClicked: cc.requestClose()
    }

    // The panel, anchored to the top-center.
    Rectangle {
        id: panel
        width: mainRow.implicitWidth + 52
        height: mainRow.implicitHeight + 52
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 12
        radius: 16
        color: cc.bg
        border.color: cc.bgAlt
        border.width: 1

        MouseArea { anchors.fill: parent }

        RowLayout {
            id: mainRow
            anchors.fill: parent
            anchors.margins: 26
            spacing: 20

            ColumnLayout {
                id: content
                Layout.preferredWidth: 460
                spacing: 20

            // ---- Clock widget ----
            Rectangle {
                id: clockRect
                Layout.fillWidth: true
                implicitHeight: clockCol.implicitHeight + 32
                radius: 12
                color: cc.bgAlt

                ColumnLayout {
                    id: clockCol
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(clock.date, "hh:mm:ss")
                        color: cc.fg
                        font.family: cc.fontFamily
                        font.pixelSize: 52
                        font.bold: true
                    }
                }
            }

            // ---- Calendar widget ----
            Rectangle {
                id: calendarRect
                Layout.fillWidth: true
                implicitHeight: calCol.implicitHeight + 24
                radius: 12
                color: cc.bgAlt

                ColumnLayout {
                    id: calCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 10

                    // Month header with navigation.
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "\u2039"
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 24
                            font.bold: true
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                onClicked: cc.shiftMonth(-1)
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: Qt.formatDateTime(new Date(cc.viewYear, cc.viewMonth, 1), "MMMM yyyy")
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 18
                            font.bold: true
                        }

                        Text {
                            text: "\uf111" // small dot / today
                            visible: cc.viewYear !== cc.curYear || cc.viewMonth !== cc.curMonth
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 12
                            font.bold: true
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                onClicked: {
                                    cc.viewYear = cc.curYear;
                                    cc.viewMonth = cc.curMonth;
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "\u203a"
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 24
                            font.bold: true
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                onClicked: cc.shiftMonth(1)
                            }
                        }
                    }

                    // Weekday headers.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 7
                        columnSpacing: 0
                        rowSpacing: 0

                        Repeater {
                            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                color: cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }
                    }

                    // Day cells.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 7
                        columnSpacing: 0
                        rowSpacing: 3

                        Repeater {
                            model: cc.monthCells(cc.viewYear, cc.viewMonth)

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 32

                                readonly property bool isToday:
                                    modelData === cc.curDay
                                    && cc.viewMonth === cc.curMonth
                                    && cc.viewYear === cc.curYear

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 30
                                    height: 30
                                    radius: 15
                                    visible: parent.isToday
                                    color: cc.fg
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: modelData > 0
                                    text: modelData > 0 ? modelData : ""
                                    color: parent.isToday ? cc.bg : cc.fg
                                    font.family: cc.fontFamily
                                    font.pixelSize: 16
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
            }

            // ---- Weather widget ----
            Rectangle {
                id: weatherRect
                Layout.fillWidth: true
                implicitHeight: wxCol.implicitHeight + 24
                radius: 12
                color: cc.bgAlt

                MouseArea {
                    anchors.fill: parent
                    onClicked: cc.showForecast = !cc.showForecast
                }

                ColumnLayout {
                    id: wxCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Weather"
                            color: cc.fgDim
                            font.family: cc.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: cc.wxLoc
                            color: cc.fgDim
                            font.family: cc.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }

                    // Current conditions (always visible).
                    Text {
                        Layout.fillWidth: true
                        text: cc.wxTemp !== "" ? cc.wxTemp + "\u00b0C" : "--"
                        color: cc.fg
                        font.family: cc.fontFamily
                        font.pixelSize: 42
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: cc.wxIcon
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 34
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: cc.wxDesc
                            color: cc.fg
                            elide: Text.ElideRight
                            font.family: cc.fontFamily
                            font.pixelSize: 18
                            font.bold: true
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !cc.wxError && cc.wxHumidity !== ""
                        text: "Humidity " + cc.wxHumidity + "%"
                        color: cc.fgDim
                        font.family: cc.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    // Hourly forecast boxes (current view only).
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 282
                        Layout.topMargin: 8
                        color: "transparent"
                        visible: !cc.showForecast && cc.wxHourly.length > 0

                        GridLayout {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            columns: 4
                            columnSpacing: 6
                            rowSpacing: 6

                            Repeater {
                                model: !cc.showForecast ? cc.wxHourly : []

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 90
                                    Layout.minimumHeight: 90
                                    Layout.maximumHeight: 90
                                    radius: 10
                                    color: cc.bgAlt2

                                    ColumnLayout {
                                        id: hourCol
                                        anchors.centerIn: parent
                                        width: parent.width - 10
                                        spacing: 3

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.hour
                                            color: cc.fgDim
                                            font.family: cc.fontFamily
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.temp + "\u00b0"
                                            color: cc.fg
                                            font.family: cc.fontFamily
                                            font.pixelSize: 19
                                            font.bold: true
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.icon
                                            color: cc.fgDim
                                            font.family: cc.fontFamily
                                            font.pixelSize: 28
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Forecast boxes (grid of day cards).
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 282
                        Layout.topMargin: 8
                        color: "transparent"
                        visible: cc.showForecast

                        GridLayout {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            columns: 4
                            columnSpacing: 6
                            rowSpacing: 6

                            Repeater {
                                model: cc.showForecast ? cc.wxForecast : []

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 90
                                    Layout.minimumHeight: 90
                                    Layout.maximumHeight: 90
                                    radius: 10
                                    color: cc.bgAlt2

                                    ColumnLayout {
                                        id: dayCol
                                        anchors.centerIn: parent
                                        width: parent.width - 10
                                        spacing: 3

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.day
                                            color: cc.fg
                                            font.family: cc.fontFamily
                                            font.pixelSize: 16
                                            font.bold: true
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.icon
                                            color: cc.fgDim
                                            font.family: cc.fontFamily
                                            font.pixelSize: 30
                                            font.bold: true
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.max + "\u00b0/" + modelData.min + "\u00b0"
                                            color: cc.fg
                                            font.family: cc.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Hint.
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        text: cc.showForecast ? "click for hourly" : "click for 8-day"
                        color: cc.fgDim
                        horizontalAlignment: Text.AlignHCenter
                        font.family: cc.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }
            }

            // ---- Media control column (right side) ----
            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.preferredHeight: clockRect.height + content.spacing + calendarRect.height + content.spacing + weatherRect.height
                Layout.minimumHeight: Layout.preferredHeight
                Layout.maximumHeight: Layout.preferredHeight
                spacing: 16

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: clockRect.height + content.spacing + calendarRect.height
                    radius: 12
                    color: cc.bgAlt

                    // Empty state.
                    Text {
                        anchors.centerIn: parent
                        visible: !cc.hasMedia
                        text: "No media player"
                        color: cc.fgDim
                        font.family: cc.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    ColumnLayout {
                        id: mediaCol
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12
                        visible: cc.hasMedia

                        Text {
                            text: "Now Playing"
                            color: cc.fgDim
                            font.family: cc.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                        }

                        // Album art.
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 140
                            Layout.preferredHeight: 140
                            radius: 10
                            color: cc.bgAlt2
                            clip: true

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                source: cc.hasMedia && cc.mediaPlayer.trackArtUrl
                                    ? cc.mediaPlayer.trackArtUrl : ""
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !cc.hasMedia || !cc.mediaPlayer.trackArtUrl
                                text: "\uf001" // music note (nerd font)
                                color: cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 36
                                font.bold: true
                            }
                        }

                        // Title.
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: cc.hasMedia ? (cc.mediaPlayer.trackTitle || "Unknown") : ""
                            color: cc.fg
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            font.family: cc.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                        }

                        // Artist.
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: cc.hasMedia ? (cc.mediaPlayer.trackArtist || "") : ""
                            color: cc.fgDim
                            elide: Text.ElideRight
                            font.family: cc.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                        }

                        // Spacer pushes the progress bar and controls to the bottom.
                        Item { Layout.fillWidth: true; Layout.fillHeight: true }

                        // Progress bar.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: cc.hasMedia && cc.mediaPlayer.positionSupported ? cc.formatTime(cc.currentPosition) : "--:--"
                                color: cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 10
                                radius: 5
                                color: cc.bgAlt2

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    radius: 5
                                    color: cc.fg
                                    width: {
                                        if (!cc.hasMedia || !cc.mediaPlayer.positionSupported || !cc.mediaPlayer.lengthSupported || cc.currentLength <= 0) return 0;
                                        const pos = progressSlider.dragging ? progressSlider.seekPos : (cc.currentPosition / cc.currentLength);
                                        return Math.max(0, Math.min(1, pos)) * parent.width;
                                    }
                                }

                                MouseArea {
                                    id: progressSlider
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    property real seekPos: 0
                                    property bool dragging: false
                                    enabled: cc.hasMedia && cc.mediaPlayer.positionSupported && cc.mediaPlayer.lengthSupported && cc.currentLength > 0 && cc.mediaPlayer.canSeek
                                    onPressed: (mouse) => { dragging = true; updateSeek(mouse.x); }
                                    onPositionChanged: (mouse) => { if (dragging) updateSeek(mouse.x); }
                                    onReleased: (mouse) => {
                                        if (dragging) {
                                            updateSeek(mouse.x);
                                            if (cc.hasMedia && cc.currentLength > 0) {
                                                const target = seekPos * cc.currentLength;
                                                cc.mediaPlayer.seek(target - cc.currentPosition);
                                            }
                                            dragging = false;
                                        }
                                    }
                                    function updateSeek(x) {
                                        seekPos = Math.max(0, Math.min(1, x / width));
                                    }
                                }
                            }

                            Text {
                                text: cc.hasMedia && cc.mediaPlayer.lengthSupported ? cc.formatTime(cc.currentLength) : "--:--"
                                color: cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        // Controls.
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.bottomMargin: 6
                            spacing: 20

                            Text {
                                text: "\uf074" // shuffle
                                color: (cc.hasMedia && cc.mediaPlayer.shuffleSupported && cc.mediaPlayer.shuffle) ? cc.fg : cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 18
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: if (cc.hasMedia && cc.mediaPlayer.shuffleSupported) cc.mediaPlayer.shuffle = !cc.mediaPlayer.shuffle
                                }
                            }

                            Text {
                                text: "\uf048" // previous
                                color: (cc.hasMedia && cc.mediaPlayer.canGoPrevious) ? cc.fg : cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 24
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: if (cc.hasMedia) cc.mediaPlayer.previous()
                                }
                            }

                            Text {
                                text: (cc.hasMedia && cc.mediaPlayer.isPlaying) ? "\uf04c" : "\uf04b" // pause / play
                                color: cc.fg
                                font.family: cc.fontFamily
                                font.pixelSize: 30
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: if (cc.hasMedia) cc.mediaPlayer.togglePlaying()
                                }
                            }

                            Text {
                                text: "\uf051" // next
                                color: (cc.hasMedia && cc.mediaPlayer.canGoNext) ? cc.fg : cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 24
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: if (cc.hasMedia) cc.mediaPlayer.next()
                                }
                            }

                            Item {
                                width: repeatIcon.implicitWidth
                                height: repeatIcon.implicitHeight
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: {
                                        if (!cc.hasMedia || !cc.mediaPlayer.loopSupported) return;
                                        if (cc.mediaPlayer.loopState === MprisLoopState.None) cc.mediaPlayer.loopState = MprisLoopState.Playlist;
                                        else if (cc.mediaPlayer.loopState === MprisLoopState.Playlist) cc.mediaPlayer.loopState = MprisLoopState.Track;
                                        else cc.mediaPlayer.loopState = MprisLoopState.None;
                                    }
                                }

                                Text {
                                    id: repeatIcon
                                    text: "\uf01e" // repeat / loop
                                    color: (cc.hasMedia && cc.mediaPlayer.loopSupported && cc.mediaPlayer.loopState !== MprisLoopState.None) ? cc.fg : cc.fgDim
                                    font.family: cc.fontFamily
                                    font.pixelSize: 18
                                    font.bold: true
                                }

                                Text {
                                    anchors.right: repeatIcon.right
                                    anchors.bottom: repeatIcon.bottom
                                    anchors.rightMargin: -3
                                    anchors.bottomMargin: -3
                                    visible: cc.hasMedia && cc.mediaPlayer.loopSupported && cc.mediaPlayer.loopState === MprisLoopState.Track
                                    text: "1"
                                    color: cc.fg
                                    font.family: cc.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }
                    }
                }

                // Spacer pushes the remaining right-column widgets to the bottom.
                Item { Layout.fillWidth: true; Layout.fillHeight: true }

                // ---- System resources widget ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // CPU.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 86
                        implicitHeight: 86
                        radius: 12
                        color: cc.bgAlt
                        clip: true

                        Text {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            text: "\uf2db\n" + Math.round(cc.cpuPercent) + "%"
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            lineHeight: 1.3
                        }
                    }

                    // RAM.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 86
                        implicitHeight: 86
                        radius: 12
                        color: cc.bgAlt
                        clip: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "\uf0a0"
                                color: cc.fg
                                font.family: cc.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                            }

                            Text {
                                id: ramUsedText
                                Layout.alignment: Qt.AlignHCenter
                                text: cc.ramUsedGb.toFixed(1) + " GB"
                                color: cc.fg
                                font.family: cc.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: Math.max(ramUsedText.implicitWidth, ramTotalText.implicitWidth)
                                Layout.preferredHeight: 1
                                color: cc.fg
                            }

                            Text {
                                id: ramTotalText
                                Layout.alignment: Qt.AlignHCenter
                                text: cc.ramTotalGb.toFixed(1) + " GB"
                                color: cc.fg
                                font.family: cc.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                    }

                    // GPU.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 86
                        implicitHeight: 86
                        radius: 12
                        color: cc.bgAlt
                        clip: true

                        Text {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            text: "\uf26c\n" + Math.round(cc.gpuPercent) + "%"
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            lineHeight: 1.3
                        }
                    }
                }

                // ---- Volume + output device widget ----
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: volCol.implicitHeight + 32
                    radius: 12
                    color: cc.bgAlt

                    ColumnLayout {
                        id: volCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        spacing: 12

                        // Volume row: icon + slider.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            // Volume / mute icon (click to toggle mute).
                            Text {
                                Layout.preferredWidth: 32
                                horizontalAlignment: Text.AlignHCenter
                                text: {
                                    if (!cc.audioSink || !cc.audioSink.audio) return "\uf026";
                                    const a = cc.audioSink.audio;
                                    if (a.muted || a.volume <= 0.001) return "\uf026";      // muted
                                    if (a.volume < 0.5) return "\uf027";                     // low
                                    return "\uf028";                                         // high
                                }
                                color: cc.fg
                                font.family: cc.fontFamily
                                font.pixelSize: 22
                                font.bold: true
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onClicked: if (cc.audioSink && cc.audioSink.audio)
                                        cc.audioSink.audio.muted = !cc.audioSink.audio.muted
                                }
                            }

                            // Slider track.
                            Rectangle {
                                id: sliderTrack
                                Layout.fillWidth: true
                                implicitHeight: 8
                                radius: 4
                                color: cc.bgAlt2

                                readonly property real vol:
                                    (cc.audioSink && cc.audioSink.audio) ? cc.audioSink.audio.volume : 0

                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, sliderTrack.vol))
                                    height: parent.height
                                    radius: 4
                                    color: cc.fg
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onPressed: setVol(mouse.x)
                                    onPositionChanged: if (pressed) setVol(mouse.x)
                                    function setVol(x) {
                                        if (!cc.audioSink || !cc.audioSink.audio) return;
                                        let v = x / sliderTrack.width;
                                        v = Math.max(0, Math.min(1, v));
                                        cc.audioSink.audio.muted = false;
                                        cc.audioSink.audio.volume = v;
                                    }
                                }
                            }

                            // Percentage.
                            Text {
                                Layout.preferredWidth: 42
                                horizontalAlignment: Text.AlignRight
                                text: (cc.audioSink && cc.audioSink.audio)
                                    ? Math.round(cc.audioSink.audio.volume * 100) + "%" : "--"
                                color: cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }

                        // Sample rate buttons.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: cc.sampleRates
                                Rectangle {
                                    required property var modelData
                                    readonly property bool isCurrent:
                                        modelData === 0 ? !cc.sampleRateForced
                                                        : (cc.sampleRateForced && modelData === cc.sampleRate)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 6
                                    color: isCurrent ? cc.fg : cc.bgAlt2

                                    Text {
                                        anchors.centerIn: parent
                                        text: cc.rateLabel(modelData)
                                        color: parent.isCurrent ? cc.bg : cc.fgDim
                                        font.family: cc.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: cc.setRate(modelData)
                                    }
                                }
                            }
                        }

                    }
                }

                // ---- Mouse battery widget ----
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 56
                    radius: 12
                    color: cc.bgAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        Text {
                            text: cc.mouseBatteryIcon()
                            color: cc.mouseBatteryPct >= 0 && cc.mouseBatteryPct <= 15 ? cc.critical : cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 20
                            font.bold: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: "Mouse"
                                color: cc.fg
                                font.family: cc.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                            }
                            Text {
                                text: "Logitech PRO X 2"
                                color: cc.fgDim
                                font.family: cc.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        Text {
                            text: cc.mouseBatteryPct >= 0 ? cc.mouseBatteryPct + "%" : "--"
                            color: cc.mouseBatteryPct >= 0 && cc.mouseBatteryPct <= 15 ? cc.critical : cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                        }
                    }
                }

                // ---- Calculator widget ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: calcCol.implicitHeight + 32
                    radius: 12
                    color: cc.bgAlt

                    ColumnLayout {
                        id: calcCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        spacing: 12

                        // Input field.
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 42
                            radius: 8
                            color: cc.bgAlt2

                            TextInput {
                                id: calcInput
                                anchors.fill: parent
                                anchors.margins: 10
                                text: cc.calcDisplay
                                color: cc.fg
                                font.family: cc.fontFamily
                                font.pixelSize: 20
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                                inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhDecimalNumbers
                                validator: RegularExpressionValidator { regularExpression: /^-?\d*\.?\d*/ }
                                onTextChanged: cc.calcTyping()
                                onAccepted: cc.calcPress("=")
                            }
                        }

                        // Operator buttons.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: ["C", "+", "-", "*", "/", "="]
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 38
                                    radius: 8
                                    color: calcOpArea.containsMouse ? cc.accent : cc.bgAlt2

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: cc.fg
                                        font.family: cc.fontFamily
                                        font.pixelSize: 18
                                        font.bold: true
                                    }
                                    MouseArea {
                                        id: calcOpArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: cc.calcPress(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Power buttons widget ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Update
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 12
                        color: updateArea.containsMouse ? cc.accent : cc.bgAlt

                        Text {
                            anchors.centerIn: parent
                            text: cc.checkingUpdates
                                ? "..."
                                : (cc.updateCount > 0 ? cc.updateCount : "\uf00c")
                            color: cc.checkingUpdates ? cc.fgDim : cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 22
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            lineHeight: 1.3
                        }
                        MouseArea {
                            id: updateArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: cc.runUpdate()
                        }
                    }

                    // Shutdown
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 12
                        color: shutdownArea.containsMouse ? cc.critical : cc.bgAlt

                        Text {
                            anchors.centerIn: parent
                            text: "\uf011" // power
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 22
                            font.bold: true
                        }
                        MouseArea {
                            id: shutdownArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: cc.powerShutdown()
                        }
                    }

                    // Reboot
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 12
                        color: rebootArea.containsMouse ? cc.accent : cc.bgAlt

                        Text {
                            anchors.centerIn: parent
                            text: "\uf021" // reboot / refresh
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 22
                            font.bold: true
                        }
                        MouseArea {
                            id: rebootArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: cc.powerReboot()
                        }
                    }

                    // Logout
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 12
                        color: logoutArea.containsMouse ? cc.accent : cc.bgAlt

                        Text {
                            anchors.centerIn: parent
                            text: "\uf08b" // sign-out
                            color: cc.fg
                            font.family: cc.fontFamily
                            font.pixelSize: 22
                            font.bold: true
                        }
                        MouseArea {
                            id: logoutArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: cc.powerLogout()
                        }
                    }
                }

            }

        }

    }
}
