import QtQuick
import QtQuick.Layouts
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

  // Config lives outside the plugin folder (the shell reloads all plugin
  // code on any file change under ~/.config/omarchy/plugins/), so editing it
  // updates the display live instead of restarting the plugin.
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/key-visualizer.json"
  readonly property string pausePath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return (runtime && runtime.length > 0 ? runtime : "/tmp") + "/omarchy-key-visualizer.paused"
  }

  // ------------------------------------------------------------- pause

  function setPaused(p) {
    if (p === root.paused) return
    // The flag file is always rewritten with "0" or "1" — never deleted:
    // the FileView watcher fires on content changes but not on deletion, so
    // a removed flag would leave the toggle stuck.
    var cmd = p
      ? "printf 1 > " + Util.shellQuote(root.pausePath)
      : "printf 0 > " + Util.shellQuote(root.pausePath)
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
    text: "\uDB80\uDF0C" // md-keyboard (U+F030C, PUA-A: \u takes 4 hex digits, so \uF030C would parse as \uF030 + "C" = camera + C)
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
          // ToggleSwitch does not flip `checked` itself — it only emits
          // toggled() and the caller owns the value. Flip the real state;
          // the checked binding follows.
          onToggled: root.setPaused(!root.paused)
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
      Dropdown {
        id: positionDropdown
        width: parent.width
        label: "Position"
        value: root.position
        options: [
          { value: "top-left", label: "Top left" },
          { value: "top-center", label: "Top center" },
          { value: "top-right", label: "Top right" },
          { value: "center-left", label: "Middle left" },
          { value: "center-center", label: "Middle center" },
          { value: "center-right", label: "Middle right" },
          { value: "bottom-left", label: "Bottom left" },
          { value: "bottom-center", label: "Bottom center" },
          { value: "bottom-right", label: "Bottom right" }
        ]
        onChanged: function(v) { root.writeConfig({ position: v }) }
      }

      // Linger --------------------------------------------------------
      // Label above, styled exactly like Dropdown's "Position" label;
      // the field takes the left half and the never-hide legend the right
      // half (only while the value is 0). The spacer keeps the field fixed.
      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          text: "Linger (seconds)"
          color: Qt.darker(Color.popups.text, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        RowLayout {
          width: parent.width
          spacing: Style.spacing.md

          NumberField {
            id: lingerField
            label: ""
            fieldWidth: Style.space(110)
            Layout.preferredWidth: Style.space(110)
            value: root.lingerMs
            from: 0
            to: 10000
            stepSize: 500
            // 0 = always show (keep the last combo until the next key).
            onModified: function(v) { root.writeConfig({ lingerMs: v }) }
          }

          Item {
            Layout.fillWidth: true
          }

          Text {
            visible: root.lingerMs === 0
            text: "never hide"
            color: Qt.darker(Color.popups.text, 1.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }
  }
}
