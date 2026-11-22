-- The map drawing's patch site, kept here for every feature that does its work once a frame on
-- the game screen: the resource grid, the tree preview, the herds and groups line, and the height
-- tool settings going back to their defaults outside the editor.
--
-- The one call of renderMap is followed by the floater pass and then
--   +16  mov eax,[A]                     (5 bytes)
--   +21  mov ecx,[B]                     (6 bytes)
--   +27  push eax / push ecx / mov ecx,viewport / call ...
-- A jump at the first load goes to a stub that calls each feature's routine in a fixed order (the
-- grid first, so the tree preview is drawn over it), does both loads and goes on behind them. A
-- routine is entered with `call`, keeps every register (the flags are free: nothing after the site
-- reads them before setting them) and returns with `ret`.
--
-- Without the grid only the second load is taken, as the editor has always done, so the first one
-- stays free for Resource Grid Overlay 1.1, which takes it when it is installed on its own. While
-- that module is active the grid stays off here and commit() waits until every module has been
-- enabled, because that module's pattern also reads the second load.

local menu_install = require("editor.menu_install")
local MODULE_NAME = require("editor.layout").MODULE_NAME

local AOB = "89 2D ? ? ? ? E8 ? ? ? ? E8 ? ? ? ? ? ? ? ? ? 8B 0D ? ? ? ? 50 51 B9 ? ? ? ? E8 ? ? ? ?"
local LOAD_EAX, LOAD_EAX_SIZE = 16, 5   -- mov eax,[A]
local LOAD_ECX, LOAD_ECX_SIZE = 21, 6   -- mov ecx,[B]
local AFTER_LOADS = 27                  -- push eax / push ecx
local VIEWPORT = 30                     -- operand of mov ecx,viewport
local OPCODE_LOAD_EAX = 0xA1
local ORDER = { "grid", "editor" }

local M = {}
local site = nil
local routines = {}

local function readAddress(address)
  return core.readInteger(address) & 0xFFFFFFFF
end

local function expect(address, bytes, purpose)
  for index, byte in ipairs(bytes) do
    if (core.readByte(address + index - 1) & 0xFF) ~= byte then
      error(string.format("%s: %s at 0x%X is not the code this module knows", MODULE_NAME, purpose, address))
    end
  end
end

---Find the site once: one match, the instructions around the loads as expected.
---@return table site { base, viewport, firstLoadFree }
function M.resolve()
  if site ~= nil then return site end
  local ok, base = pcall(core.AOBScan, AOB)
  if not ok or base == nil or base == 0 then
    error(MODULE_NAME .. ": could not find the map drawing")
  end
  local again = core.scanForAOB(AOB, base + 1)
  if again ~= nil and again ~= 0 then
    error(string.format("%s: the map drawing matches twice (0x%X, 0x%X)", MODULE_NAME, base, again))
  end
  expect(base + LOAD_ECX, { 0x8B, 0x0D }, "the map drawing")
  expect(base + AFTER_LOADS, { 0x50, 0x51, 0xB9 }, "the map drawing")
  site = {
    base = base,
    viewport = readAddress(base + VIEWPORT),
    -- Another module (Resource Grid Overlay 1.1 on its own) may already have taken the first load.
    firstLoadFree = (core.readByte(base + LOAD_EAX) & 0xFF) == OPCODE_LOAD_EAX,
  }
  return site
end

---A feature's routine, run every frame on the game screen once install() has put the site in.
---@param name string "grid" or "editor"
---@param routine number address of the routine
function M.add(name, routine)
  routines[name] = routine
end

---Put the site in with every routine added so far. Called once, at the end of enable.
---@param self table the module, for the saved bytes disable() puts back
---@return boolean installed
function M.install(self)
  if next(routines) == nil then return false end
  local S = M.resolve()
  local grid = routines.grid ~= nil
  if grid and not S.firstLoadFree then
    error(MODULE_NAME .. ": the map drawing's first load has been changed by another module")
  end
  local lines = {}
  for _, name in ipairs(ORDER) do
    if routines[name] ~= nil then lines[#lines + 1] = "call " .. name:upper() end
  end
  local at, size = S.base + LOAD_ECX, LOAD_ECX_SIZE
  if grid then
    at, size = S.base + LOAD_EAX, LOAD_EAX_SIZE + LOAD_ECX_SIZE
    lines[#lines + 1] = "mov eax,[LOAD_A]"
  end
  lines[#lines + 1] = "mov ecx,[LOAD_B]"
  lines[#lines + 1] = "jmp BACK"
  local values = {
    LOAD_A = readAddress(S.base + LOAD_EAX + 1),
    LOAD_B = readAddress(S.base + LOAD_ECX + 2),
    BACK = S.base + AFTER_LOADS,
    GRID = routines.grid, EDITOR = routines.editor,
  }
  local used = {}
  for name, value in pairs(values) do
    if table.concat(lines, "\n"):find("%f[%w_]" .. name .. "%f[^%w_]") then used[name] = value end
  end
  menu_install.patchJump(self, at, size, core.allocateAssembly(table.concat(lines, "\n") .. "\n", used))
  routines = {}
  log(INFO, string.format("%s: map drawing at 0x%X (%d bytes)%s", MODULE_NAME, at, size,
    grid and ", with the resource grid" or ""))
  return true
end

---Put the site in now, or, while Resource Grid Overlay 1.1 is active, once every module has been
---enabled: that module reads the whole call site, the second load included, when it is enabled
---and stays off if it has changed, so the site goes in after it in either load order.
---@param self table the module
---@param onProblem fun(problem: any) told when the site could not be put in
---@return string when "now" or "afterInit"
function M.commit(self, onProblem)
  local function run()
    local ok, problem = pcall(M.install, self)
    if not ok then onProblem(problem) end
  end
  if modules ~= nil and modules["resource-grid-overlay"] ~= nil then
    hooks.registerHookCallback("afterInit", run)
    return "afterInit"
  end
  run()
  return "now"
end

return M
