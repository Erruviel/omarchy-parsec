import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Add or edit one Parsec instance without opening instances.json. A
// screen-centred overlay with exclusive keyboard focus, like the macro
// editor: the bar popup is too narrow for a form and does not take typing.
PanelWindow {
  id: root

  required property Item anchorItem
  property bool open: false
  // The instance being edited; an object without a name means "add".
  property var entry: ({})
  property var macros: []
  property string fontFamily: Style.font.family
  property color foreground: Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: Color.urgent
  property bool busy: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  readonly property bool adding: !entry || !entry.name
  readonly property string originalName: adding ? "" : String(entry.name)
  readonly property bool running: !adding && entry.running === true
  property bool pendingNested: true
  property string pendingMacro: ""

  signal saved(string original, string name, string label, string workspace, string peer, string macro, bool nested)
  signal removed(string name)
  signal dismissed()

  property bool seeded: false
  function trySeed() {
    if (seeded || !open) return
    seed()
    seeded = true
  }
  function seed() {
    nameField.text = adding ? "" : String(entry.name)
    labelField.text = adding ? "" : String(entry.label || "")
    workspaceField.text = adding || entry.workspace === null || entry.workspace === undefined ? "" : String(entry.workspace)
    peerField.text = adding ? "" : String(entry.peer_id || "")
    pendingMacro = adding ? "" : String(entry.macro || "")
    pendingNested = adding ? true : !!entry.display
  }
  function commit() {
    saved(originalName, nameField.text.trim(), labelField.text.trim(), workspaceField.text.trim(),
          peerField.text.trim(), pendingMacro, pendingNested)
  }
  function macroOptions() {
    var opts = [{ value: "", label: strings.t("editor.noMacro") }]
    for (var i = 0; i < macros.length; i++) opts.push({ value: String(macros[i]), label: String(macros[i]) })
    return opts
  }

  onOpenChanged: {
    if (open) {
      trySeed()
      Qt.callLater(function () { if (root.open) (root.adding ? nameField : labelField).forceActiveFocus() })
    } else {
      seeded = false
    }
  }
  onEntryChanged: trySeed()

  visible: open
  screen: anchorItem && anchorItem.QsWindow.window ? anchorItem.QsWindow.window.screen : null
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "erruviel-parsec-editor"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  Item {
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: root.dismissed()

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.72)
      MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
    }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(48), Style.space(440))
      height: Math.min(parent.height - Style.space(48), card.contentTopInset + card.contentBottomInset + column.implicitHeight)
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
      padding: Style.space(20)
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: column
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(12)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.adding ? strings.t("editor.addTitle") : strings.t("editor.editTitle").arg(String(root.entry.label || root.entry.name || ""))
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideMiddle
        }

        Field {
          id: nameField
          label: strings.t("editor.name")
          hint: root.adding ? strings.t("editor.nameHint") : strings.t("editor.nameFixed")
          enabled: root.adding
          opacity: root.adding ? 1 : 0.6
        }

        Field {
          id: labelField
          label: strings.t("editor.label")
          hint: strings.t("editor.labelHint")
        }

        Row {
          width: parent.width
          spacing: Style.space(6)
          readonly property real cell: (width - spacing) / 2

          Field {
            id: workspaceField
            width: parent.cell
            label: strings.t("editor.workspace")
            hint: strings.t("editor.workspaceHint")
          }

          Field {
            id: peerField
            width: parent.cell
            label: strings.t("editor.peer")
            hint: strings.t("editor.peerHint")
          }
        }

        Column {
          width: parent.width
          spacing: 3
          Text {
            textFormat: Text.PlainText
            text: strings.t("editor.macro")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Dropdown {
            width: parent.width
            showLabel: false
            value: root.pendingMacro
            options: root.macroOptions()
            fontFamily: root.fontFamily
            onChanged: function (v) { root.pendingMacro = v }
          }
        }

        Toggle {
          width: parent.width
          label: strings.t("editor.nested")
          description: root.pendingNested ? strings.t("editor.nestedOn") : strings.t("editor.nestedOff")
          checked: root.pendingNested
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.pendingNested = !root.pendingNested
        }

        Text {
          visible: root.running
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: strings.t("editor.runningNote")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item {
          width: parent.width
          height: actions.implicitHeight

          Button {
            visible: !root.adding && root.originalName !== "main"
            anchors.left: parent.left
            iconText: "󰩹"
            text: strings.t("editor.remove")
            tooltipText: root.running ? strings.t("editor.removeBlocked") : ""
            bordered: true
            enabled: !root.running && !root.busy
            foreground: root.urgent
            fontFamily: root.fontFamily
            onClicked: root.removed(root.originalName)
          }

          Row {
            id: actions
            anchors.right: parent.right
            spacing: Style.space(8)

            Button {
              text: strings.t("editor.cancel")
              bordered: true
              foreground: root.dim
              fontFamily: root.fontFamily
              onClicked: root.dismissed()
            }

            Button {
              iconText: "󰆓"
              text: strings.t("editor.save")
              bordered: true
              enabled: !root.busy && (!root.adding || nameField.text.trim() !== "")
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.commit()
            }
          }
        }
      }
    }
  }

  component Field: Column {
    id: field
    property string label: ""
    property string hint: ""
    property alias text: input.text
    property alias enabled: input.enabled

    width: parent.width
    spacing: 3

    Text {
      width: field.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: field.label + (field.hint ? "  ·  " + field.hint : "")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    TextField {
      id: input
      width: field.width
      foreground: root.foreground
      font.family: root.fontFamily
      onAccepted: root.commit()
    }
  }
}
