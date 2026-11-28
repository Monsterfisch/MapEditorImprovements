-- The module's keys as Custom Hotkeys actions, where the player can rebind, clear or reset them
-- (Options > Custom Hotkeys). Only with a Custom Hotkeys that offers `registerAction`; there is no
-- dependency on it. The owners register while the module is enabled, before Custom Hotkeys'
-- afterInit closes the registration, and keep their own key handling for when the API is missing
-- or refuses an action.
--
-- A suggested key is the US-layout position of the key chosen in the module's options; Custom
-- Hotkeys leaves an action unbound when its suggestion collides with a binding the active preset
-- already has. Holds start unassigned because their module defaults use bare modifiers.

local labels = require("editor.action_labels")

local M = {}

M.ID_PREFIX = "ext.map-editor-improvements."
local ALT = 4

-- Set 1 scan codes of the module's key choices, { scan, extended }.
M.SCAN_CODES = {
  letter_a = { 0x1E }, letter_b = { 0x30 }, letter_c = { 0x2E }, letter_d = { 0x20 },
  letter_e = { 0x12 }, letter_f = { 0x21 }, letter_g = { 0x22 }, letter_h = { 0x23 },
  letter_i = { 0x17 }, letter_j = { 0x24 }, letter_k = { 0x25 }, letter_l = { 0x26 },
  letter_m = { 0x32 }, letter_n = { 0x31 }, letter_o = { 0x18 }, letter_p = { 0x19 },
  letter_q = { 0x10 }, letter_r = { 0x13 }, letter_s = { 0x1F }, letter_t = { 0x14 },
  letter_u = { 0x16 }, letter_v = { 0x2F }, letter_w = { 0x11 }, letter_x = { 0x2D },
  letter_y = { 0x15 }, letter_z = { 0x2C },
  digit_1 = { 0x02 }, digit_2 = { 0x03 }, digit_3 = { 0x04 }, digit_4 = { 0x05 },
  digit_5 = { 0x06 }, digit_6 = { 0x07 }, digit_7 = { 0x08 }, digit_8 = { 0x09 },
  digit_9 = { 0x0A }, digit_0 = { 0x0B },
  f1 = { 0x3B }, f2 = { 0x3C }, f3 = { 0x3D }, f4 = { 0x3E }, f5 = { 0x3F }, f6 = { 0x40 },
  f7 = { 0x41 }, f8 = { 0x42 }, f9 = { 0x43 }, f10 = { 0x44 }, f11 = { 0x57 }, f12 = { 0x58 },
  numpad_multiply = { 0x37 }, numpad_add = { 0x4E }, numpad_subtract = { 0x4A },
  numpad_decimal = { 0x53 }, numpad_divide = { 0x35, true },
  insert = { 0x52, true }, delete_key = { 0x53, true }, home = { 0x47, true },
  end_key = { 0x4F, true }, page_up = { 0x49, true }, page_down = { 0x51, true },
  caps_lock = { 0x3A },
}

---The Custom Hotkeys proxy when it offers module actions, else nil.
function M.provider()
  local hotkeys = modules ~= nil and modules["custom-hotkeys"] or nil
  if hotkeys ~= nil and type(hotkeys.registerAction) == "function" then return hotkeys end
  return nil
end

---The suggested binding for a key choice with these modifiers (Ctrl 1, Shift 2, Alt 4), or false:
---no key, a key without a scan code here, or Alt + F4, which belongs to Windows.
---@param name string|nil the key choice (`letter_p`, `f5`, ...)
---@param mods number|nil
function M.suggest(name, mods)
  local scan = name ~= nil and M.SCAN_CODES[name] or nil
  mods = mods or 0
  if scan == nil or (name == "f4" and mods & ALT ~= 0) then return false end
  return { scan = scan[1], extended = scan[2] == true, mods = mods }
end

---Register one action; true, or false after logging why Custom Hotkeys refused it.
---@param fallback string what the module does instead, for the log line
local function register(hotkeys, id, label, context, default, callback, fallback, release)
  local spec = { id = M.ID_PREFIX .. id, label = label, category = labels.category, context = context,
    default = default, callback = callback, release = release }
  local ok, result = pcall(hotkeys.registerAction, hotkeys, spec)
  if ok and result == true then return true end
  log(WARNING, string.format("Custom Hotkeys refused the action %s (%s); %s", spec.id, tostring(result), fallback))
  return false
end

-- An optional binding alongside the module's own key setting.
function M.hold(id)
  local held = false
  local hotkeys = M.provider()
  if hotkeys ~= nil then
    register(hotkeys, id, labels[id], { kind = "editor" }, false, function()
      held = true
      return true
    end, "the tool keeps its own key", function() held = false end)
  end
  return function() return held end
end

---The resource grid's toggle: in the map editor, and in games when the grid may show there. Both
---suggest Alt + the grid key. True when the editor action is registered.
---@param toggle fun(): boolean
function M.grid(hotkeys, key, inGames, toggle)
  local suggested = M.suggest(key, ALT)
  if not register(hotkeys, "grid-toggle", labels.grid, { kind = "editor" }, suggested, toggle,
      "the grid toggles with Alt + key") then
    return false
  end
  if inGames then
    register(hotkeys, "grid-toggle-game", labels.gridGame, { kind = "world" }, suggested, toggle,
      "the grid toggles in the map editor only")
  end
  return true
end

---The pipette's select key, suggested when it is on. True when registered.
---@param key string|nil the select key choice, nil when the key is off
---@param select fun(): boolean
function M.pipette(hotkeys, key, select)
  return register(hotkeys, "pipette", labels.pipette, { kind = "editor" }, M.suggest(key), select,
    "the pipette keeps its own key")
end

---Undo and redo, unbound: the buttons have no key.
---@param press fun(kind: string): boolean kind "undo" or "redo"
function M.history(hotkeys, press)
  for _, kind in ipairs({ "undo", "redo" }) do
    register(hotkeys, kind, labels[kind], { kind = "editor" }, false, function() return press(kind) end,
      "it stays on its button")
  end
end

return M
