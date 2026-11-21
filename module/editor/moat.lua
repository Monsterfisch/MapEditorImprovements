local layout = require("editor.layout")
local templates = layout.templates
local K = layout.K
local C = layout.C
local AOB_GAME_MODE = layout.AOB_GAME_MODE
local GAME_MODE_OPERAND = layout.GAME_MODE_OPERAND
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local readCallTarget = memory.readCallTarget
local rd32 = memory.rd32
local rd8 = memory.rd8
local patchJump = require("editor.menu_install").patchJump

-- The moat panel's choice decides the mode the editor's moat click sends.
function C.patchMoatClick(self, data)
  local site = scan(K.AOB_MOAT_CLICK, "the moat click")
  patchJump(self, site, K.MOAT_CLICK_SIZE, core.allocateAssembly(templates.moatClick, {
    MOAT_MODE = data.moatMode, PLANNED = K.MOAT_PLANNED, MOAT_TOOL = K.MOAT_TOOL, BACK = site + K.MOAT_CLICK_SIZE,
  }))
end

-- setTerrain's moat modes: permanent moat (mode 4), and a removal (mode 3) that only touches
-- moat tiles and leaves their ground as it is.
function C.patchMoatModes(self, permanent, keepGround)
  local base = scan(K.AOB_MOAT_MODE, "the moat modes")
  local D = K.MOAT_MODE
  local site = base + D.site
  local plan = site + D.size
  local nextMode = plan + (rd8(site + D.size - 1) & 0xFF)
  expectBytes(plan, { 0x8B, 0x4D, 0x0C, 0x8B, 0x55, 0xE0, 0x8B, 0x84, 0x8A }, "the planned moat")
  expectBytes(nextMode + D.decoration, { 0xC6, 0x81 }, "the moat decoration")
  expectBytes(plan + D.done, { 0xE9 }, "the moat branch's end")
  patchJump(self, site, D.size, core.allocateAssembly(templates.moatModes, {
    PERMANENT = permanent and K.MOAT_PERMANENT_MODE or 0xFFFFFFFF, KEEP_GROUND = keepGround and 1 or 0,
    LOGIC = rd32(plan + D.logic), HEIGHT = rd32(base + D.height), DECORATION = rd32(nextMode + D.decoration + 2),
    MOAT_FLAGS = K.MOAT_FLAGS, DUG = K.MOAT_DUG_FLAG, GROUND = K.GROUND_HEIGHT,
    UNMOAT = ~K.MOAT_FLAGS & 0xFFFFFFFF, UNMOAT_PLAIN = ~(K.MOAT_FLAGS | K.PLAIN2_FLAG) & 0xFFFFFFFF,
    CLEAR_DATA = readCallTarget(nextMode, D.clear, "clearMoatDataAtTile"),
    DONE = plan + D.done + 5 + rd32(plan + D.done + 1), PLAN = plan, NEXT = nextMode,
  }))
end

-- Moat on marsh in the map editor: the marsh stays under it.
function C.patchMoatMarsh(self)
  local site = scan(K.AOB_MOAT_MARSH, "the moat's marsh test") + K.MOAT_MARSH.site
  patchJump(self, site, K.MOAT_MARSH.size, core.allocateAssembly(templates.moatMarsh, {
    GAME_MODE = rd32(scan(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND), MAP_EDITOR = K.MAP_EDITOR,
    BACK = site + K.MOAT_MARSH.size,
  }))
end

return true
