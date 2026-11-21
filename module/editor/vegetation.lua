local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local SHRUB_COMMANDS = layout.SHRUB_COMMANDS
local APPLE_COMMAND = layout.APPLE_COMMAND
local APPLE_TYPE = layout.APPLE_TYPE
local K = layout.K
local C = layout.C
local TREE_TYPE_START = layout.TREE_TYPE_START
local PLACE_TREE = layout.PLACE_TREE
local STAGES = layout.STAGES
local MAX_STAGE = layout.MAX_STAGE
local PLACED_STAGE = layout.PLACED_STAGE
local TREES_IN_LANDSCAPE = layout.TREES_IN_LANDSCAPE
local TREE = layout.TREE
local LYING_FELLED = layout.LYING_FELLED
local LAST_TREE_TYPE = layout.LAST_TREE_TYPE
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local rd32 = memory.rd32
local rd8 = memory.rd8
local wr32 = memory.wr32
local patchJump = require("editor.menu_install").patchJump

local function patchTrees(self, G, O, data)
  local randomShrubs = O.shrubs and O.randomMix
  local randomTrees = O.felled and O.randomMix
  if O.apple or randomShrubs then
    patchJump(self, G.treeTypeOf, #TREE_TYPE_START, core.allocateAssembly(templates.plantType, {
      APPLE_COMMAND = O.apple and APPLE_COMMAND or 0xFFFFFFFF, APPLE_TYPE = APPLE_TYPE,
      RANDOM_SHRUB = data.randomShrub, FIRST_SHRUB = SHRUB_COMMANDS[1],
      LAST_SHRUB = SHRUB_COMMANDS[#SHRUB_COMMANDS], SEED = data.seed, RANDOM_MULTIPLIER = K.RANDOM_MULTIPLIER,
      RANDOM_INCREMENT = K.RANDOM_INCREMENT, CONVERTER_BACK = G.treeTypeOf + #TREE_TYPE_START,
    }))
  end
  if O.growth or randomTrees then
    local brush = G.brush
    if not O.growth then                       -- the game's own stage, as a brush size
      brush = core.allocate(4, true)
      wr32(brush, PLACED_STAGE + 1)
    end
    patchJump(self, G.placeTree, PLACE_TREE.stageSize, core.allocateAssembly(templates.stageFromBrush, {
      BRUSH = brush, MAX_STAGE = MAX_STAGE, STAGE = core.allocate(4, true),
      FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand, RANDOM_STANDING = K.RANDOM_STANDING,
      COMMAND_ON_STACK = PLACE_TREE.command, MOST_RANDOM_STAGE = K.MOST_RANDOM_STAGE, SEED = data.seed,
      SMALLEST_FELLED_STAGE = K.SMALLEST_FELLED_STAGE,
      RANDOM_MULTIPLIER = K.RANDOM_MULTIPLIER, RANDOM_INCREMENT = K.RANDOM_INCREMENT,
      BACK = G.placeTree + PLACE_TREE.stageSize,
    }))
  end
  if O.felled then
    local site = G.placeTree + PLACE_TREE.created
    patchJump(self, site, PLACE_TREE.createdSize, core.allocateAssembly(templates.felledTree, {
      FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand,
      COMMAND_ON_STACK = PLACE_TREE.command, TREE_SIZE = G.treeSize,
      TREES = G.landscape + TREES_IN_LANDSCAPE, TREE_TYPE = TREE.TYPE, LAST_TREE_TYPE = LAST_TREE_TYPE,
      STAGES = STAGES, TREE_STAGE = TREE.STAGE, LOGS = G.logs, TREE_LYING = TREE.LYING,
      LYING_FELLED = LYING_FELLED, TREE_LOGS = TREE.LOGS, TREE_CHOPS = TREE.CHOPS,
      LANDSCAPE = G.landscape, UPDATE_TREE = G.updateTree, RANDOM_STANDING = K.RANDOM_STANDING,
      RANDOM_FELLED = K.RANDOM_FELLED, SEED = data.seed, RANDOM_MULTIPLIER = K.RANDOM_MULTIPLIER,
      RANDOM_INCREMENT = K.RANDOM_INCREMENT, BACK = site + PLACE_TREE.createdSize,
    }))
  end
  if O.obstacles or O.noStacking then
    local site = scan(K.AOB_OBSTACLES, "the tree placement's obstacle check")
    local tables = C.eraseTables()
    local stacking = core.allocate(4, true)
    wr32(stacking, O.noStacking and 1 or 0)
    expectBytes(site + K.OBSTACLES_REFUSE[1], K.OBSTACLES_REFUSE[2], "the tree placement's tile test")
    if site < G.placeTree - K.OBSTACLES_NEAR or site > G.placeTree + K.OBSTACLES_NEAR then
      error(MODULE_NAME .. ": the obstacle check is not in the tree placement")
    end
    local past = site + K.OBSTACLES_SIZE + (rd8(site + K.OBSTACLES_JUMP) & 0xFF)
    patchJump(self, site, K.OBSTACLES_SIZE, core.allocateAssembly(templates.nearObstacles, {
      FLAG = data.nearObstacles, CHECK = site + K.OBSTACLES_SIZE, PAST_CHECK = past, NO_STACKING = stacking,
      NUMBERS = tables.numbers, ROCK_BASE = rd32(C.eraseSites()[1] + K.ERASE_ROCK.base),
      REFUSE = (site + rd32(site - 4)) & 0xFFFFFFFF,
    }))
  end
  -- With the texture mask on, its own hook on the same tile test carries the check box too
  -- (two hooks on one instruction cannot both find it).
  if O.rocksAndWater and data.mask == nil then
    -- G.placeTree is a spot inside placeTree past this test, so the test lies within reach on
    -- either side. A problem here only leaves the check box without effect.
    local ok, problem = pcall(function()
      local site = scan(K.AOB_TREE_GROUND, "the tree placement's tile test")
      if site < G.placeTree - K.OBSTACLES_NEAR or site > G.placeTree + K.OBSTACLES_NEAR then
        error(MODULE_NAME .. ": the tile test is not in the tree placement")
      end
      local mask = rd32(site + K.TREE_GROUND.mask)
      patchJump(self, site, K.TREE_GROUND.size, core.allocateAssembly(templates.treeGround, {
        FLAG = data.rocksAndWater, GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR,
        LOGIC = rd32(site + K.TREE_GROUND.logic), MASK = mask, LOOSE_MASK = mask & ~K.TREE_GROUND.loose,
        BACK = site + K.TREE_GROUND.size,
      }))
    end)
    if not ok then log(WARNING, tostring(problem) .. "; vegetation stays off rocks and water") end
  end
  if O.noStacking then C.patchEraseStacks(self, G) end
  if O.waterDecorations then C.patchRiverDecorations(self) end
  if O.waterDecorations and O.foamOnSea then C.patchFoamOnSea(self) end
end

return {
  patchTrees = patchTrees,
}
