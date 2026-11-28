local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
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

-- The rock number the editor places and previews follows the variant row.
local function patchRocks(self, G, data)
  local function rockId(site, size, tail)
    return core.allocateAssembly(templates.rockId .. tail .. "\njmp BACK\n", {
      ROCK_LOCK = data.rockLock, SIZE = G.chosenRockSize, VARIANT = G.rockVariant,
      EXTRA_VARIANT = K.EXTRA_VARIANT, EXTRA_ID = K.EXTRA_ID, PARAM3 = G.rockParam, MOUSE_Y = G.mouseTileY,
      BACK = site + size,
    })
  end
  patchJump(self, G.rockPlace, K.ROCK_PLACE.size, rockId(G.rockPlace, K.ROCK_PLACE.size, "mov [PARAM3],ecx"))
  patchJump(self, G.rockPreview, K.ROCK_PREVIEW.size, rockId(G.rockPreview, K.ROCK_PREVIEW.size, "mov edx,[MOUSE_Y]"))
end

-- With the invisible rocks check box on, placeRock gets rock 0 instead of a new rock.
function C.patchInvisibleRocks(self, data)
  local site = scan(K.AOB_CREATE_ROCK_CALL, "the rock placement's createRock call") + K.CREATE_ROCK_CALL
  local stub = core.allocateAssembly(templates.invisibleRocks, {
    FLAG = data.invisibleRocks, CREATE_ROCK = readCallTarget(site, 0, "createRock"),
    ROCK_ARGUMENTS = K.CREATE_ROCK_ARGUMENTS,
  })
  self.saved = self.saved or {}
  table.insert(self.saved, { address = site, bytes = core.readBytes(site, 5) })
  core.writeCode(site, { 0xE8, core.itob(core.getRelativeAddress(site, stub, -5)) })
end

-- The eraser frees an invisible rock's tile the way removing a rock frees the rock's tiles: the
-- rock flag and the tile's rock number go.
function C.eraseSites()
  if C.erasers ~= nil then return C.erasers end
  local sites = memory.scanAll(K.AOB_ERASE_ROCK, K.ERASE_SITES + 1)
  if #sites ~= K.ERASE_SITES then error(MODULE_NAME .. ": the eraser is not the one this module knows") end
  C.erasers = sites
  return sites
end

-- The eraser's map tables (tile flags, organism numbers), read once: the eraser choice patches
-- the instruction this pattern ends in, the addresses themselves stay.
function C.eraseTables()
  if C.tables == nil then
    local found = scan(K.AOB_ERASE_TABLES, "the eraser's map tables")
    C.tables = { flags = rd32(found + K.ERASE_TABLES.flags), numbers = rd32(found + K.ERASE_TABLES.numbers) }
  end
  return C.tables
end

function C.patchEraser(self)
  local tables = C.eraseTables()
  for _, found in ipairs(C.eraseSites()) do
    local site = found + K.ERASE_ROCK.site
    patchJump(self, site, K.ERASE_ROCK.size, core.allocateAssembly(templates.eraseInvisible, {
      ROCK_BASE = rd32(found + K.ERASE_ROCK.base), FLAGS = tables.flags,
      NUMBERS = tables.numbers, KEEP_FLAGS = (~K.ROCK_TILE_FLAG) & 0xFFFFFFFF,
      REMOVE_ROCK = readCallTarget(site, K.ERASE_ROCK.call, "removeRock"), BACK = site + K.ERASE_ROCK.size,
    }))
  end
end

-- The eraser takes every tree and shrub off a tile, not only the one the tile names: shrubs
-- that were stacked there stay in the tree list otherwise, invisible and for good.
function C.patchEraseStacks(self, G)
  for _, found in ipairs(C.eraseSites()) do
    local site = found + K.ERASE_TREE.site
    expectBytes(site, K.ERASE_TREE.bytes, "the eraser's tree branch")
    patchJump(self, site, K.ERASE_TREE.size, core.allocateAssembly(templates.eraseStack, {
      REMOVE_TREE = readCallTarget(site, K.ERASE_TREE.call, "removeTree"), LANDSCAPE = G.landscape,
      FIRST_TREE = G.firstTree, TREE_SIZE = G.treeSize, TREE_SLOTS = G.treeSlots,
      TILE_FROM_IN_USE = K.TREE_TILE_FROM_IN_USE, BACK = site + K.ERASE_TREE.size,
    }))
  end
end

-- Foam and small waves: setTerrain leaves the brush area river for them (see K.TERRAIN_LAND).
function C.patchRiverDecorations(self)
  local site = scan(K.AOB_TERRAIN_LAND, "the terrain brush") + K.TERRAIN_LAND.site
  patchJump(self, site, K.TERRAIN_LAND.size, core.allocateAssembly(templates.riverDecorations, {
    RIVER = K.RIVER_TERRAIN, SKIP_LAND = site + K.TERRAIN_LAND.size + (rd8(site + K.TERRAIN_LAND.size - 1) & 0xFF),
    BACK = site + K.TERRAIN_LAND.size,
  }))
end

-- Foam goes on ocean tiles too (they become river with foam).
function C.patchFoamOnSea(self)
  local D = K.DECORATION_TILE
  local site = scan(K.AOB_DECORATION_TILE, "the decoration's tile test") + D.site
  patchJump(self, site, D.size, core.allocateAssembly(templates.foamOnSea, {
    FLAGS = rd32(site + D.flags), RIVER = K.RIVER_TERRAIN, FOAM = K.FOAM, SEA = K.SEA_TILE,
    TILE_OK = site + D.size + (rd8(site + D.size - 1) & 0xFF), BACK = site + D.size,
  }))
end

-- Every brush gets its full shape: the walk marks the cursor tile as visited before it starts.
-- In the map editor only: the walk also gives the area of collateral damage in the game.
function C.patchBrushShape(self)
  local site = scan(K.AOB_BRUSH_START, "the brush walk")
  patchJump(self, site, K.BRUSH_START_SIZE, core.allocateAssembly(templates.brushStart, {
    MARKS = rd32(scan(K.AOB_BRUSH_MARKS, "the brush walk's marks") + K.BRUSH_MARKS),
    GAME_MODE = rd32(scan(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND), MAP_EDITOR = K.MAP_EDITOR,
    BACK = site + K.BRUSH_START_SIZE,
  }))
end

---------------------------------------------------------------------------------------
-- Undo and redo
---------------------------------------------------------------------------------------

return {
  patchRocks = patchRocks,
}
