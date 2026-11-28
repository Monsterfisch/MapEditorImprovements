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
-- stays free for the separate Resource Grid Overlay module (1.0.0 and 1.1.x take it when it is
-- installed on its own). While that module is active the grid stays off here and commit() waits
-- until every module has been enabled, because that module's pattern also reads the second load.

local menu_install = require("editor.menu_install")
local memory = require("editor.memory")
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
local running = {}
local gridActivate

local function readAddress(address)
  return memory.rd32(address) & 0xFFFFFFFF
end

---Find the site once: one match, the instructions around the loads as expected.
---@return table site { base, viewport, firstLoadFree }
function M.resolve()
  if site ~= nil then return site end
  local base = memory.scanUnique(AOB, "the map drawing")
  memory.expectBytes(base + LOAD_ECX, { 0x8B, 0x0D }, "the map drawing")
  memory.expectBytes(base + AFTER_LOADS, { 0x50, 0x51, 0xB9 }, "the map drawing")
  site = {
    base = base,
    viewport = readAddress(base + VIEWPORT),
    -- Another module (Resource Grid Overlay on its own) may already have taken the first load.
    firstLoadFree = (memory.rd8(base + LOAD_EAX) & 0xFF) == OPCODE_LOAD_EAX,
  }
  return site
end

---A feature's routine, run every frame on the game screen once install() has put the site in.
---@param name string "grid" or "editor"
---@param routine number address of the routine
function M.add(name, routine, activate)
  routines[name] = routine
  if name == "grid" then gridActivate = activate end
end

---Take a routine back before the site goes in (its feature did not finish enabling).
---@param name string
function M.remove(name)
  routines[name] = nil
  if name == "grid" then gridActivate = nil end
end

---Whether the site is in and runs this feature's routine.
---@param name string
---@return boolean
function M.running(name)
  return running[name] == true
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
  menu_install.patchJump(self, at, size, core.allocateAssembly(table.concat(lines, "\n") .. "\n", {
    LOAD_A = readAddress(S.base + LOAD_EAX + 1),
    LOAD_B = readAddress(S.base + LOAD_ECX + 2),
    BACK = S.base + AFTER_LOADS,
    GRID = routines.grid, EDITOR = routines.editor,
  }))
  if grid then gridActivate() end
  for name in pairs(routines) do running[name] = true end
  routines = {}
  return true
end

---Put the site in now, or, while Resource Grid Overlay is active, once every module has been
---enabled: that module reads the whole call site, the second load included, when it is enabled
---and stays off if it has changed, so the site goes in after it in either load order.
---@param self table the module
---@param handoff fun() called after the drawing hook is installed
---@param onProblem fun(problem: any, installed: boolean) reports installation or handoff failure
---@return string when "now" or "afterInit"
function M.commit(self, handoff, onProblem)
  local function run()
    if routines.grid ~= nil then
      local first = #(self.saved or {}) + 1
      local ok, installed = pcall(M.install, self)
      if ok and installed then
        local handedOff, problem = pcall(handoff)
        if not handedOff then onProblem(problem, true) end
        return
      end
      local drawingSafe = true
      local problems = { tostring(installed) }
      if self.saved ~= nil then
        for index = #self.saved, first, -1 do
          local saved = self.saved[index]
          local restored, problem = pcall(core.writeCode, saved.address, saved.bytes)
          if restored then
            table.remove(self.saved, index)
          else
            problems[#problems + 1] = string.format("could not restore 0x%X (%s)", saved.address, tostring(problem))
            if saved.address == site.base + LOAD_EAX then drawingSafe = false end
          end
        end
      end
      M.remove("grid")
      log(ERROR, "The map editor resource grid is off: " .. table.concat(problems, ". "))
      if not drawingSafe then return end
    end
    local installed = false
    local ok, problem = pcall(function()
      installed = M.install(self)
      if installed then handoff() end
    end)
    if not ok then onProblem(problem, installed) end
  end
  if modules ~= nil and modules["resource-grid-overlay"] ~= nil then
    hooks.registerHookCallback("afterInit", run)
    return "afterInit"
  end
  run()
  return "now"
end

return M
