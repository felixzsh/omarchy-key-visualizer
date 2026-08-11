import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar control for the Key Visualizer. The keyboard glyph opens a small menu
// (KeyboardPanel, the native bar popup) with:
//   - Show keys  toggle that pauses/resumes the on-screen display
//   - Mode       all keys, or bindings only (combos with a modifier)
//   - Position   bottom / top / center of the screen
//
// The toggle writes a pause flag and the options write config.json — both
// files are watched by the display panel (KeyVisualizer.qml), so the menu and
// the overlay always agree, on every monitor. Follows the native bar-widget
// pattern (Panel + BarIconButton + KeyboardPanel), e.g. omarchy.audio.
Panel {
  id: root
  moduleName: "felixzsh.key-visualizer"
  // No IPC target: the display panel (KeyVisualizer.qml) owns the "key-visualizer"
  // target, so omarchy-shell key-visualizer toggle|pause|resume keeps working.

  // Mirrors of the files the display panel watches; these stay in sync via
  // the FileViews below.
  property bool paused: false
  property string mode: "all"
  property string position: "bottom-center"
  property int margin: 67
  property int lingerMs: 1000

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/felixzsh.key-visualizer"
  readonly property string pausePath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return (runtime && runtime.length > 0 ? runtime : "/tmp") + "/omarchy-key-visualizer.paused"
  }
  readonly property string configPath: root.pluginDir + "/config.json"

  // ------------------------------------------------------------- pause

  function setPaused(p) {
    if (p === root.paused) return
    var cmd = p
      ? "printf 1 > " + Util.shellQuote(root.pausePath)
      : "rm -f " + Util.shellQuote(root.pausePath)
    toggleProc.command = ["sh", "-c", cmd]
    toggleProc.running = true
  }

  Process {
    id: toggleProc
  }

  FileView {
    id: pauseFlag
    path: root.pausePath
    watchChanges: true
    printErrors: false
    onLoaded: root.paused = (text() === "1")
    onFileChanged: reload()
  }

  // ------------------------------------------------------------- config

  function applyConfig(raw) {
    var cfg = {}
    try { cfg = JSON.parse(raw || "{}") } catch (e) {}
    root.mode = cfg.mode === "bindings" ? "bindings" : "all"
    if (typeof cfg.position === "string" && cfg.position.length > 0) root.position = cfg.position
    if (isFinite(cfg.margin) && cfg.margin >= 0) root.margin = Math.round(cfg.margin)
    if (isFinite(cfg.lingerMs) && cfg.lingerMs >= 0) root.lingerMs = Math.round(cfg.lingerMs)
  }

  // Round-trips every option so a menu edit never drops values the display
  // panel or the user set directly in config.json.
  function writeConfig(update) {
    var cfg = {
      mode: root.mode,
      position: root.position,
      margin: root.margin,
      lingerMs: root.lingerMs
    }
    for (var k in update) cfg[k] = update[k]
    if (update.mode !== undefined) root.mode = update.mode
    if (update.position !== undefined) root.position = update.position
    writeProc.command = ["sh", "-c",
      "printf '%s\\n' '" + JSON.stringify(cfg) + "' > " + Util.shellQuote(root.configPath)]
    writeProc.running = true
  }

  Process {
    id: writeProc
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onFileChanged: reload()
  }

  // ------------------------------------------------------------- bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uF030C" // nf-md-keyboard_outline
    onPressed: function(b) {
      if (b === Qt.RightButton) return
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(250)
    contentHeight: menuColumn.implicitHeight + panel.padding * 2

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.spacing.lg

      // Show keys -----------------------------------------------------
      Item {
        width: parent.width
        height: showSwitch.implicitHeight

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Show keys"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.popups.text
        }

        ToggleSwitch {
          id: showSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: !root.paused
          foreground: Color.popups.text
          accent: Color.accent
          onToggled: root.setPaused(!checked)
        }
      }

      // Mode ----------------------------------------------------------
      Item {
        width: parent.width
        height: modeButtons.height

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Mode"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.popups.text
        }

        Row {
          id: modeButtons
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Button {
            text: "All keys"
            selected: root.mode !== "bindings"
            foreground: Color.popups.text
            accent: Color.accent
            onClicked: root.writeConfig({ mode: "all" })
          }
          Button {
            text: "Bindings"
            selected: root.mode === "bindings"
            foreground: Color.popups.text
            accent: Color.accent
            onClicked: root.writeConfig({ mode: "bindings" })
          }
        }
      }

      // Position ------------------------------------------------------
      Item {
        width: parent.width
        height: positionButtons.height

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Position"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.popups.text
        }

        Row {
          id: positionButtons
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Button {
            text: "Bottom"
            selected: root.position.indexOf("bottom") !== -1
            foreground: Color.popups.text
            accent: Color.accent
            onClicked: root.writeConfig({ position: "bottom-center" })
          }
          Button {
            text: "Top"
            selected: root.position.indexOf("top") !== -1
            foreground: Color.popups.text
            accent: Color.accent
            onClicked: root.writeConfig({ position: "top-center" })
          }
          Button {
            text: "Center"
            selected: root.position === "center"
            foreground: Color.popups.text
            accent: Color.accent
            onClicked: root.writeConfig({ position: "center" })
          }
        }
      }
    }
  }
}
