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
// With historyCount > 1 the last few combos stack as a fading history,
// keyviz-style.
//
// On first load the panel also appends a small guarded block to
// ~/.config/hypr/hyprland.lua that dofiles the capture script, so install
// is just add + enable; Hyprland auto-reloads its config on save. The
// block no-ops if the plugin folder is later removed.
Item {
  id: root

  property bool opened: false
  // History of recent combinations, newest first. Each entry is
  // { keys: [...], releasedAt: 0|ms }: 0 while it is the combo currently
  // being pressed; an epoch ms once a newer combo or a release superseded
  // it. The history tick prunes entries whose linger window passed. With
  // historyCount 1 this is exactly "the current combo, lingering".
  property var entries: []
  // How many combos stay on screen (1..5, default 1). Older entries fade
  // out via the entryOpacity() gradient; a count of 1 is the classic
  // current-combo-only display.
  property int historyCount: 1
  // How long the last combination stays on screen after the keys are
  // released (keyviz's "Duration"; keyviz defaults to 5000ms). The combo
  // lingers intact, then vanishes in one frame — no fade. 0 means "always
  // show": entries never expire, so the stack only shrinks when newer
  // combos push old ones out of the history window.
  property int lingerMs: 1000
  // Drop state written more than this long ago (e.g. from a previous shell
  // session after a restart) so a stale combo never sticks on screen.
  readonly property int maxStateAgeMs: 1500

  // Options read from config.json in the plugin folder (created with
  // defaults on first run, hot-reloaded on save):
  //   mode     "all" | "bindings" — bindings only shows combos with a
  //            modifier, ignoring plain typing (tutorial mode).
  //   position one of the six corners/edges: top/bottom + left/center/right.
  //            Middle positions were dropped — the stack anchors to the top
  //            (grows down) or the bottom (grows up) edge.
  //   margin   distance from the screen edge in px (default 67).
  //   lingerMs how long a released combo stays (default 1000).
  //   historyCount how many combos stack on screen (1..5, default 1).
  property string mode: "all"
  property string position: "bottom-center"
  property int margin: Style.space(67)
  readonly property var modLabels: ["Super", "Ctrl", "Alt", "Shift", "Menu", "AltGr"]

  // Options live at ~/.config/omarchy/key-visualizer.json rather than inside the
  // plugin folder on purpose: the shell watches every file under
  // ~/.config/omarchy/plugins/ and reloads all plugin code on any change, so
  // a config edit there would tear down and rebuild the panel. Editing this
  // file updates the display live.
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/key-visualizer.json"
  // Pre-1.3.1 config lived in the watched plugin dir; migrated once on first
  // load after the move.
  readonly property string legacyConfigPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/felixzsh.key-visualizer/config.json"

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
  readonly property int entryGap: Style.space(6)
  readonly property int chipPadX: Style.space(9)
  readonly property int chipPadY: Style.space(4)
  readonly property int chipHeight: Math.ceil(chipFontMetrics.height) + 2 * chipPadY

  // Stateless measurement: FontMetrics.advanceWidth(text) returns the
  // width for the given string directly. The previous shared TextMetrics
  // (text set imperatively inside the width bindings) went stale from the
  // third chip onwards, collapsing every container to single-char width.
  function chipWidth(label) {
    return Math.ceil(chipFontMetrics.advanceWidth(String(label))) + 2 * chipPadX
  }

  function rowWidth(keys) {
    var w = 0
    for (var i = 0; i < keys.length; i++) w += chipWidth(keys[i])
    return w + Math.max(0, keys.length - 1) * chipGap
  }

  // The card sizes to the widest history row, not the current one, so a
  // wider older entry never clips.
  function contentWidth() {
    var w = 0
    for (var i = 0; i < root.entries.length; i++) w = Math.max(w, rowWidth(root.entries[i].keys))
    return w
  }

  function contentHeight() {
    if (root.entries.length === 0) return 0
    return root.entries.length * root.chipHeight + (root.entries.length - 1) * root.entryGap
  }

  // Stack fade: the current combo is fully opaque and every older entry
  // steps down in opacity (tunable here). Clamped so the oldest row of a
  // 5-deep stack stays readable.
  function entryOpacity(pos) {
    return Math.max(0.25, 1 - pos * 0.22)
  }

  function sameKeys(a, b) {
    if (a.length !== b.length) return false
    var sa = a.slice().sort()
    var sb = b.slice().sort()
    for (var i = 0; i < sa.length; i++) if (sa[i] !== sb[i]) return false
    return true
  }

  function trimEntries(list) {
    while (list.length > root.historyCount) list.pop()
    return list
  }

  // Row order for the card. Top positions stack the history downward with
  // the newest combo on top; bottom positions stack it upward with the
  // newest on the bottom edge. Each item carries its original index so the
  // fade always measures distance from the newest combo.
  function displayModel() {
    var list = []
    var n = root.entries.length
    if (root.position.indexOf("bottom") !== -1) {
      for (var i = n - 1; i >= 0; i--) list.push({ entry: root.entries[i], pos: i })
    } else {
      for (var j = 0; j < n; j++) list.push({ entry: root.entries[j], pos: j })
    }
    return list
  }

  FontMetrics {
    id: chipFontMetrics
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
    var es = root.entries.slice()
    if (next.length === 0) {
      // All keys released: the newest combo enters its linger window; the
      // history tick prunes it once lingerMs passes.
      if (es.length > 0 && es[0].releasedAt === 0) {
        es[0] = { keys: es[0].keys, releasedAt: Date.now() }
      }
    } else if (es.length > 0 && root.sameKeys(es[0].keys, next)) {
      // Same combo re-pressed (or the state file re-fired): refresh it,
      // no duplicate history entry.
      es[0] = { keys: es[0].keys, releasedAt: 0 }
    } else {
      // A new combo arrived: the previous combo becomes a history entry
      // (it keeps lingering) and the new one takes the top of the stack.
      if (es.length > 0 && es[0].releasedAt === 0) {
        es[0] = { keys: es[0].keys, releasedAt: Date.now() }
      }
      es.unshift({ keys: next, releasedAt: 0 })
    }
    root.entries = root.trimEntries(es)
    root.opened = root.entries.length > 0
  }

  // Prunes entries whose linger window passed and caps the stack at
  // historyCount, keyviz's tick-style. With lingerMs 0 entries never
  // expire: the stack only shrinks when newer combos push old ones out.
  Timer {
    id: historyTick
    interval: 250
    repeat: true
    running: root.entries.length > 0
    onTriggered: {
      var now = Date.now()
      var kept = []
      for (var i = 0; i < root.entries.length; i++) {
        var e = root.entries[i]
        if (e.releasedAt === 0 || root.lingerMs <= 0 || now - e.releasedAt < root.lingerMs) kept.push(e)
      }
      root.entries = root.trimEntries(kept)
      root.opened = root.entries.length > 0
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
    root.entries = []
    root.opened = false
  }

  function setPaused(p) {
    if (p === root.paused) return
    // Always rewrite the flag with "0" or "1", never delete it: the
    // FileView watcher fires on content changes but not on deletion.
    var cmd = p
      ? "printf 1 > " + Util.shellQuote(root.pausePath)
      : "printf 0 > " + Util.shellQuote(root.pausePath)
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
    if (typeof cfg.position === "string" && cfg.position.length > 0) {
      // Pre-history versions had middle positions ("center-left" etc.);
      // they were dropped, so fold any leftover into the bottom row.
      var pos = cfg.position
      if (pos.indexOf("center") === 0 || pos.indexOf("middle") === 0) pos = "bottom" + pos.slice(pos.indexOf("-"))
      root.position = pos
    }
    if (isFinite(cfg.margin) && cfg.margin >= 0) root.margin = Math.round(cfg.margin)
    if (isFinite(cfg.lingerMs) && cfg.lingerMs >= 0) root.lingerMs = Math.round(cfg.lingerMs)
    if (isFinite(cfg.historyCount)) root.historyCount = Math.max(1, Math.min(5, Math.round(cfg.historyCount)))
  }

  function migrateConfig() {
    // First load with the new location: carry over values from the old
    // plugin-dir config (if any) and remove it, or seed the defaults.
    var defaults = '{"mode": "all", "position": "bottom-center", "margin": 67, "lingerMs": 1000, "historyCount": 1}'
    migrateProc.command = ["sh", "-c",
      "if [ -f " + Util.shellQuote(root.legacyConfigPath) + " ]; then "
      + "cp " + Util.shellQuote(root.legacyConfigPath) + " " + Util.shellQuote(root.configPath) + "; "
      + "rm -f " + Util.shellQuote(root.legacyConfigPath) + "; "
      + "else printf '%s\\n' '" + defaults + "' > " + Util.shellQuote(root.configPath) + "; fi"]
    migrateProc.running = true
  }

  Process {
    id: migrateProc
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
        if (root.configPath !== "" && text() === "") root.migrateConfig()
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
      visible: root.entries.length > 0
      width: card.borderLeft + root.cardPad + root.contentWidth() + root.cardPad + card.borderRight
      height: card.borderTop + root.cardPad + root.contentHeight() + root.cardPad + card.borderBottom
      x: {
        var p = root.position
        if (p.indexOf("left") !== -1) return root.margin
        if (p.indexOf("right") !== -1) return parent.width - width - root.margin
        return Math.round((parent.width - width) / 2)
      }
      // Top positions anchor the stack's first row at the top edge (the
      // history grows downward); bottom positions anchor the last row at
      // the bottom edge (the history grows upward).
      y: {
        var p = root.position
        if (p.indexOf("top") !== -1) return root.margin
        return parent.height - height - root.margin
      }
      color: Util.alpha(Color.popups.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      Column {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.cardPad
        anchors.leftMargin: card.borderLeft + root.cardPad
        anchors.bottomMargin: card.borderBottom + root.cardPad
        anchors.rightMargin: card.borderRight + root.cardPad
        spacing: root.entryGap

        Repeater {
          model: root.displayModel()

          delegate: Row {
            required property var modelData
            spacing: root.chipGap
            opacity: root.entryOpacity(modelData.pos)

            Repeater {
              model: modelData.entry.keys

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
  }
}
