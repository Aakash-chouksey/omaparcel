import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Sender panel. Thin client over tsctl: the daemon is the only writer, this
// panel never speaks HTTP or SQL. Read state from `tsctl status --json`, act
// through tsctl, then read again.
Panel {
  id: root

  moduleName: "codejack.tunnelshare"
  ipcTarget: "codejack.tunnelshare"

  property var anchorItem: null
  property var hostWidget: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // -------------------------------------------------------------- state

  property var statusData: null
  property bool daemonDown: false
  property string tunnelState: ""
  property string tunnelError: ""
  property bool tsctlMissing: false
  property string statusProblem: ""
  property string actionError: ""

  property var shares: []
  property double nowSecs: 0

  property var lastShare: null
  property string lastPin: ""
  property string pendingPin: ""
  property string qrPath: ""
  property string copiedField: ""

  property bool pinEnabled: false
  property string pinText: "6"
  property bool noteOpen: false
  property string noteText: ""
  property int hours: 24

  property bool busyPick: false
  property bool busyToggle: false
  property bool busyQr: false
  property bool confirmStopOpen: false

  readonly property bool cloudflaredMissing: /cloudflared/i.test(tunnelError)
  readonly property bool shareBusy: busyPick || shareProc.running
  readonly property bool pinValid: pinText.length >= 4 && pinText.length <= 8
  readonly property bool canShare: !shareBusy && !tsctlMissing && !daemonDown && (!pinEnabled || pinValid)
  readonly property bool showLinks: !tsctlMissing && !daemonDown

  // One word for the bar icon. The panel decides it once so the bar and the
  // panel status line cannot drift apart.
  readonly property string barState: {
    if (tsctlMissing || daemonDown) return "off"
    if (statusData === null) return "unknown"
    if (tunnelState === "up") return "live"
    if (tunnelState === "starting") return "starting"
    if (tunnelError !== "" || cloudflaredMissing) return "error"
    return "off"
  }

  // ------------------------------------------------------------ helpers

  function str(v, fallback) {
    if (v === undefined || v === null) return fallback
    var s = String(v)
    return s.trim() === "" ? fallback : s
  }

  function setError(message) {
    var text = String(message === undefined || message === null ? "" : message).trim()
    if (text !== "") root.actionError = text
  }

  function clearError() {
    root.actionError = ""
    root.statusProblem = ""
  }

  function publicHost() {
    return String(statusData ? statusData.public_base || "" : "").replace(/^https?:\/\//, "")
  }

  function statusText() {
    if (tsctlMissing) return "tsctl is not on PATH"
    if (daemonDown) return "Daemon down."
    if (statusData === null) return statusProblem !== "" ? "Cannot read state" : "Reading state…"
    if (cloudflaredMissing) return "cloudflared is not installed"
    if (tunnelState === "up") {
      var checked = statusData && statusData.tunnel ? statusData.tunnel.verified !== false : true
      return "Live at " + publicHost() + (checked ? "" : (tunnelError !== "" ? " (unverified)" : " (checking)"))
    }
    if (tunnelState === "starting") return "Starting the tunnel"
    if (tunnelState === "disabled") return "Tunnel disabled"
    if (tunnelError !== "") return "Tunnel down. " + tunnelError
    return "Tunnel down."
  }

  function statusColor() {
    if (tunnelState === "up" && !daemonDown) return tunnelError !== "" ? urgent : accent
    if (cloudflaredMissing || tunnelError !== "") return urgent
    return dim
  }

  function statusActionText() {
    if (tsctlMissing || daemonDown) return "Start sharing"
    if (cloudflaredMissing) return ""
    if (tunnelState === "down" || tunnelState === "disabled") return "Restart"
    return ""
  }

  function tooltipText() {
    if (tsctlMissing) return "TunnelShare · tsctl missing"
    if (daemonDown) return "TunnelShare · daemon down"
    if (statusData === null) return "TunnelShare"
    if (tunnelState === "up") return "TunnelShare · live at " + publicHost() + (tunnelError !== "" ? " (unverified)" : "")
    if (tunnelState === "starting") return "TunnelShare · starting"
    if (cloudflaredMissing) return "TunnelShare · cloudflared missing"
    if (tunnelError !== "") return "TunnelShare · " + tunnelError
    return "TunnelShare · tunnel down"
  }

  function copyText(text, field) {
    var value = String(text === undefined || text === null ? "" : text)
    if (value === "") return
    Quickshell.execDetached(["wl-copy", value])
    root.copiedField = field
    copyTimer.restart()
  }

  function makeLink() {
    if (!lastShare) return ""
    return str(lastShare.url, "") !== "" ? String(lastShare.url) : String(lastShare.path || "")
  }

  function resultHint() {
    if (!lastShare) return ""
    if (str(lastShare.url, "") !== "") return ""
    return "The tunnel is down. This path works once it is back up."
  }

  // ------------------------------------------------------------ actions

  function refresh() {
    if (whichProc.running || statusProc.running) return
    whichProc.running = true
  }

  function refreshShares() {
    if (listProc.running || root.daemonDown || root.tsctlMissing) return
    listProc.running = true
  }

  function setService(action) {
    if (serviceProc.running) return
    root.clearError()
    root.busyToggle = true
    serviceProc.command = ["systemctl", "--user", action, "tunnelshare"]
    serviceProc.running = true
  }

  function toggleSharing() {
    if (root.busyToggle) return
    // A running daemon with a broken tunnel still counts as sharing on, so the
    // switch tracks the daemon, and the status line offers the restart.
    if (root.daemonDown || root.statusData === null) root.setService("start")
    else root.confirmStopOpen = true
  }

  function runStatusAction() {
    if (root.daemonDown || root.tsctlMissing || root.statusData === null) {
      root.setService("start")
      return
    }
    if (tunnelProc.running) return
    root.clearError()
    root.busyToggle = true
    tunnelProc.running = true
  }

  function pickPaths(directory) {
    if (pickProc.running || root.shareBusy) return
    root.clearError()
    root.busyPick = true
    pickProc.command = directory
      ? ["omarchy", "file", "select", "--title", "Share folder", "--directory"]
      : ["omarchy", "file", "select", "--title", "Share files", "--multiple"]
    pickProc.running = true
  }

  // One path per line from the chooser. Each path stays one argv element all
  // the way to tsctl, so spaces never need quoting.
  function splitPaths(text) {
    var lines = String(text === undefined || text === null ? "" : text).split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/\r$/, "")
      if (line !== "") out.push(line)
    }
    return out
  }

  function sharePaths(paths) {
    if (!paths || paths.length === 0) return
    root.clearError()
    root.pendingPin = root.pinEnabled ? root.pinText : ""
    var args = ["tsctl", "share"]
    for (var i = 0; i < paths.length; i++) args.push(String(paths[i]))
    args.push("--json")
    args.push("--hours", String(root.hours))
    if (root.pendingPin !== "") args.push("--pin", root.pendingPin)
    var note = root.noteText.trim()
    if (root.noteOpen && note !== "") args.push("--note", note)
    shareProc.command = args
    shareProc.running = true
  }

  function syncLastShareUrl() {
    if (!root.lastShare) return
    var base = String(root.statusData && root.statusData.public_base || "")
    var path = String(root.lastShare.path || "")
    var url = base !== "" && path !== "" ? base + path : ""
    if (String(root.lastShare.url || "") === url) return
    // A var object is not observable, so reassign a copy to notify bindings.
    var next = {}
    for (var k in root.lastShare) next[k] = root.lastShare[k]
    next.url = url
    root.lastShare = next
  }

  function applyStatus(text) {
    var raw = String(text === undefined || text === null ? "" : text).trim()
    if (raw === "") return
    try {
      var data = JSON.parse(raw)
      var tun = data && data.tunnel ? data.tunnel : {}
      root.statusData = data
      root.daemonDown = false
      root.statusProblem = ""
      root.tunnelState = String(tun.state || "")
      root.tunnelError = String(tun.error || "")
      root.syncLastShareUrl()
    } catch (e) {
      root.statusProblem = "tsctl status returned no usable JSON"
    }
  }

  function applyShares(text) {
    var raw = String(text === undefined || text === null ? "" : text).trim()
    root.nowSecs = Date.now() / 1000
    if (raw === "") return
    try {
      var data = JSON.parse(raw)
      root.shares = data && Array.isArray(data.shares) ? data.shares : []
    } catch (e) {
      root.shares = []
    }
  }

  function applyShare(text) {
    var raw = String(text === undefined || text === null ? "" : text).trim()
    if (raw === "") return
    var data = null
    try {
      data = JSON.parse(raw)
    } catch (e) {
      root.setError("tsctl share returned no usable JSON")
      return
    }
    if (!data || !data.id) {
      root.setError("tsctl share returned no id")
      return
    }
    root.lastShare = data
    root.lastPin = data.pin_set === true ? root.pendingPin : ""
    root.qrPath = ""
    root.pinEnabled = false
    root.pinText = "6"
    root.noteOpen = false
    root.noteText = ""
  }

  function applyQr(text) {
    var lines = splitPaths(text)
    if (lines.length > 0) root.qrPath = lines[0]
  }

  // -------------------------------------------------------------- timers

  Timer {
    id: pollTimer
    // 3 s while the panel reads it, slower when only the bar icon needs it.
    interval: root.opened ? 3000 : 8000
    running: true
    repeat: true
    triggeredOnStart: true
    property int ticks: 0
    onTriggered: {
      root.refresh()
      ticks++
      if (root.opened && ticks % 3 === 0) root.refreshShares()
    }
  }

  Timer {
    id: copyTimer
    interval: 1600
    running: false
    repeat: false
    onTriggered: root.copiedField = ""
  }

  // ----------------------------------------------------------- processes

  Process {
    id: whichProc
    command: ["which", "tsctl"]
    onExited: function(exitCode) {
      var missing = exitCode !== 0
      if (missing !== root.tsctlMissing) {
        root.tsctlMissing = missing
        if (missing) {
          root.statusData = null
          root.daemonDown = false
          root.shares = []
        }
      }
      if (!missing) statusProc.running = true
    }
  }

  Process {
    id: statusProc
    command: ["tsctl", "status", "--json"]
    property string stderrText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: statusProc.stderrText = text
    }
    onExited: function(exitCode) {
      var message = String(statusProc.stderrText || "").trim()
      statusProc.stderrText = ""
      if (exitCode === 2) {
        // Documented exit code for "daemon is down", not a parse error.
        root.daemonDown = true
        root.statusData = null
        root.tunnelState = ""
        root.tunnelError = ""
        root.shares = []
        root.statusProblem = /daemon unreachable/.test(message) ? "" : message
        return
      }
      if (exitCode !== 0) root.setError(message !== "" ? message : "tsctl status exited " + exitCode)
    }
  }

  Process {
    id: listProc
    command: ["tsctl", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyShares(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.shares = []
    }
  }

  Process {
    id: pickProc
    property string stdoutText: ""
    property string stderrText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: pickProc.stdoutText = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: pickProc.stderrText = text
    }
    onExited: function(exitCode) {
      var paths = root.splitPaths(pickProc.stdoutText)
      var message = String(pickProc.stderrText || "").trim()
      pickProc.stdoutText = ""
      pickProc.stderrText = ""
      root.busyPick = false
      // Exit 1 is "nothing picked", a decision and not a fault.
      if (exitCode === 1) return
      if (exitCode !== 0) {
        root.setError(message !== "" ? message : "The file chooser failed")
        return
      }
      root.sharePaths(paths)
    }
  }

  Process {
    id: shareProc
    property string stderrText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyShare(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: shareProc.stderrText = text
    }
    onExited: function(exitCode) {
      var message = String(shareProc.stderrText || "").trim()
      shareProc.stderrText = ""
      if (exitCode !== 0) root.setError(message !== "" ? message : "tsctl share exited " + exitCode)
      root.refresh()
      root.refreshShares()
    }
  }

  Process {
    id: revokeProc
    property string targetId: ""
    property string stderrText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: revokeProc.stderrText = text
    }
    onExited: function(exitCode) {
      var message = String(revokeProc.stderrText || "").trim()
      revokeProc.stderrText = ""
      if (exitCode !== 0) {
        root.setError(message !== "" ? message : "tsctl revoke exited " + exitCode)
      } else if (root.lastShare && root.lastShare.id === revokeProc.targetId) {
        root.lastShare = null
        root.lastPin = ""
        root.qrPath = ""
      }
      root.refresh()
      root.refreshShares()
    }
  }

  Process {
    id: qrProc
    property string stderrText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyQr(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: qrProc.stderrText = text
    }
    onExited: function(exitCode) {
      var message = String(qrProc.stderrText || "").trim()
      qrProc.stderrText = ""
      root.busyQr = false
      if (exitCode !== 0) root.setError(message !== "" ? message : "tsctl qr exited " + exitCode)
    }
  }

  Process {
    id: serviceProc
    property string stderrText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: serviceProc.stderrText = text
    }
    onExited: function(exitCode) {
      var message = String(serviceProc.stderrText || "").trim()
      serviceProc.stderrText = ""
      root.busyToggle = false
      if (exitCode !== 0) root.setError(message !== "" ? message : "systemctl exited " + exitCode)
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: tunnelProc
    property string stderrText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: tunnelProc.stderrText = text
    }
    onExited: function(exitCode) {
      var message = String(tunnelProc.stderrText || "").trim()
      tunnelProc.stderrText = ""
      root.busyToggle = false
      if (exitCode !== 0) root.setError(message !== "" ? message : "tsctl tunnel restart exited " + exitCode)
      Qt.callLater(root.refresh)
    }
  }

  function revoke(shareId) {
    var id = String(shareId === undefined || shareId === null ? "" : shareId)
    if (id === "" || revokeProc.running) return
    root.clearError()
    revokeProc.targetId = id
    revokeProc.command = ["tsctl", "revoke", id]
    revokeProc.running = true
  }

  function showQr(shareId) {
    var id = String(shareId === undefined || shareId === null ? "" : shareId)
    if (id === "" || qrProc.running) return
    root.clearError()
    root.busyQr = true
    root.qrPath = ""
    qrProc.command = ["tsctl", "qr", id]
    qrProc.running = true
  }

  onOpenedChanged: {
    if (!opened) {
      root.confirmStopOpen = false
      return
    }
    root.clearError()
    root.refresh()
    root.refreshShares()
  }

  Component.onCompleted: root.refresh()

  // -------------------------------------------------------------- content

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The PIN and note fields need the keys; everything else is panel keys.
      blocked: pinField.activeFocus || noteField.activeFocus
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") {
          root.refresh()
          root.refreshShares()
        }
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        // ------------------------------------------------------ header
        Item {
          width: parent.width
          implicitHeight: Math.max(headerLabels.implicitHeight, sharingToggle.implicitHeight)

          Column {
            id: headerLabels
            anchors.left: parent.left
            anchors.right: sharingToggle.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "Sharing"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.statusActionText() === ""
              text: root.statusText()
              color: root.statusColor()
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              maximumLineCount: 1
            }
          }

          ToggleSwitch {
            id: sharingToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.tsctlMissing
            checked: !root.daemonDown && root.statusData !== null
            busy: root.busyToggle
            foreground: root.foreground
            accent: root.accent
            onToggled: root.toggleSharing()
          }
        }

        // Status with an inline action when there is one to offer.
        Item {
          width: parent.width
          implicitHeight: Math.max(statusLine.implicitHeight, statusAction.implicitHeight)
          visible: root.statusActionText() !== "" || root.statusProblem !== ""

          Text {
            id: statusLine
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: statusAction.visible ? statusAction.left : parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusProblem !== "" ? root.statusProblem : root.statusText()
            color: root.statusProblem !== "" ? root.dim : root.statusColor()
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          Button {
            id: statusAction
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.statusActionText() !== ""
            text: root.statusActionText()
            foreground: root.accent
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.runStatusAction()
          }
        }

        // -------------------------------------------------- primary action
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            id: filesButton
            width: Math.round((parent.width - parent.spacing) * 0.58)
            text: "Share files"
            iconText: root.shareBusy ? "\uf110" : ""
            iconSpinning: root.shareBusy
            selected: true
            enabled: root.canShare
            opacity: enabled ? 1 : 0.5
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.pickPaths(false)
          }

          Button {
            width: parent.width - parent.spacing - filesButton.width
            text: "Share folder"
            bordered: true
            enabled: root.canShare
            opacity: enabled ? 1 : 0.5
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.pickPaths(true)
          }
        }

        // ------------------------------------------------- share options
        Item {
          width: parent.width
          implicitHeight: Math.max(pinToggle.implicitHeight, hoursGroup.implicitHeight)

          ToggleSwitch {
            id: pinToggle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            checked: root.pinEnabled
            foreground: root.foreground
            accent: root.accent
            onToggled: {
              root.pinEnabled = !root.pinEnabled
              if (root.pinEnabled && root.pinText === "") root.pinText = "6"
            }
          }

          Text {
            anchors.left: pinToggle.right
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Require a code"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          ButtonGroup {
            id: hoursGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: [
              { value: "1", label: "1h" },
              { value: "24", label: "24h" },
              { value: "72", label: "72h" }
            ]
            value: String(root.hours)
            focusable: false
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onChanged: function(value) { root.hours = Number(value) }
          }
        }

        TextField {
          id: pinField
          // Seeded on show, then the field owns its text. A text binding would
          // break on the first keystroke anyway and leave a stale value behind.
          width: Math.min(parent.width, Style.space(140))
          visible: root.pinEnabled
          height: visible ? implicitHeight : 0
          placeholderText: "4 to 8 digits"
          maximumLength: 8
          foreground: root.foreground
          accent: root.accent
          validator: RegularExpressionValidator { regularExpression: /^[0-9]{0,8}$/ }
          onVisibleChanged: if (visible) text = root.pinText
          onTextEdited: root.pinText = text
        }

        Button {
          width: parent.width
          visible: !root.noteOpen
          height: visible ? implicitHeight : 0
          leftAlign: true
          text: root.noteOpen ? "" : "Add a note"
          foreground: root.dim
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: {
            root.noteOpen = true
            Qt.callLater(function() { noteField.forceActiveFocus() })
          }
        }

        TextField {
          id: noteField
          width: parent.width
          visible: root.noteOpen
          height: visible ? implicitHeight : 0
          placeholderText: "Optional note, 200 characters"
          maximumLength: 200
          foreground: root.foreground
          accent: root.accent
          onVisibleChanged: if (visible) text = root.noteText
          onTextEdited: root.noteText = text
        }

        // ---------------------------------------------------- result card
        BorderSurface {
          width: parent.width
          visible: root.lastShare !== null
          height: visible ? implicitHeight : 0
          implicitHeight: resultColumn.implicitHeight + Style.space(20)
          color: Style.normalFillFor(root.foreground, root.accent)
          borderSpec: Border.controlSpec("selected", root.foreground, root.accent)
          radius: Style.cornerRadius

          Column {
            id: resultColumn
            x: Style.space(10)
            y: Style.space(10)
            width: parent.width - Style.space(20)
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.makeLink()
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
              wrapMode: Text.Wrap
              maximumLineCount: 1
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.resultHint() !== ""
              text: root.resultHint()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Row {
              spacing: Style.space(8)

              Button {
                text: root.copiedField === "link" ? "Copied" : "Copy link"
                selected: root.copiedField === "link"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.copyText(root.makeLink(), "link")
              }

              Button {
                text: root.busyQr ? "Making…" : "QR"
                bordered: true
                enabled: !root.busyQr && root.lastShare !== null
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.showQr(root.lastShare ? root.lastShare.id : "")
              }
            }

            Image {
              visible: root.qrPath !== ""
              width: Math.min(parent.width, Style.space(150))
              height: visible ? width : 0
              cache: false
              fillMode: Image.PreserveAspectFit
              source: root.qrPath !== "" ? Util.fileUrl(root.qrPath) : ""
            }

            Row {
              visible: root.lastPin !== ""
              height: visible ? implicitHeight : 0
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.lastPin
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: Style.space(2)
              }

              Button {
                anchors.verticalCenter: parent.verticalCenter
                text: root.copiedField === "pin" ? "Copied" : "Copy code"
                selected: root.copiedField === "pin"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.copyText(root.lastPin, "pin")
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.lastPin !== ""
              text: "Send the code in a separate message."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }
          }
        }

        // --------------------------------------------------- active links
        PanelSectionHeader {
          visible: root.showLinks
          height: visible ? implicitHeight : 0
          text: "ACTIVE LINKS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        ListView {
          id: shareList
          width: parent.width
          // Scrolls on its own; the rest of the panel stays put.
          height: root.showLinks && count > 0 ? Math.min(contentHeight, Style.space(150)) : 0
          visible: height > 0
          spacing: Style.space(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          model: root.shares

          delegate: ShareRow {
            required property var modelData
            width: ListView.view.width
            share: modelData
            nowSecs: root.nowSecs
            copied: root.copiedField === modelData.id
            foreground: root.foreground
            dim: root.dim
            accent: root.accent
            urgent: root.urgent
            fontFamily: root.fontFamily
            onCopyRequested: function(shareId) {
              var share = root.shares.find(function(s) { return s.id === shareId })
              if (!share) return
              root.copyText(share.url ? share.url : share.path, shareId)
            }
            onRevokeRequested: function(shareId) { root.revoke(shareId) }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.showLinks && root.shares.length === 0
          height: visible ? implicitHeight : 0
          text: "Nothing shared yet. Pick a file to start."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        // ---------------------------------------------------- error line
        Text {
          id: errorLine
          textFormat: Text.PlainText
          width: parent.width
          visible: root.errorText() !== ""
          height: visible ? implicitHeight : 0
          text: root.errorText()
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }

      ConfirmDialog {
        id: stopConfirm
        anchors.fill: parent
        z: 10
        opened: root.confirmStopOpen
        message: "Stop sharing? Every live link stops working."
        confirmText: "Stop"
        foreground: root.foreground
        fontFamily: root.fontFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.confirmStopOpen = false
        onConfirmed: {
          root.confirmStopOpen = false
          root.setService("stop")
        }
      }
    }
  }

  function errorText() {
    if (root.actionError !== "") return root.actionError
    if (root.tsctlMissing) return "Tried: tsctl status --json"
    return ""
  }
}
