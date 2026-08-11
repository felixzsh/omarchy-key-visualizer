# Omarchy Key Visualizer

A tiny [Omarchy](https://omarchy.org/) plugin that shows the keys you press
on screen. No keycap images, no animations — just the characters and
combinations, rendered with the shell's own styles, appearing while a key is
held and disappearing the moment it's released.

Built for keybinding tutorials and screencasts: Omarchy is a keybinding-heavy
desktop, so a combo like `Super + Shift + G` shows up as three small chips
at the bottom of the screen.

## How it works

| Piece          | Where it runs                              | What it does |
|----------------|--------------------------------------------|--------------|
| `key-visualizer.lua`| Hyprland Lua config (inside the compositor)| Listens to `input.keyboard.key`, tracks the pressed combo, writes it to `$XDG_RUNTIME_DIR/omarchy-key-visualizer.json` |
| `KeyVisualizer.qml`| Quickshell `omarchy-shell` (keep-loaded panel)| Watches the state file and renders the chips |

No background daemons, no special permissions, no extra packages: the
compositor is already the source of truth for keys, and the shell is already
running.

## Install

```bash
omarchy plugin add https://github.com/YOU/omarchy-keycaster
omarchy plugin enable omarchy.key-visualizer
```

Then load the capture script into Hyprland's Lua config. Add this line at the
bottom of `~/.config/hypr/hyprland.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/omarchy.key-visualizer/key-visualizer.lua")
```

Reload Hyprland:

```bash
hyprctl reload
```

The panel starts with the shell, so it works after the next login too.

### Requirements

- Hyprland with Lua config support (0.56+), as shipped by Omarchy.
- The plugin enabled in the shell (done above).

## Behavior

- **Typing** — shows just the character: `g`, `G`, `!`, `5`.
- **Modifier combos** — shows every modifier plus the key: `Super Shift G`,
  `Ctrl C`, `Super Enter`.
- **Non-printing keys** — labeled: `Esc`, `Tab`, `F1`, arrows, `Space`.
- Modifiers that produce the shifted character (`Shift` with a letter) are
  folded into the character itself: `Shift + 1` shows `!`.
- Key repeat is ignored; a held key shows once.
- The combo disappears immediately after the last key is released.

## Customize

Everything lives in the plugin directory
(`~/.config/omarchy/plugins/omarchy.key-visualizer/`); saved changes reload
automatically.

| Want to change...                 | Edit                                    |
|-----------------------------------|-----------------------------------------|
| How long a released combo lingers | `hideDelayMs` in `KeyVisualizer.qml` (default `120`) |
| Chip font / padding               | `chipFont`, `chipPadX/Y` in `KeyVisualizer.qml` |
| Key labels or layout mapping      | `KEYS` / `CHARS` / `SHIFTED` tables in `key-visualizer.lua` |

The key tables use **US layout** keycode mapping. Letters and digits match
most layouts; on other layouts, symbol keys (`;`, `[`, `ñ`, …) may show the
US glyph or fall back to the key name. Dead keys and compose sequences are
not expanded.

## Status

`omarchy-shell key-visualizer ping` — health check.

## Roadmap

- Layout-aware keysyms via `xkbcommon` instead of the static US table.
- Mouse button display.
- A pause toggle for presentations.

## License

MIT
