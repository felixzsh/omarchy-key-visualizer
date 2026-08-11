import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Key Visualizer — shows the keys you press as small chips at the bottom of
// the screen. The capture side is key-visualizer.lua (Hyprland Lua): it listens
// to the compositor's key events and writes the current combination to
// $XDG_RUNTIME_DIR/omarchy-key-visualizer.json. This panel watches that file
// and renders. No images, no animations: the combo appears while held and
// disappears the moment the keys are released.
Item {
  id: root

  property bool opened: false
  property var keys: []
  // Grace period after the last key is released. Small enough to feel
  // immediate, long enough that a quick tap is still readable.
  property int hideDelayMs: 120
  // Drop state written more than this long ago (e.g. from a previous shell
  // session after a restart) so a stale combo never sticks on screen.
  readonly property int maxStateAgeMs: 1500

  readonly property string statePath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return (runtime && runtime.length > 0 ? runtime : "/tmp") + "/omarchy-key-visualizer.json"
  }

  // ------------------------------------------------------------- layout

  readonly property int cardPad: Style.space(10)
  readonly property int chipGap: Style.space(8)
  readonly property int chipPadX: Style.space(9)
  readonly property int chipPadY: Style.space(4)
  readonly property int chipHeight: Math.ceil(chipTextMetrics.height) + 2 * chipPadY

  function chipWidth(label) {
    chipMetrics.text = String(label)
    return Math.ceil(chipMetrics.advanceWidth) + 2 * chipPadX
  }

  function contentWidth() {
    var w = 0
    for (var i = 0; i < root.keys.length; i++) w += chipWidth(root.keys[i])
    return w + Math.max(0, root.keys.length - 1) * chipGap
  }

  TextMetrics {
    id: chipMetrics
    font: chipFont
  }

  FontMetrics {
    id: chipTextMetrics
    font: chipFont
  }

  readonly property var chipFont: Qt.font({
    family: Style.font.family,
    pixelSize: Style.font.title,
    bold: true
  })

  // ------------------------------------------------------------- state

  function apply() {
    var next = []
    try {
      var parsed = JSON.parse(stateFile.text())
      if (parsed && Array.isArray(parsed.keys)) {
        var age = Math.floor(Date.now() / 1000) - (parsed.t || 0)
        if (age <= Math.ceil(root.maxStateAgeMs / 1000)) next = parsed.keys
      }
    } catch (e) {}
    root.keys = next
    if (next.length === 0) {
      hideTimer.restart()
    } else {
      hideTimer.stop()
      root.opened = true
    }
  }

  Timer {
    id: hideTimer
    interval: root.hideDelayMs
    onTriggered: root.opened = false
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.apply()
    onFileChanged: reload()
  }

  // Lifecycle required for panel plugins: summoning is a no-op because the
  // display is driven by the state file; hiding closes the window.
  function open(payloadJson) {}
  function close() { root.opened = false }

  IpcHandler {
    target: "key-visualizer"
    function ping(): string { return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
  }

  // ------------------------------------------------------------- display

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "key-visualizer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only surface: never block clicks to the desktop below.
    mask: Region {}

    BorderSurface {
      id: card
      visible: root.keys.length > 0
      width: card.borderLeft + root.cardPad + root.contentWidth() + root.cardPad + card.borderRight
      height: card.borderTop + root.cardPad + root.chipHeight + root.cardPad + card.borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(67)
      color: Util.alpha(Color.popups.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      Row {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.cardPad
        anchors.leftMargin: card.borderLeft + root.cardPad
        anchors.bottomMargin: card.borderBottom + root.cardPad
        anchors.rightMargin: card.borderRight + root.cardPad
        spacing: root.chipGap

        Repeater {
          model: root.keys

          delegate: Rectangle {
            required property string modelData
            width: root.chipWidth(modelData)
            height: root.chipHeight
            radius: Math.max(3, Style.cornerRadius - 1)
            color: Util.alpha(Color.popups.text, 0.10)
            border.color: Util.alpha(Color.popups.text, 0.35)
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: parent.modelData
              font: root.chipFont
              color: Color.popups.text
            }
          }
        }
      }
    }
  }
}
