import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// DNS Changer bar pill.
//
// Left-click toggles the panel. Middle-click refreshes the active-DNS status.
// Label mirrors the CLI's `status` command: "Off" (no active nameservers),
// the matching catalog server's name, or "Custom" (connected, but not to
// anything in our list). This is the only entry point; it loads Panel.qml
// and owns the bar label + click routing (same shape as the clock/chand
// pattern).

BarWidget {
  id: root
  moduleName: "io.github.hack3rrabbit.dns-changer"

  // Same face the DnsChanger desktop/web app uses (its index.css: `body {
  // font-family: Inter }`, Inter-Medium.ttf) instead of the shell's bar
  // theme font. Bundled from Google Fonts, SIL OFL 1.1 (fonts/Inter-OFL.txt).
  FontLoader {
    id: interFont
    source: Qt.resolvedUrl("fonts/Inter.ttf")
  }

  property var panelLoader: null

  // Mirrored from the panel's poller so the pill renders without the panel
  // being open.
  property var statusState: null // { state: "off"|"known"|"unknown", server }
  readonly property bool hasStatus: !!statusState

  readonly property color offColor: Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.3)
  readonly property color onColor: root.bar ? root.bar.barForeground : Color.foreground

  readonly property string label: {
    if (!root.hasStatus) return "DNS …"
    if (root.statusState.state === "off") return "DNS Off"
    if (root.statusState.state === "known") return root.statusState.server.name
    return "DNS Custom"
  }

  readonly property color pillColor: (root.hasStatus && root.statusState.state === "off") ? root.offColor : root.onColor

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function setStatusState(state) {
    root.statusState = state
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.hack3rrabbit.dns-changer"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    labelVisible: true
    hasVisualContent: text !== ""
    fontFamily: interFont.name
    fontSize: Style.font.bodySmall
    foreground: root.pillColor
    useActiveColor: false
    tooltipText: "DNS Changer — click to open, middle-click to refresh"

    onPressed: function (b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) { root.refresh(); return }
      root.togglePanel()
    }
  }
}
