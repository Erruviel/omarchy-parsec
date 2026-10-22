import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Parsec bar widget with an anchored popup panel. All state comes from
// `bin/parsec-panel` (one process per refresh): the instances listed in
// ~/.config/parsec-multi/instances.json, whether each one runs, which
// window and workspace it has and whether it is connected to a host.
// Actions (launch / focus / stop / edit) go through the same script.
Panel {
  id: root
  moduleName: "erruviel.parsec"
  ipcTarget: "erruviel.parsec"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(barForeground, 1.4)
  readonly property color faint: Qt.rgba(barForeground.r, barForeground.g, barForeground.b, 0.25)

  readonly property string panelScript: Qt.resolvedUrl("../bin/parsec-panel").toString().replace(/^file:\/\//, "")

  property var info: ({})
  readonly property bool installed: info.installed === true
  readonly property bool hasBwrap: info.bwrap === true
  readonly property var instances: info.instances || []
  readonly property bool showCount: setting("showCount", true) !== false

  // One action in flight at a time; the affected row dims while it runs.
  property string busyName: ""

  // The instance being edited in the overlay: "+" for a new one, a name
  // for an existing one, "" when closed.
  property string editing: ""
  readonly property var macros: info.macros || []
  function entryFor(name) {
    for (var i = 0; i < instances.length; i++) if (instances[i].name === name) return instances[i]
    return ({})
  }

  readonly property int runningCount: {
    var n = 0
    for (var i = 0; i < instances.length; i++) if (instances[i].running) n++
    return n
  }
  readonly property int connectedCount: {
    var n = 0
    for (var i = 0; i < instances.length; i++) if (instances[i].connected) n++
    return n
  }

  readonly property string statusText: {
    if (!installed) return strings.t("status.notInstalled")
    if (!hasBwrap) return strings.t("status.noBwrap")
    if (instances.length === 0) return strings.t("status.none")
    return strings.t("status.summary")
      .arg(Commons.I18n.formatNumber(runningCount))
      .arg(Commons.I18n.formatNumber(connectedCount))
  }

  // -------------------------------------------------------------- refresh ---
  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function updateInfo(raw) {
    try {
      var next = JSON.parse(raw)
      if (next && typeof next === "object") info = next
    } catch (e) {}
  }

  // -------------------------------------------------------------- actions ---
  function runAction(args, name) {
    if (actionProc.running) return
    busyName = name || ""
    actionProc.command = [root.panelScript].concat(args)
    actionProc.running = true
  }

  // Launching switches to the instance's workspace, so the panel gets out
  // of the way first.
  function launch(inst) {
    if (busyName !== "") return
    root.close()
    runAction(["launch", inst.name], inst.name)
  }

  function focusInstance(inst) {
    if (busyName !== "") return
    root.close()
    runAction(["focus", inst.name], inst.name)
  }

  function stopInstance(inst) {
    if (busyName !== "") return
    runAction(["stop", inst.name], inst.name)
  }

  // The instance's macro, one player per window. Starting it leaves the
  // panel up: the player waits until that window has focus anyway.
  function toggleMacro(inst) {
    if (busyName !== "") return
    runAction(["macro-toggle", inst.name], inst.name)
  }

  function editList() {
    root.close()
    Quickshell.execDetached([root.panelScript, "edit"])
  }

  // ------------------------------------------------------- list editing ---
  function openEditor(name) {
    root.close()
    editing = name
  }

  function commitEdit(original, name, label, workspace, peer, macro, nested) {
    var fields = ["label=" + label, "workspace=" + workspace, "peer_id=" + peer, "macro=" + macro, "nested=" + (nested ? "1" : "0")]
    if (original === "") runAction(["add", "name=" + name].concat(fields), name)
    else runAction(["set", original].concat(fields), original)
    editing = ""
  }

  function removeInstance(name) {
    runAction(["remove", name], name)
    editing = ""
  }

  visible: installed
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: installed ? button.implicitHeight : 0

  Process {
    id: statusProc
    command: [root.panelScript]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateInfo(text) }
  }

  Process {
    id: actionProc
    onExited: {
      root.busyName = ""
      root.refresh()
    }
  }

  InstanceEditorWindow {
    anchorItem: button
    open: root.editing !== ""
    entry: root.editing === "+" ? ({}) : root.entryFor(root.editing)
    macros: root.macros
    busy: root.busyName !== ""
    fontFamily: root.fontFamily
    foreground: root.barForeground
    onDismissed: root.editing = ""
    onSaved: function (original, name, label, workspace, peer, macro, nested) {
      root.commitEdit(original, name, label, workspace, peer, macro, nested)
    }
    onRemoved: function (name) { root.removeInstance(name) }
  }

  // Background poll while closed; a quicker one while the panel is open so
  // "connected" flips show up promptly.
  Timer {
    interval: Math.max(2, root.setting("interval", 5)) * 1000
    running: !root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ------------------------------------------------------------------ bar ---
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showCount && root.connectedCount > 0 ? "󰢹 " + root.connectedCount : "󰢹"
    opacity: root.runningCount > 0 ? 1 : 0.5
    slotSize: root.showCount && root.connectedCount > 0 ? -1 : Style.bar.statusSlot
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  // ---------------------------------------------------------------- panel ---
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.installed
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: strings.t("title")
            meta: root.statusText
            foreground: root.barForeground
            fontFamily: root.fontFamily
            iconOpacity: root.runningCount > 0 ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: "󰢹"
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(4)
                Button {
                  iconText: "󰐕"
                  text: strings.t("action.add")
                  fontSize: Style.font.caption
                  bordered: true
                  foreground: root.barForeground
                  fontFamily: root.fontFamily
                  onClicked: root.openEditor("+")
                }
                Button {
                  iconText: "󰏫"
                  tooltipText: strings.t("action.edit")
                  fontSize: Style.font.caption
                  bordered: true
                  foreground: root.barForeground
                  fontFamily: root.fontFamily
                  onClicked: root.editList()
                }
              }
            }
          }

          PanelSeparator {
            visible: root.instances.length > 0
            foreground: root.barForeground
          }

          Repeater {
            model: root.instances
            InstanceRow {
              required property var modelData
              width: parent.width
              inst: modelData
            }
          }

          Text {
            visible: root.instances.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: strings.t("hint.emptyAdd")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.instances.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: strings.t("hint.login")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // One instance line: status dot · label + details · actions.
  component InstanceRow: Item {
    id: row
    property var inst: ({})

    readonly property bool running: inst.running === true
    readonly property bool connected: inst.connected === true
    readonly property bool rowBusy: root.busyName === inst.name
    readonly property string detail: {
      var parts = []
      var ws = inst.winWorkspace !== null && inst.winWorkspace !== undefined ? inst.winWorkspace : inst.workspace
      if (ws !== null && ws !== undefined) parts.push(strings.t("row.workspace").arg(Commons.I18n.formatNumber(ws)))
      if (inst.display) parts.push(strings.t("row.display").arg(String(inst.display)))
      if (connected) parts.push(strings.t("row.connected").arg(String(inst.host || "")))
      else if (running) parts.push(strings.t("row.idle"))
      else if (!inst.loggedIn) parts.push(strings.t("row.notLoggedIn"))
      if (macroState === "running") parts.push(strings.t("row.macroRunning").arg(String(inst.macro)))
      else if (macroState === "waiting") parts.push(strings.t("row.macroWaiting").arg(String(inst.macro)))
      else if (macroState === "missing") parts.push(strings.t("row.macroMissing").arg(String(inst.macro)))
      return parts.join("  ·  ")
    }
    readonly property string macroState: String(inst.macroState || "")
    readonly property bool macroOn: macroState === "running" || macroState === "waiting"
    readonly property bool hasMacro: running && macroState !== "" && macroState !== "missing"

    implicitHeight: Math.max(nameCol.implicitHeight, actions.implicitHeight) + Style.space(4)
    opacity: rowBusy ? 0.5 : 1

    Rectangle {
      id: statusDot
      width: Style.space(8)
      height: width
      radius: width / 2
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      color: row.connected ? root.barForeground : "transparent"
      border.width: row.connected ? 0 : 1
      border.color: row.running ? root.barForeground : root.faint
    }

    Column {
      id: nameCol
      anchors.left: statusDot.right
      anchors.leftMargin: Style.space(10)
      anchors.right: actions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: String(row.inst.label || row.inst.name || "")
        color: root.barForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: row.detail
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Button {
        iconText: "󰏫"
        tooltipText: strings.t("action.editInstance")
        fontSize: Style.font.caption
        bordered: true
        enabled: root.busyName === ""
        foreground: root.dim
        fontFamily: root.fontFamily
        onClicked: root.openEditor(row.inst.name)
      }

      Button {
        visible: row.hasMacro
        iconText: row.macroOn ? "󰓛" : "󰌌"
        text: row.macroOn ? strings.t("action.macroStop") : strings.t("action.macro")
        fontSize: Style.font.caption
        bordered: true
        active: row.macroOn
        enabled: !row.rowBusy && root.busyName === ""
        foreground: root.barForeground
        fontFamily: root.fontFamily
        onClicked: root.toggleMacro(row.inst)
      }

      Button {
        visible: row.running
        iconText: "󰍹"
        text: strings.t("action.show")
        fontSize: Style.font.caption
        bordered: true
        enabled: !row.rowBusy && root.busyName === ""
        foreground: root.barForeground
        fontFamily: root.fontFamily
        onClicked: root.focusInstance(row.inst)
      }

      Button {
        visible: row.running
        iconText: "󰓛"
        tooltipText: strings.t("action.stop")
        fontSize: Style.font.caption
        bordered: true
        enabled: !row.rowBusy && root.busyName === ""
        foreground: root.barForeground
        fontFamily: root.fontFamily
        onClicked: root.stopInstance(row.inst)
      }

      Button {
        visible: !row.running
        iconText: "󰐊"
        text: row.inst.peer_id ? strings.t("action.connect") : strings.t("action.launch")
        fontSize: Style.font.caption
        bordered: true
        enabled: root.hasBwrap && !row.rowBusy && root.busyName === ""
        foreground: root.barForeground
        fontFamily: root.fontFamily
        onClicked: root.launch(row.inst)
      }
    }
  }
}
