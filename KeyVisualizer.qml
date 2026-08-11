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
// lingers briefly after release (like keyviz's Duration), then vanishes.
//
// On first load the panel also appends a small guarded block to
// ~/.config/hypr/hyprland.lua that dofiles the capture script, so install
// is just add + enable; Hyprland auto-reloads its config on save. The
// block no-ops if the plugin folder is later removed.
Item {
  id: root

  property bool opened: false
  property var keys: []
  // How long the last combination stays on screen after the keys are
  // released (keyviz's "Duration"; keyviz defaults to 5000ms). The combo
  // lingers intact, then vanishes in one frame — no fade.
  property int lingerMs: 1000
  // Drop state written more than this long ago (e.g. from a previous shell
  // session after a restart) so a stale combo never sticks on screen.
  readonly property int maxStateAgeMs: 1500

  // Options read from config.json in the plugin folder (created with
  // defaults on first run, hot-reloaded on save):
  //   mode     "all" | "bindings" — bindings only shows combos with a
  //            modifier, ignoring plain typing (tutorial mode).
  //   position bottom-center (default) or any top/bottom + left/center/
  //            right combination, keyviz-style.
  //   margin   distance from the screen edge in px (default 67).
  //   lingerMs how long a released combo stays (default 1000).
  property string mode: "all"
  property string position: "bottom-center"
  property int margin: Style.space(67)
  readonly property var modLabels: ["Super", "Ctrl", "Alt", "Shift", "Menu", "AltGr"]

  property var manifest: ({})
  readonly property string configPath: {
    var dir = root.manifest && root.manifest.__sourceDir ? root.manifest.__sourceDir : ""
    return dir ? dir + "/config.json" : ""
  }

  readonly property string statePath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return (runtime && runtime.length > 0 ? runtime : "/tmp") + "/omarchy-key-visualizer.json"
  }

  // Pause flag shared with the bar widget: while the file holds "1" the
  // display is frozen (keys are ignored). The bar button writes/removes the
  // file; both sides watch it, so a click on any monitor updates all of them.
  property bool paused: false
  readonly property string pausePath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return (runtime && runtime.length > 0 ? runtime : "/tmp") + "/omarchy-key-visualizer.paused"
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
    if (!root.paused) {
      try {
        var parsed = JSON.parse(stateFile.text())
        if (parsed && Array.isArray(parsed.keys)) {
          var age = Math.floor(Date.now() / 1000) - (parsed.t || 0)
          if (age <= Math.ceil(root.maxStateAgeMs / 1000)) next = parsed.keys
        }
      } catch (e) {}
    }    if (next.length > 0 && root.mode === "bindings") {
      var hasMod = false
      for (var i = 0; i < next.length; i++) {
        if (root.modLabels.indexOf(next[i]) !== -1) { hasMod = true; break }
      }
      if (!hasMod) next = []
    }
    if (next.length === 0) {
      // Keys were released: keep the last combo on screen for the linger
      // window, then clear it. A fresh press restarts the timer below.
      hideTimer.restart()
    } else {
      hideTimer.stop()
      root.keys = next
      root.opened = true
    }
  }

  Timer {
    id: hideTimer
    interval: root.lingerMs
    onTriggered: {
      root.keys = []
      root.opened = false
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.apply()
    onFileChanged: reload()
  }

  FileView {
    id: pauseFile
    path: root.pausePath
    watchChanges: true
    printErrors: false
    onLoaded: root.paused = (text() === "1")
    onFileChanged: reload()
  }

  onPausedChanged: if (root.paused) {
    hideTimer.stop()
    root.keys = []
    root.opened = false
  }

  function setPaused(p) {
    if (p === root.paused) return
    var cmd = p
      ? "printf 1 > " + Util.shellQuote(root.pausePath)
      : "rm -f " + Util.shellQuote(root.pausePath)
    pauseToggleProc.command = ["sh", "-c", cmd]
    pauseToggleProc.running = true
  }

  Process {
    id: pauseToggleProc
  }

  // --------------------------------------------------------------- options

  function applyConfig(raw) {
    var cfg = {}
    try { cfg = JSON.parse(raw || "{}") } catch (e) {}
    root.mode = cfg.mode === "bindings" ? "bindings" : "all"
    if (typeof cfg.position === "string" && cfg.position.length > 0) root.position = cfg.position
    if (isFinite(cfg.margin) && cfg.margin >= 0) root.margin = Math.round(cfg.margin)
    if (isFinite(cfg.lingerMs) && cfg.lingerMs >= 0) root.lingerMs = Math.round(cfg.lingerMs)
  }

  function seedConfig() {
    var defaults = '{"mode": "all", "position": "bottom-center", "margin": 67, "lingerMs": 1000}'
    seedConfigProc.command = ["sh", "-c",
      "printf '%s\\n' '" + defaults + "' > " + Util.shellQuote(root.configPath)]
    seedConfigProc.running = true
  }

  Process {
    id: seedConfigProc
  }

  property bool configSeeded: false

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.applyConfig(text())
      // First run: write the defaults so the file is discoverable and the
      // options can be tuned without hunting for them. Guarded because the
      // shell injects `manifest` after instantiation, which re-fires this.
      if (!root.configSeeded) {
        root.configSeeded = true
        if (root.configPath !== "" && text() === "") root.seedConfig()
      }
    }
    onFileChanged: reload()
  }

  // ------------------------------------------------- capture hook injection
  //
  // The capture script (key-visualizer.lua) must run inside Hyprland's Lua
  // config, but the plugin cannot register itself there — the user owns
  // hyprland.lua. On first load we append a small guarded block that
  // dofiles the script; Hyprland auto-reloads its config on save, so the
  // whole install is: add + enable. The block is idempotent and no-ops if
  // the plugin folder is later removed, so uninstalling never breaks the
  // config.

  readonly property string captureMarker: "-- [key-visualizer] capture hook"
  readonly property string captureBlock: {
    var lines = [
      "",
      "-- [key-visualizer] capture hook (managed by the plugin; safe to remove)",
      'local kc_path = os.getenv("HOME") .. "/.config/omarchy/plugins/felixzsh.key-visualizer/key-visualizer.lua"',
      'local kc_file = io.open(kc_path, "r")',
      'if kc_file then kc_file:close(); dofile(kc_path) end',
      ""
    ]
    return lines.join("\n")
  }

  function maybeInjectCapture(raw) {
    if (!raw) return
    if (raw.indexOf(root.captureMarker) !== -1) return
    var kept = []
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length; i++) {
      // Drop an older plain dofile line (manual installs, previous versions)
      // so the block below is the only reference and stays upgradeable.
      if (lines[i].indexOf("key-visualizer.lua") !== -1) continue
      kept.push(lines[i])
    }
    console.log("key-visualizer: injecting capture hook into hyprland.lua")
    hyprConfFile.setText(kept.join("\n") + root.captureBlock)
    injectReloadTimer.start()
  }

  Timer {
    id: injectReloadTimer
    interval: 400
    onTriggered: reloadProc.running = true
  }

  Process {
    id: reloadProc
    command: ["hyprctl", "reload"]
  }

  FileView {
    id: hyprConfFile
    path: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"
    watchChanges: true
    printErrors: false
    onLoaded: root.maybeInjectCapture(text())
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
    function paused(): string { return root.paused ? "true" : "false" }
    function pause(): string { root.setPaused(true); return "ok" }
    function resume(): string { root.setPaused(false); return "ok" }
    function toggle(): string { root.setPaused(!root.paused); return "ok" }
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
      x: {
        var p = root.position
        if (p.indexOf("left") !== -1) return root.margin
        if (p.indexOf("right") !== -1) return parent.width - width - root.margin
        return Math.round((parent.width - width) / 2)
      }
      y: {
        var p = root.position
        if (p.indexOf("top") !== -1) return root.margin
        if (p.indexOf("bottom") !== -1) return parent.height - height - root.margin
        return Math.round((parent.height - height) / 2)
      }
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
