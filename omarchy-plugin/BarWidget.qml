import QtQuick
import qs.Commons
import qs.Ui

// The bar half of the plugin. It owns no state of its own: the panel keeps the
// tsctl snapshot, the bar only reads it, so the icon and the panel can never
// disagree about whether the tunnel is up.
BarWidget {
  id: root

  moduleName: "codejack.tunnelshare"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
  readonly property string shareState: panelItem ? String(panelItem.barState || "unknown") : "unknown"

  // Spec colors: off is dim, starting is normal, live is accent, tunnel error is
  // urgent. No animation here, the icon is a state readout, not a progress bar.
  readonly property color iconColor: {
    if (!bar) return Color.foreground
    if (shareState === "live") return Color.accent
    if (shareState === "error") return bar.urgent
    if (shareState === "starting") return bar.barForeground
    return Qt.darker(bar.barForeground, 1.6)
  }

  function injectPanel() {
    var target = panelItem
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    if (panelItem) panelItem.open()
  }

  function close() {
    if (panelItem) panelItem.close()
  }

  function toggle() {
    if (panelItem) panelItem.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelItem) panelItem.closeForPopoutSwitch()
  }

  function refresh() {
    if (panelItem && panelItem.refresh) panelItem.refresh()
  }

  function tooltipText() {
    if (panelItem && panelItem.tooltipText) return panelItem.tooltipText()
    return "TunnelShare"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
      Qt.callLater(root.refresh)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: false
    foreground: root.iconColor
    tooltipText: root.tooltipText()
    text: "\uf1e6"

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }
}
