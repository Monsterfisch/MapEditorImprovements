local layout = require("editor.layout")
local templates = layout.templates
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_PARAM = layout.ITEM_PARAM
local ITEM_RENDER = layout.ITEM_RENDER
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local TYPE_EVERY_FRAME = layout.TYPE_EVERY_FRAME
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local TEXTURES = layout.TEXTURES
local VEGETATION = layout.VEGETATION
local ROCKS = layout.ROCKS
local SHRUB_COMMANDS = layout.SHRUB_COMMANDS
local APPLE_COMMAND = layout.APPLE_COMMAND
local GRAVEL_COMMAND = layout.GRAVEL_COMMAND
local IRON_COMMAND = layout.IRON_COMMAND
local K = layout.K
local C = layout.C
local PENCIL_TARGET = layout.PENCIL_TARGET
local memory = require("editor.memory")
local scan = memory.scan
local readCallTarget = memory.readCallTarget
local item = memory.item
local dwordList = memory.dwordList
local rd32 = memory.rd32
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local buttonPictures = require("editor.images").buttonPictures
local frame = require("editor.frame")

---------------------------------------------------------------------------------------
-- The texture mask (Textures menu)
---------------------------------------------------------------------------------------

-- The mask's words: on (the check box), the stroke's reference texture (valid, ground flags,
-- look), setLand running inside setTerrain, a saved return address, and a byte per tile for
-- the tiles setLand let through.
function C.maskWords()
  if C.maskState == nil then
    C.maskState = {
      on = core.allocate(4, true), valid = core.allocate(4, true), flags = core.allocate(4, true),
      decoration = core.allocate(4, true), nested = core.allocate(4, true), ret = core.allocate(4, true),
      byType = core.allocate(4, true),
      stamps = core.allocate(K.MAP_TILES, true),
    }
  end
  return C.maskState
end

-- The Mask button, at the top left of the landscape menu's panel (in every one of its menus),
-- and the item that ends a stroke when the mouse button is let go (called while the landscape
-- menu's new table is built).
function C.textureMask(M)
  local G, O, data, added = M.G, M.O, M.data, M.added
  local W = C.maskWords()
  wr32(W.byType, O.maskByType and 1 or 0)
  local R = C.resolvePipette(G)
  local pictures = buttonPictures("mask")
  if G.blit == nil then
    G.blit = core.allocateAssembly(templates.blit, {
      PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
      SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
    })
  end
  for _, box in ipairs({ added.maskButton }) do
    wr32(box + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(box + ITEM_X, K.MASK_BUTTON.x)
    wr32(box + ITEM_Y, K.MASK_BUTTON.y)
    wr32(box + ITEM_WIDTH, pictures.width)
    wr32(box + ITEM_HEIGHT, pictures.height)
    wr32(box + ITEM_ACTION, core.allocateAssembly(templates.flip, { FLAG = W.on }))
    wr32(box + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(box + ITEM_RENDER, core.allocateAssembly(templates.flagPictureButton, {
      NORMAL = pictures.normal, HOVERED = pictures.hover, CHOSEN = pictures.chosen, FLAG = W.on,
      HOVER = G.hover, PENCIL = G.pencil, PENCIL_TARGET = PENCIL_TARGET, ITEM_X = G.itemX, ITEM_Y = G.itemY,
      BLIT = G.blit,
    }))
    wr32(box + ITEM_TEXT, 0)
    wr16(box + ITEM_CONTROL, -1)
    wr16(box + ITEM_HIDDEN, 0)
    M.tooltips[#M.tooltips + 1] = { item = box, lines = function()
      return { "Mask: " .. (rd8(W.on) ~= 0 and "on" or "off"),
        "Paints only tiles with the texture of the tile you start on" }
    end, raise = K.CHECK_BOX_TOOLTIP_RAISE }
  end

  -- The tools it works for, the nature tools: the Heights, Textures, Water, Vegetation and Rocks
  -- menus' (and the module's own: gravel, iron, max height, foam, small waves, the shrubs, the
  -- apple tree) and the pipette (its objects use the game's tools, already in the list).
  local tools = {}
  local blocks = { [K.HEIGHTS_TAB] = true, [TEXTURES] = true, [K.WATER] = true, [VEGETATION] = true,
    [ROCKS] = true, [K.ROCKS_SKIRMISH] = true }
  for param, entry in pairs(G.buttons) do
    if blocks[entry.block] then tools[#tools + 1] = param end
  end
  for _, rock in ipairs(G.rockButtons) do tools[#tools + 1] = rd32(item(G.table, rock.index, ITEM_PARAM)) end
  for _, decoration in ipairs(K.WATER_DECORATIONS) do tools[#tools + 1] = decoration.command end
  for _, command in ipairs(SHRUB_COMMANDS) do tools[#tools + 1] = command end
  for _, command in ipairs({ APPLE_COMMAND, K.MAX_HEIGHT_TOOL, K.PIPETTE_TOOL }) do tools[#tools + 1] = command end
  tools[#tools + 1] = GRAVEL_COMMAND
  tools[#tools + 1] = IRON_COMMAND
  tools[#tools + 1] = -1
  data.mask = { words = W, tools = dwordList(tools) }

  local tick = added.maskTick
  wr32(tick + ITEM_TYPE, TYPE_EVERY_FRAME)
  wr32(tick + ITEM_ACTION, core.allocateAssembly(templates.maskRelease, {
    CLICK_HELD = R.clickHeld, REF_VALID = W.valid,
  }))
end

-- The mask in the texture tools' tile loops (setTerrain and setLand) and around setTerrain's
-- call of setLand.
function C.patchTextureMask(self, G, data)
  local validTiles = C.resolveValidTiles()
  local W = data.mask.words
  local R = C.resolvePipette(G)
  local T = R.tileMap
  local terrain = scan(K.AOB_MASK_TERRAIN, "setTerrain's tile loop")
  local land = scan(K.AOB_MASK_LAND, "setLand's tile loop")
  local call = scan(K.AOB_MASK_CALL, "setTerrain's call of setLand") + K.MASK_CALL
  local MT, ML = K.MASK_TERRAIN, K.MASK_LAND
  local check = C.assemble("maskCheck", {
    MASK_ON = W.on, SUBTYPE = G.subtype, TOOLS = data.mask.tools, REF_VALID = W.valid,
    LOGIC = T + rd32(terrain + MT.logic), TEXTURE_FLAGS = K.MASK_FLAGS, REF_FLAGS = W.flags,
    NOT_EARTH = (~K.EARTH) & 0xFFFFFFFF,
    DECORATION = T + K.TMS.decoration, REF_DECORATION = W.decoration, STAMPS = W.stamps, NESTED = W.nested,
    BY_TYPE = W.byType, WATER_FLAGS = K.MASK_WATER,
  })
  data.mask.check = check
  local skip = rd8(terrain + MT.next) & 0xFF
  if skip >= 0x80 then skip = skip - 0x100 end
  C.patchJump(self, terrain, MT.size, core.allocateAssembly(templates.maskTerrain, {
    MASK_CHECK = check, NEXT_TILE = terrain + MT.next + 1 + skip, LOGIC = rd32(terrain + MT.logic),
    BACK = terrain + MT.size,
  }))
  C.patchJump(self, land, ML.size, core.allocateAssembly(templates.maskLand, {
    MASK_CHECK = check, NEXT_TILE = land + ML.next + 4 + rd32(land + ML.next), LOGIC = rd32(land + ML.logic),
    BACK = land + ML.size,
  }))
  C.patchCall(self, call, core.allocateAssembly(templates.maskNested, {
    NESTED = W.nested, RETURN = W.ret, SET_LAND = readCallTarget(call, 0, "setLand"),
  }))

  -- The height tools, trees and rocks: every stub first, then the patches.
  local function nextOf(site, at) return site + at + 4 + rd32(site + at) end
  local stubs = {}
  local tree = scan(K.AOB_MASK_TREE, "placeTree's tile test")
  local TM = K.MASK_TREE
  local loose = data.rocksAndWater or core.allocate(4, true)   -- Vegetation on rocks and water
  stubs[#stubs + 1] = { tree, TM.size, C.assemble("treeMask", {
    MASK_CHECK = check, TREE_LEAVE = nextOf(tree, TM.leave), LOGIC = rd32(tree + TM.logic),
    TEST_MASK = rd32(tree + TM.test), BACK = tree + TM.size, FLAG = loose, GAME_MODE = G.gameMode,
    MAP_EDITOR = K.MAP_EDITOR, LOOSE_MASK = rd32(tree + TM.test) & ~K.TREE_GROUND.loose,
  }) }
  local rock = scan(K.AOB_MASK_ROCK, "placeRock")
  stubs[#stubs + 1] = { rock, K.MASK_ROCK.size, C.assemble("rockMask", {
    MASK_CHECK = check, MAP_SIZE = K.MAP_SIZE, VALID = validTiles, ROWS = R.rows, BACK = rock + K.MASK_ROCK.size,
  }) }
  for _, stub in ipairs(stubs) do C.patchJump(self, stub[1], stub[2], stub[3]) end
end

-- The height tools' filter routine (templates.heightFilter), made once: the ignore boxes, the
-- height range, then the mask (or nothing, without it).
function C.heightFilter(G, data)
  if data.heightFilter ~= nil then return data.heightFilter end
  local R = C.resolvePipette(G)
  local T = R.tileMap
  local H = C.heightWords()
  local mask = data.mask ~= nil and data.mask.check or C.assemble("alwaysYes", {})
  data.heightFilter = C.assemble("heightFilter", {
    LOGIC = T + R.logic, IGNORE_WATER = H.ignoreWater, WATER_FLAGS = K.WATER_FLAGS,
    IGNORE_FARMLAND = H.ignoreFarmland, RIVER = K.RIVER_TERRAIN, DECORATION = T + K.TMS.decoration,
    FARMLAND = K.FARMLAND_LOOKS, SUBTYPE = G.subtype, RAISE_TOOL = K.RAISE_TOOL, LOWER_TOOL = K.LOWER_TOOL,
    EQUALIZE_TOOL = K.EQUALIZE_TOOL, INVERT = H.invert, SNAP = H.snap, BASE_HEIGHT = T + R.defaultHeight,
    RANGE_MIN = H.rangeMin, RANGE_MAX = H.rangeMax, MASK_CHECK = mask,
  })
  return data.heightFilter
end

-- The start of each tile in the height tools (raiseLand, useLevelBrush, useTerrainHeightBrush,
-- createPlateau): the next tile when the height filter says no.
function C.patchHeightFilters(self, G, data)
  local filter = C.heightFilter(G, data)
  local function nextOf(site, at) return site + at + 4 + rd32(site + at) end
  local stubs = {}
  local raise = scan(K.AOB_MASK_RAISE, "raiseLand's tile loop")
  local RM = K.MASK_RAISE
  stubs[#stubs + 1] = { raise, RM.size, C.assemble("raiseMask", {
    MASK_CHECK = filter, NEXT_TILE = nextOf(raise, RM.next), LOGIC = rd32(raise + RM.logic), BACK = raise + RM.size,
  }) }
  local B = K.MASK_BRUSH
  local level = scan(K.AOB_MASK_LEVEL, "the equalize tool's tile loop")
  stubs[#stubs + 1] = { level, B.size, C.assemble("levelMask", {
    MASK_CHECK = filter, NEXT_TILE = nextOf(level, B.next), LOGIC = rd32(level + B.logic), BACK = level + B.size,
    TILE_AT = rd8(level + B.tile) & 0xFF, CLICKED_AT = K.MASK_LEVEL_CLICKED,
  }) }
  for _, entry in ipairs({ { K.AOB_MASK_MIN, "the min and max height tools' tile loop" },
      { K.AOB_MASK_PLATEAU, "the plateau tools' tile loop" } }) do
    local at = scan(entry[1], entry[2])
    stubs[#stubs + 1] = { at, B.size, C.assemble("brushMask", {
      MASK_CHECK = filter, NEXT_TILE = nextOf(at, B.next), LOGIC = rd32(at + B.logic), BACK = at + B.size,
      TILE_AT = rd8(at + B.tile) & 0xFF,
    }) }
  end
  for _, stub in ipairs(stubs) do C.patchJump(self, stub[1], stub[2], stub[3]) end
end

-- After the map is drawn, every frame: the tree preview (also while the menu is hidden), and
-- outside the map editor the height tool settings back to their defaults. The routine runs from
-- the map drawing's patch site (editor/frame.lua), which init.lua puts in once every feature has
-- added its routine.
function C.patchFrame(self, G, data)
  local R = C.resolvePipette(G)
  local H = C.heightWords()
  frame.resolve()
  local plants = core.allocate(K.PLANT_TOOLS, true)
  local pad = C.assemble("alwaysYes", {})
  data.groupOn = core.allocate(4, true)
  local groupPad = pad
  if data.groupWarning ~= nil then
    wr32(data.groupOn, 1)
    groupPad = C.luaPad(data.groupWarning, "the herds and groups line")
  end
  if data.treePreviewPad ~= nil then
    for command in pairs(G.plantTypes or {}) do
      if command < K.PLANT_TOOLS then core.writeByte(plants + command, 1) end
    end
    pad = data.treePreviewPad
  end
  frame.add("editor", C.assemble("frameHook", {
    GAME_MODE = R.gameMode, MAP_EDITOR = K.MAP_EDITOR, RANGE_MIN = H.rangeMin, RANGE_MAX = H.rangeMax,
    DEFAULT_MIN = K.HEIGHT_RANGE_DEFAULT[1], DEFAULT_MAX = K.HEIGHT_RANGE_DEFAULT[2], SNAP = H.snap,
    INVERT = H.invert, IGNORE_WATER = H.ignoreWater, IGNORE_FARMLAND = H.ignoreFarmland, SUBTYPE = G.subtype,
    PLANT_TOOLS = K.PLANT_TOOLS, PLANTS = plants, PAD = pad,
    MENU_RENDER = data.treePreviewItem and data.treePreviewItem + ITEM_RENDER_TYPE or plants,
    RENDER_NONE = layout.RENDER_NONE,
    GROUP_ON = data.groupOn, FIRST_GROUP = G.firstGroup or 0, GROUP_SLOTS = G.groupSlots or 0,
    GROUP_SIZE = G.groupSize or 0,
    GROUP_COUNT = data.groupCount or data.groupOn, GROUP_MARGIN = K.GROUP_MARGIN, GROUP_PAD = groupPad,
  }))
end

-- Whether the mask would let a tile be changed, without starting a stroke (for previews).
-- What the mask compares for a tile's flags (maskCheck's mask_kind): its ground flags.
function C.maskKind(W, logic)
  local kind = logic & K.MASK_FLAGS & 0xFFFFFFFF
  if rd32(W.byType) ~= 0 and kind & K.MASK_WATER ~= 0 then kind = kind & ~K.EARTH & 0xFFFFFFFF end
  return kind
end

function C.maskPeek(T, R, tile)
  local W = C.maskState
  if W == nil or rd8(W.on) == 0 or rd32(W.valid) == 0 then return true end
  if C.maskKind(W, rd32(T + R.logic + tile * 4)) ~= (rd32(W.flags) & 0xFFFFFFFF) then return false end
  return C.waterAlike(W) or (rd8(T + K.TMS.decoration + tile) & 0xFF) == (rd32(W.decoration) & 0xFF)
end

-- The mask for lua that paints tiles (the pipette): answers whether tile may change, taking the
-- reference from clicked when a stroke starts, like maskCheck.
function C.maskAllows(T, R, tile, clicked)
  local W = C.maskState
  if W == nil or rd8(W.on) == 0 then return true end
  local function look(at)
    return C.maskKind(W, rd32(T + R.logic + at * 4)), rd8(T + K.TMS.decoration + at) & 0xFF
  end
  if rd32(W.valid) == 0 then
    local flags, decoration = look(clicked)
    wr32(W.flags, flags)
    wr32(W.decoration, decoration)
    wr32(W.valid, 1)
  end
  local flags, decoration = look(tile)
  return flags == (rd32(W.flags) & 0xFFFFFFFF)
    and (C.waterAlike(W) or decoration == (rd32(W.decoration) & 0xFF))
end

-- Water variants count as one: the setting is on and the stroke's reference is sea, river or ford.
function C.waterAlike(W)
  return rd32(W.byType) ~= 0 and (rd32(W.flags) & K.MASK_WATER) ~= 0
end

return true
