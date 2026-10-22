import QtQuick
import qs.Commons
import qs.Ui

// One active link in the panel's list. Owns only the two-step revoke confirm;
// every action leaves through a signal so the panel stays the single caller of
// tsctl.
BorderSurface {
  id: root

  property var share: null
  property double nowSecs: 0
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.45)
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  signal copyRequested(string shareId)
  signal revokeRequested(string shareId)

  readonly property string shareId: share ? String(share.id || "") : ""
  readonly property int fileCount: {
    var n = share && share.files !== undefined && share.files !== null ? Number(share.files) : 0
    return isFinite(n) ? Math.round(n) : 0
  }
  readonly property string noteText: share ? String(share.note || "") : ""
  readonly property bool hasPin: share ? share.pin_set === true : false
  readonly property string link: share
    ? (String(share.url || "") !== "" ? String(share.url) : String(share.path || ""))
    : ""

  property bool confirming: false

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight + Style.space(6)
  color: "transparent"
  borderSpec: Border.none()

  function titleText() {
    if (noteText !== "") return noteText
    return fileCount === 1 ? "1 file" : fileCount + " files"
  }

  function fmtSize(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n <= 0) return ""
    if (n < 1024) return n + " B"
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB"
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(n < 10 * 1024 * 1024 ? 1 : 0) + " MB"
    return (n / (1024 * 1024 * 1024)).toFixed(1) + " GB"
  }

  function expiryText() {
    var expires = share && share.expires_at !== undefined ? Number(share.expires_at) : 0
    var left = expires - nowSecs
    if (!isFinite(left) || left <= 0) return "expired"
    if (left < 3600) return "in " + Math.max(1, Math.round(left / 60)) + "m"
    if (left < 86400) return "in " + Math.round(left / 3600) + "h"
    return "in " + Math.floor(left / 86400) + "d"
  }

  function metaText() {
    var bits = [expiryText()]
    var size = fmtSize(share ? share.size : 0)
    if (noteText !== "") bits.push(fileCount === 1 ? "1 file" : fileCount + " files")
    if (size !== "") bits.push(size)
    if (hasPin) bits.push("code")
    return bits.join(" · ")
  }

  Item {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.space(2)
    anchors.rightMargin: Style.space(2)
    implicitHeight: Math.max(labels.implicitHeight, actions.implicitHeight)

    Column {
      id: labels
      anchors.left: parent.left
      anchors.right: actions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.titleText()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.metaText()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Button {
        anchors.verticalCenter: parent.verticalCenter
        text: root.confirming ? "Confirm" : "Revoke"
        foreground: root.confirming ? root.urgent : root.dim
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        horizontalPadding: Style.space(6)
        verticalPadding: Style.space(2)
        onClicked: {
          if (root.confirming) {
            root.confirming = false
            root.revokeRequested(root.shareId)
            return
          }
          root.confirming = true
          confirmTimer.restart()
        }
      }

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconText: root.copied ? "\uf00c" : "\uf0ea"
        tooltipText: "Copy link"
        foreground: root.copied ? root.accent : root.dim
        hoverColor: root.accent
        fontFamily: root.fontFamily
        onClicked: root.copyRequested(root.shareId)
      }
    }
  }

  // Panel-level "Copied" feedback lands here as a flag the shell sets through
  // the panel; a row only needs to know whether its own link was copied.
  property bool copied: false

  Timer {
    id: confirmTimer
    interval: 4000
    running: false
    repeat: false
    onTriggered: root.confirming = false
  }
}
