-- Key Visualizer for Omarchy — shows the keys you press on screen.
--
-- This script runs inside the Hyprland Lua config, listens to the
-- compositor's `input.keyboard.key` event, and writes the currently
-- pressed combination to a small state file that the Quickshell plugin
-- (KeyVisualizer.qml) watches and renders.
--
-- Install: add one line to ~/.config/hypr/hyprland.lua (at the bottom):
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/omarchy.key-visualizer/key-visualizer.lua")
--
-- then reload Hyprland (`hyprctl reload`). Requires Hyprland with Lua
-- config support (0.56+).

local runtime = os.getenv("XDG_RUNTIME_DIR") or ""
if runtime == "" then runtime = "/tmp" end
local STATE_FILE = runtime .. "/omarchy-key-visualizer.json"

-- Modifier names, keyed by xkb keycode (evdev + 8).
local MODS = {
  [50] = "Shift",  [62] = "Shift",   -- Shift_L / Shift_R
  [37] = "Ctrl",   [105] = "Ctrl",   -- Control_L / Control_R
  [64] = "Alt",    [108] = "Alt",    -- Alt_L / Alt_R (AltGr on some layouts)
  [133] = "Super", [134] = "Super",  -- Super_L / Super_R
  [135] = "Menu",
  [109] = "AltGr",                   -- ISO_Level3_Shift
}

-- Display order for modifier chips.
local MOD_ORDER = { "Super", "Ctrl", "Alt", "Shift", "Menu", "AltGr" }

-- Keycap-style labels for keys that don't produce a printable character.
local KEYS = {
  [9] = "Esc", [22] = "Backspace", [23] = "Tab", [36] = "Enter", [66] = "Caps",
  [67] = "F1", [68] = "F2", [69] = "F3", [70] = "F4", [71] = "F5", [72] = "F6",
  [73] = "F7", [74] = "F8", [75] = "F9", [76] = "F10", [95] = "F11", [96] = "F12",
  [107] = "Print", [78] = "Scroll", [127] = "Pause",
  [118] = "Ins", [110] = "Home", [112] = "PgUp", [119] = "Del", [115] = "End", [117] = "PgDn",
  [111] = "Up", [113] = "Left", [116] = "Down", [114] = "Right",
  [65] = "Space",
  [77] = "Num", [106] = "KP/", [63] = "KP*", [82] = "KP-", [86] = "KP+",
  [104] = "KP Enter", [125] = "KP=",
  [79] = "KP7", [80] = "KP8", [81] = "KP9", [83] = "KP4", [84] = "KP5", [85] = "KP6",
  [87] = "KP1", [88] = "KP2", [89] = "KP3", [90] = "KP0", [91] = "KP.",
  [121] = "Mute", [122] = "Vol-", [123] = "Vol+",
  [94] = "\\", [51] = "\\",
}

-- Printable characters (US layout), unshifted.
local CHARS = {
  [10] = "1", [11] = "2", [12] = "3", [13] = "4", [14] = "5", [15] = "6",
  [16] = "7", [17] = "8", [18] = "9", [19] = "0", [20] = "-", [21] = "=",
  [24] = "q", [25] = "w", [26] = "e", [27] = "r", [28] = "t", [29] = "y",
  [30] = "u", [31] = "i", [32] = "o", [33] = "p", [34] = "[", [35] = "]",
  [38] = "a", [39] = "s", [40] = "d", [41] = "f", [42] = "g", [43] = "h",
  [44] = "j", [45] = "k", [46] = "l", [47] = ";", [48] = "'", [49] = "`",
  [52] = "z", [53] = "x", [54] = "c", [55] = "v", [56] = "b", [57] = "n",
  [58] = "m", [59] = ",", [60] = ".", [61] = "/",
}

-- Shifted counterparts for keys whose shifted form isn't just uppercase.
local SHIFTED = {
  [10] = "!", [11] = "@", [12] = "#", [13] = "$", [14] = "%", [15] = "^",
  [16] = "&", [17] = "*", [18] = "(", [19] = ")", [20] = "_", [21] = "+",
  [34] = "{", [35] = "}", [47] = ":", [48] = '"', [49] = "~",
  [59] = "<", [60] = ">", [61] = "?",
}

local pressed = {} -- keycode -> true
local combo = {}   -- ordered keycodes of non-modifier keys currently down

local function shift_down()
  return pressed[50] or pressed[62]
end

-- Modifiers other than Shift. A bare Shift folds into the character itself
-- (Shift + g renders as "G"), so it only shows as a chip alongside another
-- modifier (Super + Shift + G) or a non-character key (Shift + Enter).
local function non_shift_mods_down()
  local seen = {}
  for kc, down in pairs(pressed) do
    local name = MODS[kc]
    if down and name and name ~= "Shift" then seen[name] = true end
  end
  local out = {}
  for _, name in ipairs(MOD_ORDER) do
    if seen[name] then out[#out + 1] = name end
  end
  return out
end

local function any_printable()
  for _, kc in ipairs(combo) do
    if CHARS[kc] then return true end
  end
  return false
end

-- Label for one pressed key. `binding` is true when a modifier other than
-- Shift is held: the display switches to keycap style (uppercase letters)
-- which is what you want to read for keybinding tutorials.
local function key_label(kc, binding)
  local label = KEYS[kc]
  if label then return label end
  local ch = CHARS[kc]
  if not ch then return nil end
  if binding then return string.upper(ch) end
  if shift_down() then
    return SHIFTED[kc] or string.upper(ch)
  end
  return ch
end

local function labels()
  local parts = {}
  local ns = non_shift_mods_down()
  for _, m in ipairs(ns) do parts[#parts + 1] = m end
  local binding = #ns > 0
  -- A bare Shift folds into the character (Shift + g renders as "G") and
  -- only earns a chip next to another modifier or a non-character key.
  if shift_down() and (binding or not any_printable()) then
    parts[#parts + 1] = "Shift"
  end
  for _, kc in ipairs(combo) do
    local label = key_label(kc, binding)
    if label then parts[#parts + 1] = label end
  end
  return parts
end

local last_payload = ""
local function emit()
  local parts = labels()
  local payload = '{"keys":['
  if #parts > 0 then
    payload = payload .. '"' .. table.concat(parts, '","') .. '"'
  end
  payload = payload .. '],"t":' .. os.time() .. '}'
  if payload == last_payload then return end
  last_payload = payload
  local f = io.open(STATE_FILE, "w")
  if f then
    f:write(payload)
    f:close()
  end
end

-- state: 0 = released, 1 = pressed, 2 = repeat (ignored).
hl.on("input.keyboard.key", function(keycode, timeMs, state)
  if state == 2 then return end

  if state == 1 then
    pressed[keycode] = true
    if not MODS[keycode] then
      local found = false
      for _, kc in ipairs(combo) do
        if kc == keycode then found = true break end
      end
      if not found then combo[#combo + 1] = keycode end
    end
  else
    pressed[keycode] = false
    if not MODS[keycode] then
      for i, kc in ipairs(combo) do
        if kc == keycode then
          table.remove(combo, i)
          break
        end
      end
    end
  end

  emit()
end)
