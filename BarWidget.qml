import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar toggle for the Key Visualizer: a keyboard glyph that pauses/resumes the
// on-screen key display. Pause state is a flag file in the runtime dir
// ($XDG_RUNTIME_DIR/omarchy-key-visualizer.paused) that the panel and every bar
// widget instance watch, so one click updates all of them. The widget is
// dimmed while paused.
BarWidget {
  id: root
  moduleName: "felixzsh.key-visualizer"

  property bool paused: false

  readonly property string pausePath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return (runtime && runtime.length > 0 ? runtime : "/tmp") + "/omarchy-key-visualizer.paused"
  }

  function toggle() {
    var cmd = root.paused
      ? "rm -f " + Util.shellQuote(root.pausePath)
      : "printf 1 > " + Util.shellQuote(root.pausePath)
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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uF030C" // nf-md-keyboard_outline
    fontSize: Style.font.icon
    horizontalMargin: 6
    active: !root.paused
    dimmed: root.paused
    tooltipText: root.paused
      ? "Key Visualizer — paused (click to resume)"
      : "Key Visualizer — click to pause"
    onPressed: function() { root.toggle() }
  }
}
