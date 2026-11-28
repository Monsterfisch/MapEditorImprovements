local layout = require("editor.layout")
local K = layout.K
local C = layout.C
local AOB_GAME_MODE = layout.AOB_GAME_MODE
local GAME_MODE_OPERAND = layout.GAME_MODE_OPERAND
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local readCallTarget = memory.readCallTarget
local rd32 = memory.rd32

---------------------------------------------------------------------------------------
-- Pipette
---------------------------------------------------------------------------------------

-- The pipette is a tool of its own (K.PIPETTE_TOOL, an id the game's click handlers leave
-- alone; its preview is the plain brush). Every frame, before the map click handler, lua
-- looks at the mouse: in read mode a click on the map takes the tile's heights and/or
-- textures, in write mode clicking and dragging gives them to the tiles under the brush.
-- The writes are the ones the game's own height and terrain tools make, followed by the
-- same updates.

local function keyCode(name, choice)
  if type(name) ~= "string" then return nil end
  local special = { ctrl = 0x11, shift = 0x10, alt = 0x12, space = 0x20, tab = 0x09 }
  if special[name] ~= nil and choice ~= "select" then return special[name] end
  local letter = name:match(choice ~= nil and "^letter_([a-z])$" or "^letter_(%a)$")
  if letter ~= nil then return string.byte(letter:upper()) end
  local digit = name:match("^digit_(%d)$")
  if digit ~= nil and choice ~= "hold" then return 0x30 + tonumber(digit) end
  local f = name:match(choice ~= nil and "^f([1-9]%d?)$" or "^f(%d+)$")
  if f ~= nil and tonumber(f) >= 1 and tonumber(f) <= 12 then return 0x6F + tonumber(f) end
  return nil
end
C.keyCode = keyCode

local validTiles, validTilesError
function C.resolveValidTiles()
  if validTiles == nil and validTilesError == nil then
    local ok, site = pcall(memory.scanUnique, K.AOB_TILE_VALID, "the map's tiles")
    if ok then validTiles = rd32(site + K.TILE_VALID) else validTilesError = site end
  end
  if validTilesError ~= nil then error(validTilesError, 0) end
  return validTiles
end

-- What the game needs for the pipette, from the code that uses it.
function C.resolvePipette(G)
  if C.resolved ~= nil then return C.resolved end
  local R = {}
  local mouse = scan(K.AOB_MOUSE_CLICK, "the map click")
  local M = K.MOUSE_CLICK
  R.clickStart, R.mouseX, R.mouseY = rd32(mouse + M.start), rd32(mouse + M.x), rd32(mouse + M.y)
  R.clickHeld = rd32(scan(K.AOB_CLICK_HELD, "the map click state") + K.CLICK_HELD)
  local mouseTile = scan(K.AOB_MOUSE_TILE, "the mouse tile")
  local MT = K.MOUSE_TILE
  R.flatView, R.viewport = rd32(mouseTile + MT.flat), rd32(mouseTile + MT.viewport)
  R.flatSetup = readCallTarget(mouseTile, MT.flatSetup, "setupMouseTileXY2")
  R.mouseSetup = readCallTarget(mouseTile, MT.setup, "setupMouseTileXY")
  local preview = scan(K.AOB_PIPETTE_PREVIEW, "the brush preview")
  local P = K.PIPETTE_PREVIEW
  R.previewSite, R.brushField, R.brushSizes = preview, rd32(preview + P.brush), rd32(preview + P.sizes)
  expectBytes(preview + P.rows[1], P.rows[2], "the brush preview's rows")
  R.rows = rd32(preview + P.rows[1] + #P.rows[2])
  local walk = scan(K.AOB_BRUSH_TILE, "the brush walk")
  R.tileForBrush = readCallTarget(walk, K.BRUSH_TILE_CALL, "getTileForBrush")
  local tail = scan(K.AOB_HEIGHT_TAIL, "the height brush")
  local H = K.HEIGHT_TAIL
  R.pathFinding, R.links, R.logicFlag = rd32(tail + H.pathFinding), readCallTarget(tail, H.links, "the path links"),
    rd32(tail + H.flag)
  local heights = scan(K.AOB_HEIGHTS, "the tile heights")
  R.height, R.defaultHeight, R.logic = rd32(heights + K.HEIGHTS.height), rd32(heights + K.HEIGHTS.default),
    rd32(heights + K.HEIGHTS.logic)
  local after = scan(K.AOB_HEIGHT_TOOL, "the height tool")
  local A = K.HEIGHT_TOOL
  R.walk, R.minimap = readCallTarget(after, A.walk, "the walk layer update"), rd32(after + A.minimap)
  R.macroFlag, R.redraw = rd32(after + A.macro), readCallTarget(after, A.redraw, "the minimap redraw")
  local rock = scan(K.AOB_HEIGHT_ROCK, "the height brush's rock removal")
  R.organism, R.landscape = rd32(rock + K.HEIGHT_ROCK.organism), rd32(rock + K.HEIGHT_ROCK.landscape)
  R.removeRock = readCallTarget(rock, K.HEIGHT_ROCK.remove, "removeRock")
  local building = scan(K.AOB_BUILDING_TYPE, "the building types")
  R.buildingStride, R.buildingType = rd32(building + K.BUILDING_TYPE.stride), rd32(building + K.BUILDING_TYPE.type)
  R.commandOfType = scan(K.AOB_COMMAND_OF_TYPE, "convertBuildingTypeToCommandBuildingType")
  local sprites = scan(K.AOB_BUILDING_SPRITES, "the building pictures")
  expectBytes(sprites + K.BUILDINGS_STATE - 1, { 0xB9 }, "the buildings")
  R.buildingsState = rd32(sprites + K.BUILDINGS_STATE)
  local variations = scan(K.AOB_VARIATIONS, "the building variations")
  R.variationField, R.variationTables = rd32(variations + K.VARIATIONS.field), {}
  for i, at in ipairs(K.VARIATIONS.tables) do R.variationTables[i] = rd32(variations + at) end
  R.hovelField = rd32(scan(K.AOB_HOVEL_VARIANT, "the hovel variants") + K.HOVEL_VARIANT.field)
  R.ruinedFlag = rd32(scan(K.AOB_RUINED_CATHEDRAL, "the ruined cathedral") + K.RUINED_CATHEDRAL.flag)
  local choice = scan(K.AOB_PLAYER_CHOICE, "the player shields")
  R.playerFlags, R.currentPlayer = rd32(choice + K.PLAYER_CHOICE.flags), rd32(choice + K.PLAYER_CHOICE.current)
  R.editorPlayer = rd32(scan(K.AOB_EDITOR_PLAYER, "the editor's building owner") + K.EDITOR_PLAYER)
  local place = scan(K.AOB_PLACE_PLANT, "the rock and tree placement")
  R.placeRock = readCallTarget(place, K.PLACE_PLANT.placeRock, "placeRock")
  R.placeTree = readCallTarget(place, K.PLACE_PLANT.placeTree, "placeTree")
  R.menuGuard = rd32(scan(K.AOB_KEY_GUARD, "the key guard") + K.KEY_GUARD)
  R.keyState = rd32(scan(K.AOB_ASYNC_KEY, "the key state") + K.ASYNC_KEY_IMPORT)
  R.gameMode = rd32(scan(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND)
  R.tileMap = rd32(scan(K.AOB_ROCK_PREVIEW, "the tile map") + K.ROCK_PREVIEW.tileMap)
  C.resolved = R
  return R
end

-- Names of what the textures pipette took, for the line above its panel.
function C.textureNames(logic, decoration)
  local names = {}
  for _, flag in ipairs(K.TEXTURE_NAMES) do
    if logic & flag[1] ~= 0 then names[#names + 1] = flag[2] end
  end
  local river = logic & K.RIVER_TERRAIN ~= 0
  for _, flag in ipairs(river and K.RIVER_DECORATION_NAMES or K.DECORATION_NAMES) do
    if decoration & flag[1] ~= 0 then names[#names + 1] = flag[2] end
  end
  if #names == 0 then names[1] = "plain ground" end
  return table.concat(names, ", ")
end

return {
  keyCode = keyCode,
}
