-- Key Visualizer - Hyprland hook
--
-- Mirrors the currently held keys into a small JSON file inside the current
-- user's private runtime directory; Quickshell's KeyVisualizer.qml watches
-- that file with a FileView and renders the overlay from it.
--
-- This is the post-hardening rewrite of the file introduced in 89cd794
-- ("security hardening"), which broke key capture on Hyprland's embedded
-- Lua environment:
--
--   1. The runtime-directory and symlink validation no longer shells out to
--      `stat`/`test` (those checks failed inside Hyprland's Lua VM and
--      silently disabled capture or the initial state-file write). Instead
--      we require XDG_RUNTIME_DIR to be *exactly* /run/user/<uid>, where
--      <uid> is the effective UID read in Lua. The OS creates
--      /run/user/<uid> as a mode-0700 directory owned by <uid> and never
--      as a symlink, so the exact-path check provides the same guarantee
--      without any shell access.
--
--   2. The state file is updated *in place* (open "w", write, close). The
--      hardening pass wrote a temp file and os.rename()d it over the state
--      file, which replaced the inode; Quickshell's FileView stays attached
--      to the old inode and therefore never saw the key-state updates.
--
--   3. The state file is seeded with an empty JSON object when this hook
--      loads and kept at mode 0600, so FileView always has a stable,
--      private file to watch.

local STATE_FILE_NAME = "key-visualizer.json"

local function log(msg)
  pcall(print, "[key-visualizer] " .. msg)
end

--------------------------------------------------------------------------
-- Runtime-directory validation (pure Lua; no stat/test shelling)
--------------------------------------------------------------------------

-- Read the effective UID. It is the only shell access the hook performs,
-- and it is wrapped so that a restricted Lua build simply disables the
-- hook instead of crashing Hyprland's startup.
local function effectiveUid()
  local ok, handle = pcall(io.popen, "id -u 2>/dev/null")
  if not ok or type(handle) ~= "file" then
    return nil
  end
  local out = handle:read("*a") or ""
  handle:close()
  return tonumber(out:match("%d+"))
end

-- Returns the absolute path of the state file, or nil when the runtime
-- directory is not the current user's private one.
local function resolveStatePath()
  local uid = effectiveUid()
  if not uid then
    log("could not determine the effective uid; hook disabled")
    return nil
  end

  local expected = string.format("/run/user/%d", uid)
  local runtimeDir = os.getenv("XDG_RUNTIME_DIR")
  if runtimeDir == nil or runtimeDir == "" then
    runtimeDir = expected -- XDG spec default
  end

  if runtimeDir ~= expected then
    log(("XDG_RUNTIME_DIR %q is not the current user's %q; hook disabled"):format(runtimeDir, expected))
    return nil
  end

  return expected .. "/" .. STATE_FILE_NAME
end

-- Lua has no portable chmod(2). The path is built exclusively from uid
-- digits, so a plain `chmod 600` is safe; when os.execute is unavailable
-- we degrade gracefully - the file still lives in the user's private,
-- 0700-only directory.
local function enforceMode0600(path)
  if type(os.execute) ~= "function" then
    return
  end
  pcall(os.execute, string.format("chmod 600 %s", path))
end

-- Seed the state file so Quickshell's FileView has a file to attach to as
-- soon as the shell starts.
local function seedStateFile(path)
  local f = io.open(path, "w")
  if not f then
    log(("cannot create state file %q; hook disabled"):format(path))
    return false
  end
  f:write("{}")
  f:close()
  enforceMode0600(path)
  return true
end

--------------------------------------------------------------------------
-- State file updates (in place, stable inode)
--------------------------------------------------------------------------

local held = {} -- key names currently held, in press order
local heldSet = {}

local function jsonString(s)
  return '"' .. (s:gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"'
end

local function writeState(eventType, keyName, path)
  local keys = {}
  for i = 1, #held do
    keys[i] = jsonString(held[i])
  end

  -- In-place update: opening the *existing* file with "w" truncates it
  -- without replacing it, so the inode stays stable and FileView keeps
  -- delivering changes. Never replace the file via a temp file +
  -- os.rename() here.
  local f = io.open(path, "w")
  if not f then
    -- The file went away; recreate it (restoring 0600) and retry once.
    if not seedStateFile(path) then
      return
    end
    f = io.open(path, "w")
    if not f then
      log(("cannot write state file %q; capture disabled"):format(path))
      return
    end
  end

  f:write(string.format(
    '{"keys":[%s],"event":%s,"key":%s,"ts":%d}',
    table.concat(keys, ","),
    jsonString(eventType),
    jsonString(keyName),
    os.time()
  ))
  f:flush()
  f:close()
end

--------------------------------------------------------------------------
-- Key event capture
--------------------------------------------------------------------------

local function keyLabel(event)
  -- Best-effort key naming across Hyprland's Lua bindings.
  local e = event
  if type(event.getKeyboardEvent) == "function" then
    local ok, ke = pcall(event.getKeyboardEvent, event)
    if ok and type(ke) == "table" then
      e = ke
    end
  end
  local code = e.keycode or e.code or 0
  if type(e.getKeyCode) == "function" then
    local ok, v = pcall(e.getKeyCode, e)
    if ok then
      code = v or code
    end
  end
  if type(hs) == "table" and type(hs.keycodes) == "table" and type(hs.keycodes.map) == "table" then
    local name = hs.keycodes.map[code]
    if type(name) == "string" and name ~= "" then
      return name
    end
  end
  return string.format("Key%d", code)
end

local function onKeyEvent(event, path)
  local down = true
  if type(event.isKeyDown) == "function" then
    local ok, v = pcall(event.isKeyDown, event)
    if ok then
      down = v == true
    end
  end
  local name = keyLabel(event)
  if down then
    if not heldSet[name] then
      heldSet[name] = true
      held[#held + 1] = name
    end
  else
    heldSet[name] = nil
    for i = #held, 1, -1 do
      if held[i] == name then
        table.remove(held, i)
        break
      end
    end
  end
  writeState(down and "down" or "up", name, path)
end

--------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------

local statePath = resolveStatePath()
if not statePath then
  return
end

if not seedStateFile(statePath) then
  return
end

if type(hs) ~= "table" or type(hs.eventtap) ~= "table" or type(hs.eventtap.new) ~= "function" then
  log("hs.eventtap unavailable; state file seeded but key capture disabled")
  return
end

local ok, err = pcall(function()
  local tap = hs.eventtap.new({
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.keyUp,
  }, function(event)
    onKeyEvent(event, statePath)
  end)
  tap:enable()
end)

if not ok then
  log(("eventtap failed to start: %s"):format(tostring(err)))
  return
end

log(("state file ready: %s"):format(statePath))
