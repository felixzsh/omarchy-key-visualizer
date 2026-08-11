# Omarchy Key Visualizer

A tiny [Omarchy](https://omarchy.org/) plugin that shows the keys you press
on screen. No keycap images, no animations — just the characters and
combinations, rendered with the shell's own styles, appearing while a key is
held and lingering briefly after release.

Built for keybinding tutorials and screencasts: Omarchy is a keybinding-heavy
desktop, so a combo like `Super + Shift + G` shows up as three small chips
at the bottom of the screen.

## How it works

| Piece          | Where it runs                              | What it does |
|----------------|--------------------------------------------|--------------|
| `key-visualizer.lua`| Hyprland Lua config (inside the compositor)| Listens to `input.keyboard.key`, tracks the pressed combo, writes it to `$XDG_RUNTIME_DIR/omarchy-key-visualizer.json` |
| `KeyVisualizer.qml`| Quickshell `omarchy-shell` (keep-loaded panel)| Watches the state file and renders the chips |
| `BarWidget.qml`| Quickshell bar (per monitor)               | Keyboard glyph that pauses/resumes the display |

No background daemons, no special permissions, no extra packages: the
compositor is already the source of truth for keys, and the shell is already
running.

## Install

Validate the folder first (optional but handy for plugin authors):

```bash
omarchy plugin validate ./omarchy-keycaster
```

Then add it — a local path works as well as a git URL (`plugin add` clones
with git, and `git clone` accepts local paths):

```bash
omarchy plugin add /path/to/omarchy-keycaster --enable
# or once published:
# omarchy plugin add https://github.com/YOU/omarchy-keycaster --enable
```

`--enable` enables it right away; without it, enable later with
`omarchy plugin enable felixzsh.key-visualizer`. The plugin is a panel and a bar
widget: the panel shows the keys, and the bar widget is a toggle — enable
prompts for its bar section (or pass `--section right`). If you added from a
local path, `omarchy plugin update felixzsh.key-visualizer` pulls your local
changes into the installed copy.

That's the whole install: on first load the panel appends a small guarded
block to `~/.config/hypr/hyprland.lua` that loads the capture script into
Hyprland's Lua config, and Hyprland auto-reloads on save. Nothing else to
do — no manual edits, no `hyprctl reload`.

### Requirements

- Hyprland with Lua config support (0.56+), as shipped by Omarchy.
- The plugin enabled in the shell (done above).

## Bar widget

The keyboard glyph in the bar (right section by default) toggles the
display: click to pause, click again to resume. While paused the glyph dims
and keys stay off the screen — handy for presentations. The state is a flag
file both the bar and the panel watch, so it stays in sync across monitors
and survives shell restarts. You can also drive it over IPC:

```bash
omarchy-shell key-visualizer toggle
omarchy-shell key-visualizer pause
omarchy-shell key-visualizer resume
omarchy-shell key-visualizer paused   # true | false
```

Move it with `omarchy bar move felixzsh.key-visualizer --section left` (or
right/center).

## Behavior

- **Typing** — shows just the character: `g`, `G`, `!`, `5`.
- **Modifier combos** — shows every modifier plus the key: `Super Shift G`,
  `Ctrl C`, `Super Enter`.
- **Non-printing keys** — labeled: `Esc`, `Tab`, `F1`, arrows, `Space`.
- Modifiers that produce the shifted character (`Shift` with a letter) are
  folded into the character itself: `Shift + 1` shows `!`.
- Key repeat is ignored; a held key shows once.
- After the last key is released the combo lingers briefly (1s by default,
  keyviz-style "Duration") and then vanishes in one frame — no fade.
- In `mode: "bindings"` only combos with a modifier are shown; plain typing
  stays off screen.

## Customize

On first load the panel writes `config.json` into the plugin directory
(`~/.config/omarchy/plugins/felixzsh.key-visualizer/config.json`) with these
defaults; edit it and the display updates on save:

```json
{
  "mode": "all",
  "position": "bottom-center",
  "margin": 67,
  "lingerMs": 1000
}
```

| Option      | Values                                             | Default         |
|-------------|----------------------------------------------------|-----------------|
| `mode`      | `all` or `bindings` (only combos with a modifier)  | `all`           |
| `position`  | `bottom-center`, `top-center`, `center`, `top-left`, `bottom-right`, … | `bottom-center` |
| `margin`    | px from the screen edge                            | `67`            |
| `lingerMs`  | ms a released combo stays (keyviz defaults to `5000`) | `1000`       |

Deeper tweaks still live in the QML/Lua sources:

| Want to change...                 | Edit                                    |
|-----------------------------------|-----------------------------------------|
| Chip font / padding               | `chipFont`, `chipPadX/Y` in `KeyVisualizer.qml` |
| Key labels or layout mapping      | `KEYS` / `CHARS` / `SHIFTED` tables in `key-visualizer.lua` |

The key tables use **US layout** keycode mapping. Letters and digits match
most layouts; on other layouts, symbol keys (`;`, `[`, `ñ`, …) may show the
US glyph or fall back to the key name. Dead keys and compose sequences are
not expanded.

## Status

`omarchy-shell key-visualizer ping` — health check.
`omarchy-shell key-visualizer state` — `open` while a combo is on screen.

## Roadmap

- Layout-aware keysyms via `xkbcommon` instead of the static US table.
- Mouse button display.
- Per-monitor placement.

## License

MIT
