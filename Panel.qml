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
  property int historyCount: 1
  property bool comboMode: false
  // Manual fine-tune offsets (px) written by the D-pad; reset when a preset
  // position is chosen from the dropdown.
  property int offsetX: 0
  property int offsetY: 0
  // How many pixels a D-pad click moves the card.
  readonly property int nudgeStep: 4
  // The display's state file: the D-pad injects a virtual arrow key here so
  // the visualizer renders the move like a real keypress.
  readonly property string statePath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return (runtime && runtime.length > 0 ? runtime : "/tmp") + "/omarchy-key-visualizer.json"
  }

  // Config lives outside the plugin folder (the shell reloads all plugin
  // code on any file change under ~/.config/omarchy/plugins/), so editing it
  // updates the display live instead of restarting the plugin.
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/key-visualizer.json"
  // Persisted next to the config so the pause state survives restarts
  // (the runtime dir is wiped on reboot).
  readonly property string pausePath: Quickshell.env("HOME") + "/.config/omarchy/key-visualizer.paused"

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
    if (isFinite(cfg.historyCount)) root.historyCount = Math.max(1, Math.min(5, Math.round(cfg.historyCount)))
    root.comboMode = cfg.comboMode === true
    if (isFinite(cfg.offsetX)) root.offsetX = Math.round(cfg.offsetX)
    if (isFinite(cfg.offsetY)) root.offsetY = Math.round(cfg.offsetY)
  }

  // Round-trips every option so a menu edit never drops values the display
  // panel or the user set directly in config.json.
  function writeConfig(update) {
    var cfg = {
      mode: root.mode,
      position: root.position,
      margin: root.margin,
      lingerMs: root.lingerMs,
      historyCount: root.historyCount,
      comboMode: root.comboMode,
      offsetX: root.offsetX,
      offsetY: root.offsetY
    }
    for (var k in update) cfg[k] = update[k]
    if (update.mode !== undefined) root.mode = update.mode
    if (update.position !== undefined) root.position = update.position
    if (update.historyCount !== undefined) root.historyCount = update.historyCount
    if (update.comboMode !== undefined) root.comboMode = update.comboMode
    if (update.offsetX !== undefined) root.offsetX = update.offsetX
    if (update.offsetY !== undefined) root.offsetY = update.offsetY
    writeProc.command = ["sh", "-c",
      "printf '%s\\n' '" + JSON.stringify(cfg) + "' > " + Util.shellQuote(root.configPath)]
    writeProc.running = true
  }

  // Nudge the card by one step and feed a virtual arrow key to the visualizer
  // through its state file, so the move shows up in the history like a real
  // keypress: we write the arrow down, then release it a moment later.
  function nudge(dx, dy) {
    var nx = Math.max(-2000, Math.min(2000, root.offsetX + dx * root.nudgeStep))
    var ny = Math.max(-2000, Math.min(2000, root.offsetY + dy * root.nudgeStep))
    root.writeConfig({ offsetX: nx, offsetY: ny })
    var arrow = dx < 0 ? "←" : dx > 0 ? "→" : dy < 0 ? "↑" : "↓"
    var now = Math.floor(Date.now() / 1000)
    nudgeKeyProc.command = ["sh", "-c",
      "printf '%s' '" + JSON.stringify({ keys: [arrow], t: now }) + "' > " + Util.shellQuote(root.statePath)]
    nudgeKeyProc.running = true
    nudgeReleaseTimer.interval = 120
    nudgeReleaseTimer.restart()
  }

  // Press-and-hold helpers for the D-pad: a tap moves once; holding starts the
  // repeat timer so the card keeps moving (and the arrow keeps feeding the
  // visualizer) until the button is released.
  function startNudge(dx, dy) {
    root.nudge(dx, dy)
    nudgeHoldTimer.dx = dx
    nudgeHoldTimer.dy = dy
    nudgeHoldTimer.interval = 280
    nudgeHoldTimer.repeat = false
    nudgeHoldTimer.restart()
  }

  function stopNudge() {
    nudgeHoldTimer.interval = 280
    nudgeHoldTimer.repeat = false
    nudgeHoldTimer.stop()
  }

  Process {
    id: nudgeKeyProc
  }

  Timer {
    id: nudgeReleaseTimer
    interval: 120
    repeat: false
    onTriggered: {
      var now = Math.floor(Date.now() / 1000)
      nudgeKeyProc.command = ["sh", "-c",
        "printf '%s' '" + JSON.stringify({ keys: [], t: now }) + "' > " + Util.shellQuote(root.statePath)]
      nudgeKeyProc.running = true
    }
  }

  // While a D-pad button is held: the first move happens on press (in
  // startNudge), then after a short delay this timer repeats every 60ms.
  Timer {
    id: nudgeHoldTimer
    interval: 280
    repeat: false
    property int dx: 0
    property int dy: 0
    onTriggered: {
      root.nudge(dx, dy)
      interval = 60
      repeat = true
      restart()
    }
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

      // Combo mode -----------------------------------------------------
      // Game mode: combo counter + score with escalating effects (pulse,
      // hue, screen shake). Chords with modifiers build the combo; plain
      // characters are hits that only add score.
      Item {
        width: parent.width
        height: comboSwitch.implicitHeight

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Combo mode"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.popups.text
        }

        ToggleSwitch {
          id: comboSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.comboMode
          foreground: Color.popups.text
          accent: Color.accent
          onToggled: root.writeConfig({ comboMode: !root.comboMode })
        }
      }

      // Mode ----------------------------------------------------------
      Item {
        width: parent.width
        height: modeButtons.height

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Filter"
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
          { value: "bottom-left", label: "Bottom left" },
          { value: "bottom-center", label: "Bottom center" },
          { value: "bottom-right", label: "Bottom right" }
        ]
        onChanged: function(v) { root.writeConfig({ position: v, offsetX: 0, offsetY: 0 }) }
      }

      // Fine-tune D-pad: 4px per click; holding a button keeps moving (the
      // move repeats after a short delay). Each nudge also feeds a virtual
      // arrow key to the visualizer, so the move shows up in its history.
      // The Button draws the look; a transparent MouseArea on top captures
      // press/release so a held button can repeat.
      RowLayout {
        width: parent.width
        spacing: Style.spacing.xs

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.spacing.controlHeight
          Button {
            anchors.fill: parent
            text: "←"
            tooltipText: "Move left"
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            onPressed: root.startNudge(-1, 0)
            onReleased: root.stopNudge()
          }
        }

        ColumnLayout {
          spacing: Style.spacing.xxs
          Layout.fillWidth: true
          Repeater {
            model: [
              { dx: 0, dy: -1, label: "↑", tip: "Move up" },
              { dx: 0, dy: 1, label: "↓", tip: "Move down" }
            ]
            delegate: Item {
              Layout.fillWidth: true
              Layout.preferredHeight: Math.round(Style.spacing.controlHeight / 2)
              Button {
                anchors.fill: parent
                text: modelData.label
                tooltipText: modelData.tip
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                onPressed: root.startNudge(modelData.dx, modelData.dy)
                onReleased: root.stopNudge()
              }
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.spacing.controlHeight
          Button {
            anchors.fill: parent
            text: "→"
            tooltipText: "Move right"
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            onPressed: root.startNudge(1, 0)
            onReleased: root.stopNudge()
          }
        }
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
            // Field works in seconds (matches the label); the config stays in
            // ms, so we convert at the boundary. Step is 1s, "never hide" at 0.
            value: Math.round(root.lingerMs / 1000)
            from: 0
            to: 10
            stepSize: 1
            // 0 = always show (keep the last combo until the next key).
            onModified: function(v) { root.writeConfig({ lingerMs: v * 1000 }) }
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

      // History --------------------------------------------------------
      // How many combos stack on screen (1..5). Older entries fade out;
      // the stack direction follows the position (top grows down, bottom
      // grows up) and is not configurable.
      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Text {
          text: "History (count)"
          color: Qt.darker(Color.popups.text, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        NumberField {
          id: historyField
          label: ""
          fieldWidth: Style.space(110)
          value: root.historyCount
          from: 1
          to: 5
          stepSize: 1
          onModified: function(v) { root.writeConfig({ historyCount: v }) }
        }
      }
    }
  }
}
