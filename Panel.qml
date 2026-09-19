import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Loads the same face the DnsChanger desktop/web app uses everywhere
// (its index.css declares `body { font-family: Inter }`, Inter-Medium.ttf)
// so the panel matches instead of falling back to the shell's bar theme
// font. Bundled from Google Fonts (fonts/Inter.ttf, SIL OFL 1.1 —
// fonts/Inter-OFL.txt), a variable font covering every weight the original
// app uses.

// DNS Changer popup panel — connect/disconnect/status, ported from
// dnschanger-cli's three commands:
//   connect  -> pick a row, type a custom address, or hit Random
//   disconnect (aliases dis/d8t) -> the Disconnect button
//   status   -> the header line, kept live by a background poller

Panel {
  id: root
  moduleName: "io.github.hack3rrabbit.dns-changer"
  ipcTarget: "io.github.hack3rrabbit.dns-changer"
  manageIpc: false

  FontLoader {
    id: interFont
    source: Qt.resolvedUrl("fonts/Inter.ttf")
  }

  property var anchorItem: null
  property var hostWidget: null
  onHostWidgetChanged: root.pushStatusToHost()
  readonly property var barIdentity: hostWidget || root

  // Quickshell's Process does not resolve relative paths against the
  // plugin dir, so derive the script's absolute path from this file's URL
  // (same trick as chand's fetchChand).
  readonly property string scriptPath: Qt.resolvedUrl("scripts/dns-changer").toString().replace(/^file:\/\//, "")

  readonly property color connectedColor: "#22c55e"

  property var servers: Model.bundledServers()
  // Saved, named custom servers — not part of the original CLI (its -s flag
  // connects to a synthetic customServer() but never persists it).
  property var customProfiles: []
  // Catalog + saved profiles, sorted by live ping once available (falls
  // back to rate order for anything not yet pinged) — this drives the
  // visible list and keyboard cursor.
  readonly property var displayServers: Model.sortByPing(root.customProfiles.concat(root.servers), root.pingResults)
  property var activeIps: []
  readonly property var status: Model.statusOf(root.activeIps, root.displayServers)
  property bool busy: false
  property string message: ""
  property string errorText: ""
  property string customText: ""
  property string profileNameText: ""
  property int cursor: 0

  // ip -> latency in ms, or null for a timeout. Not part of the original
  // CLI (it has no ping feature) — a plugin addition, keyed by address so
  // servers sharing an address (several catalog entries do) share a result.
  property var pingResults: ({})

  // domain -> local cached favicon path, or null once scripts/dns-changer
  // favicons has confirmed there's no real icon (see its header comment for
  // why this can't just be a direct URL: DuckDuckGo's icon service serves a
  // generic placeholder instead of failing for an unknown domain).
  property var faviconPaths: ({})

  onOpenedChanged: if (root.opened) Qt.callLater(function() {
    customField.text = root.customText
    profileNameField.text = root.profileNameText
  })

  function open() {
    root.controller.show()
    root.refresh()
    root.fetchServers()
    root.pingServers()
    root.fetchFavicons()
  }

  // ---- persistence: last-known active DNS, so the bar pill and header
  // restore instantly after a shell/plugin reload instead of blanking
  // until the next poll (same pattern as chand's panel.json). ----
  property FileView stateFile: FileView {
    path: Quickshell.env("HOME") + "/.cache/omarchy-dns-changer/state.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.restoreState()
  }
  property FileView serversFile: FileView {
    path: Quickshell.env("HOME") + "/.cache/omarchy-dns-changer/servers.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.restoreServers()
  }
  property FileView customProfilesFile: FileView {
    path: Quickshell.env("HOME") + "/.cache/omarchy-dns-changer/custom-profiles.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.restoreCustomProfiles()
  }

  function persistState() {
    try { stateFile.setText(JSON.stringify({ ts: Math.floor(Date.now() / 1000), activeIps: root.activeIps }) + "\n") } catch (e) {}
  }
  function restoreState() {
    try {
      var raw = String(stateFile.text() || "").trim()
      if (!raw) return
      var st = JSON.parse(raw)
      if (Array.isArray(st.activeIps)) {
        root.activeIps = st.activeIps
        root.pushStatusToHost()
      }
    } catch (e) {}
  }
  function persistServers() {
    try { serversFile.setText(JSON.stringify(root.servers)) } catch (e) {}
  }
  function restoreServers() {
    try {
      var raw = String(serversFile.text() || "").trim()
      if (!raw) return
      var list = JSON.parse(raw)
      if (Array.isArray(list) && list.length) root.servers = Model.attachDomains(Model.sortByRate(list))
    } catch (e) {}
  }
  function persistCustomProfiles() {
    try { customProfilesFile.setText(JSON.stringify(root.customProfiles)) } catch (e) {}
  }
  function restoreCustomProfiles() {
    try { root.customProfiles = Model.loadCustomProfiles(customProfilesFile.text()) } catch (e) {}
    root.pushStatusToHost()
  }
  function pushStatusToHost() {
    if (root.hostWidget && typeof root.hostWidget.setStatusState === "function")
      root.hostWidget.setStatusState(Model.statusOf(root.activeIps, root.displayServers))
  }
  onActiveIpsChanged: { root.persistState(); root.pushStatusToHost() }

  // Panel-cursor flag guard, same rationale as chand's: prefer the shell's
  // setter method; direct property assignment throws on current Omarchy
  // builds that expose it read-only.
  function setCenterHoverRevealSuppressed(value) {
    if (!root.bar) return
    if (typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if ("centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- actions ----
  function refresh() {
    root.errorText = ""
    statusProc.command = [root.scriptPath, "active"]
    statusProc.running = true
  }

  function fetchServers() {
    if (fetchProc.running) return
    fetchProc.command = [root.scriptPath, "fetch-servers"]
    fetchProc.running = true
  }

  function connectServer(server) {
    if (root.busy || !server || connectProc.running) return
    root.busy = true
    root.errorText = ""
    root.message = "Connecting to " + server.name + "…"
    connectProc.command = [root.scriptPath, "connect"].concat(server.servers)
    connectProc.running = true
  }

  function connectCustom() {
    var parsed = Model.parseAddressList(root.customText)
    if (!parsed.ok) { root.errorText = parsed.error; return }
    var existing = Model.serverByAddresses(root.displayServers, parsed.addresses)
    root.connectServer(existing || Model.customServer(parsed.addresses))
  }

  // Saves a named custom profile (persists across restarts, shown in the
  // list, pingable, deletable) and connects to it. Not part of the
  // original CLI — its -s flag connects to a synthetic customServer() but
  // never saves it.
  function saveCustomProfile() {
    var parsed = Model.parseAddressList(root.customText)
    if (!parsed.ok) { root.errorText = parsed.error; return }
    root.customProfiles = Model.upsertCustomProfile(root.customProfiles, root.profileNameText, parsed.addresses)
    root.persistCustomProfiles()
    var saved = Model.serverByAddresses(root.customProfiles, parsed.addresses)
    root.profileNameText = ""
    profileNameField.text = ""
    root.pingServers()
    root.connectServer(saved)
  }

  function removeCustomProfile(key) {
    root.customProfiles = Model.removeCustomProfile(root.customProfiles, key)
    root.persistCustomProfiles()
  }

  function connectRandom() {
    var picked = Model.randomServer(root.servers)
    if (!picked) { root.errorText = "No servers available"; return }
    root.connectServer(picked)
  }

  function disconnect() {
    if (root.busy || disconnectProc.running) return
    root.busy = true
    root.errorText = ""
    root.message = "Disconnecting…"
    disconnectProc.command = [root.scriptPath, "disconnect"]
    disconnectProc.running = true
  }

  function flushCache() {
    if (flushProc.running) return
    root.message = "Flushing DNS cache…"
    flushProc.command = [root.scriptPath, "flush"]
    flushProc.running = true
  }

  // Pings each catalog server's first address once (deduped — several
  // entries share an address). Not part of the original CLI.
  function pingServers() {
    if (pingProc.running) return
    var seen = {}
    var ips = []
    for (var i = 0; i < root.displayServers.length; i++) {
      var ip = root.displayServers[i].servers[0]
      if (ip && !seen[ip]) { seen[ip] = true; ips.push(ip) }
    }
    if (ips.length === 0) return
    pingProc.command = [root.scriptPath, "ping"].concat(ips)
    pingProc.running = true
  }

  // Resolves real favicons for servers that have a known domain (skips
  // ones already resolved). Not part of the original CLI.
  function fetchFavicons() {
    if (faviconsProc.running) return
    var seen = {}
    var domains = []
    for (var i = 0; i < root.servers.length; i++) {
      var d = root.servers[i].domain
      if (d && !seen[d] && !(d in root.faviconPaths)) { seen[d] = true; domains.push(d) }
    }
    if (domains.length === 0) return
    faviconsProc.command = [root.scriptPath, "favicons"].concat(domains)
    faviconsProc.running = true
  }

  function moveCursor(d) {
    if (root.displayServers.length === 0) return
    root.cursor = Math.max(0, Math.min(root.displayServers.length - 1, root.cursor + d))
  }
  function activateCursor() {
    if (root.cursor >= 0 && root.cursor < root.displayServers.length) root.connectServer(root.displayServers[root.cursor])
  }

  // ---- processes ----
  Process {
    id: statusProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var parsed = JSON.parse(raw)
          if (parsed && parsed.ok && Array.isArray(parsed.servers)) root.activeIps = parsed.servers
          else if (parsed && parsed.error) root.errorText = parsed.error
        } catch (e) {}
      }
    }
  }

  Process {
    id: connectProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && parsed.ok) { root.message = "Connected"; root.refresh() }
          else { root.errorText = (parsed && parsed.error) || "Failed to connect"; root.message = "" }
        } catch (e) { root.errorText = "Failed to connect"; root.message = "" }
      }
    }
  }

  Process {
    id: disconnectProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && parsed.ok) { root.message = "Disconnected"; root.refresh() }
          else { root.errorText = (parsed && parsed.error) || "Failed to disconnect"; root.message = "" }
        } catch (e) { root.errorText = "Failed to disconnect"; root.message = "" }
      }
    }
  }

  Process {
    id: flushProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && parsed.ok) root.message = "DNS cache flushed"
          else { root.errorText = (parsed && parsed.error) || "Failed to flush cache"; root.message = "" }
        } catch (e) {}
      }
    }
  }

  Process {
    id: fetchProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var parsed = JSON.parse(raw)
          if (Array.isArray(parsed) && parsed.length) {
            root.servers = Model.attachDomains(Model.sortByRate(parsed))
            root.persistServers()
            root.pingServers()
            root.fetchFavicons()
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: pingProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var parsed = JSON.parse(raw)
          if (parsed && parsed.ok && parsed.results) {
            var merged = {}
            for (var k in root.pingResults) merged[k] = root.pingResults[k]
            for (var k2 in parsed.results) merged[k2] = parsed.results[k2]
            root.pingResults = merged
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: faviconsProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          var parsed = JSON.parse(raw)
          if (parsed && parsed.ok && parsed.results) {
            var merged = {}
            for (var k in root.faviconPaths) merged[k] = root.faviconPaths[k]
            for (var k2 in parsed.results) merged[k2] = parsed.results[k2]
            root.faviconPaths = merged
          }
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: { root.refresh(); root.pingServers(); root.fetchFavicons() }
  }

  // ================= UI =================
  component ServerRow: CursorSurface {
    id: srow
    required property var entry
    required property int index

    readonly property bool isCurrent: root.status.state === "known" && root.status.server && root.status.server.key === entry.key
    readonly property bool isCustom: !!entry.isCustomProfile
    readonly property string primaryAddress: (entry.servers && entry.servers[0]) || ""
    readonly property var pingMs: root.pingResults[primaryAddress]
    readonly property string pingText: Model.formatPing(pingMs)
    readonly property var badge: Model.badgeHsla(entry.key)
    // A local cached path once root.fetchFavicons() has confirmed a real
    // icon exists for this domain (undefined = not resolved yet, null =
    // confirmed no real icon — see scripts/dns-changer's header comment).
    readonly property var faviconEntry: entry.domain ? root.faviconPaths[entry.domain] : null
    readonly property string faviconPath: (typeof faviconEntry === "string") ? faviconEntry : ""
    property bool faviconFailed: false

    width: mainColumn.width
    height: rowInner.height + Style.space(12)
    hasCursor: root.cursor === index
    current: isCurrent
    foreground: root.barForeground
    currentFill: Style.selectedFillFor(root.barForeground, Color.accent)

    Item {
      id: rowInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      height: Math.max(avatar.height, textCol.implicitHeight)

      // Real favicon for well-known providers: root.fetchFavicons() already
      // fetched it via scripts/dns-changer and rejected DuckDuckGo's
      // generic placeholder, so any path here is a genuine icon.
      Image {
        id: favicon
        visible: srow.faviconPath !== "" && !srow.faviconFailed && status === Image.Ready
        width: Style.space(24)
        height: Style.space(24)
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        source: srow.faviconPath !== "" ? ("file://" + srow.faviconPath) : ""
        asynchronous: true
        smooth: true
        fillMode: Image.PreserveAspectFit
        onStatusChanged: if (status === Image.Error) srow.faviconFailed = true
      }

      // Fallback generated monogram badge — shown whenever there's no known
      // domain for this provider, or its favicon failed/hasn't loaded yet
      // (no third-party logos are bundled or reproduced; see Model.badgeHsla).
      Rectangle {
        id: avatar
        visible: !favicon.visible
        width: Style.space(24)
        height: Style.space(24)
        radius: width / 2
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.hsla(srow.badge.h, srow.badge.s, srow.badge.l, srow.badge.a)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: Model.initials(srow.entry.name)
          color: "#ffffff"
          font.family: interFont.name
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      // Remove button for saved custom profiles only — catalog entries
      // aren't user-owned data and can't be deleted.
      PanelActionButton {
        id: removeBtn
        visible: srow.isCustom
        z: 1
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "✕"
        tooltipText: "Remove profile"
        foreground: root.barForeground
        hoverColor: Color.urgent
        onClicked: root.removeCustomProfile(srow.entry.key)
      }

      Column {
        id: textCol
        anchors.left: avatar.right
        anchors.right: srow.isCustom ? removeBtn.left : parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: srow.isCustom ? Style.space(4) : 0
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          elide: Text.ElideRight
          text: (srow.isCurrent ? "● " : "") + srow.entry.name
          color: srow.isCurrent ? root.connectedColor : srow.foreground
          font.family: interFont.name
          font.pixelSize: Style.font.body
          font.bold: srow.isCurrent
        }
        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: parent.width
          elide: Text.ElideRight
          text: Model.tagList(srow.entry.tags) + (srow.pingText !== "" ? "  ·  " + srow.pingText : "")
          color: srow.pingMs === null ? Color.urgent : Qt.darker(srow.foreground, 1.5)
          font.family: interFont.name
          font.pixelSize: Style.font.caption
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPositionChanged: root.cursor = srow.index
      onClicked: root.connectServer(srow.entry)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: customField.activeFocus || profileNameField.activeFocus
      onCloseRequested: root.close()
      onMoveRequested: function (dx, dy) { root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onTextKey: function (t) { if (t === "r") root.refresh() }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: mainColumn
          width: scroll.width
          spacing: Style.space(12)

          // ---- HEADER ----
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              id: titleText
              anchors.verticalCenter: parent.verticalCenter
              text: "DNS Changer"
              color: root.barForeground
              font.family: interFont.name
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Item {
              width: Math.max(0, parent.width - titleText.width - flushBtn.width - refreshBtn.width - Style.space(24))
              height: 1
            }
            PanelActionButton {
              id: flushBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: "⟲"
              tooltipText: "Flush DNS cache"
              foreground: root.barForeground
              onClicked: root.flushCache()
            }
            PanelActionButton {
              id: refreshBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: "↻"
              tooltipText: "Refresh status"
              foreground: root.barForeground
              onClicked: root.refresh()
            }
          }

          PanelSeparator { foreground: root.barForeground }

          // ---- STATUS ----
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: {
              if (root.status.state === "off") return "Disconnected — no DNS servers set"
              if (root.status.state === "known") return "Connected to " + root.status.server.name + "  (" + root.status.server.servers.join(", ") + ")"
              return "Connected to an unknown server  (" + root.activeIps.join(", ") + ")"
            }
            color: root.status.state === "off" ? Qt.darker(root.barForeground, 1.4) : root.barForeground
            font.family: interFont.name
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.message !== "" || root.errorText !== ""
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: root.errorText !== "" ? ("⚠ " + root.errorText) : root.message
            color: root.errorText !== "" ? Color.urgent : Qt.darker(root.barForeground, 1.2)
            font.family: interFont.name
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { foreground: root.barForeground }

          // ---- SERVERS (catalog + saved custom profiles, ping-sorted) ----
          PanelSectionHeader {
            text: "Servers (" + root.displayServers.length + ")"
            foreground: root.barForeground
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.displayServers
              delegate: ServerRow {
                required property var modelData
                entry: modelData
              }
            }
          }

          PanelSeparator { foreground: root.barForeground }

          // ---- CUSTOM SERVER ----
          PanelSectionHeader {
            text: "Custom server"
            foreground: root.barForeground
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: customField
              width: parent.width - connectCustomBtn.width - Style.space(8)
              placeholderText: "e.g. 8.8.8.8, 8.8.4.4"
              foreground: root.barForeground
              onTextChanged: root.customText = text
              onAccepted: root.connectCustom()
              onActiveFocusChanged: root.setCenterHoverRevealSuppressed(activeFocus)
            }
            Button {
              id: connectCustomBtn
              anchors.verticalCenter: parent.verticalCenter
              text: "Connect"
              bordered: true
              enabled: !root.busy
              foreground: root.barForeground
              onClicked: root.connectCustom()
            }
          }

          // Saves the address above as a named, reusable profile — shown in
          // the Servers list (pingable, deletable) instead of retyped every
          // time. Not part of the original CLI.
          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: profileNameField
              width: parent.width - saveProfileBtn.width - Style.space(8)
              placeholderText: "Profile name (optional) — saves the address above"
              foreground: root.barForeground
              onTextChanged: root.profileNameText = text
              onAccepted: root.saveCustomProfile()
              onActiveFocusChanged: root.setCenterHoverRevealSuppressed(activeFocus)
            }
            Button {
              id: saveProfileBtn
              anchors.verticalCenter: parent.verticalCenter
              text: "Save profile"
              bordered: true
              enabled: !root.busy && root.customText.trim() !== ""
              foreground: root.barForeground
              onClicked: root.saveCustomProfile()
            }
          }

          PanelSeparator { foreground: root.barForeground }

          // ---- ACTIONS ----
          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Random"
              bordered: true
              enabled: !root.busy
              foreground: root.barForeground
              onClicked: root.connectRandom()
            }
            Button {
              text: "Disconnect"
              bordered: true
              enabled: !root.busy && root.status.state !== "off"
              foreground: root.barForeground
              onClicked: root.disconnect()
            }
            Button {
              text: "Ping all"
              bordered: true
              enabled: !pingProc.running
              foreground: root.barForeground
              onClicked: root.pingServers()
            }
          }
        }
      }
    }
  }
}
