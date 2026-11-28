local layout = require("editor.layout")
local MODULE_NAME = layout.MODULE_NAME
local LANDSCAPE_KEY_RECORD = layout.LANDSCAPE_KEY_RECORD
local KEY_BUTTON_ITEM = layout.KEY_BUTTON_ITEM
local ITEM_COUNT = layout.ITEM_COUNT
local MAP_CLICK_ITEM = layout.MAP_CLICK_ITEM
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_PARAM = layout.ITEM_PARAM
local ITEM_RENDER = layout.ITEM_RENDER
local TYPE_EVERY_FRAME = layout.TYPE_EVERY_FRAME
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local TYPE_GROUP_START = layout.TYPE_GROUP_START
local TYPE_BLOCK = layout.TYPE_BLOCK
local TYPE_END = layout.TYPE_END
local TYPE_GROUP_MEMBER_MASK = layout.TYPE_GROUP_MEMBER_MASK
local TYPE_GROUP_MEMBER = layout.TYPE_GROUP_MEMBER
local HOVER_TEXT_ITEM = layout.HOVER_TEXT_ITEM
local HOVER_TEXT_POSITION = layout.HOVER_TEXT_POSITION
local DEER = layout.DEER
local LION = layout.LION
local RABBIT = layout.RABBIT
local CAMEL = layout.CAMEL
local TEXTURES = layout.TEXTURES
local VEGETATION = layout.VEGETATION
local ANIMALS = layout.ANIMALS
local ROCKS = layout.ROCKS
local SHRUB_COMMANDS = layout.SHRUB_COMMANDS
local APPLE_COMMAND = layout.APPLE_COMMAND
local APPLE_TYPE = layout.APPLE_TYPE
local IRON_COMMAND = layout.IRON_COMMAND
local TEXTURE_ROWS = layout.TEXTURE_ROWS
local VEGETATION_TREES = layout.VEGETATION_TREES
local TOP_ROW_SHRUB = layout.TOP_ROW_SHRUB
local SORTED_SHRUBS = layout.SORTED_SHRUBS
local K = layout.K
local BUTTON_RENDER = layout.BUTTON_RENDER
local BUTTON_WIDTH = layout.BUTTON_WIDTH
local MAP_CLICK = layout.MAP_CLICK
local HOVER_RENDER_BYTES = layout.HOVER_RENDER_BYTES
local HOVER_RENDER_CALL = layout.HOVER_RENDER_CALL
local CAMERA_X = layout.CAMERA_X
local CAMERA_Y = layout.CAMERA_Y
local TEXT_LAYER = layout.TEXT_LAYER
local AOB_AMMO_COUNT = layout.AOB_AMMO_COUNT
local AMMO_WIDTH = layout.AMMO_WIDTH
local AMMO_TEXT_MANAGER = layout.AMMO_TEXT_MANAGER
local AMMO_RENDER_NUMBER = layout.AMMO_RENDER_NUMBER
local AOB_NAME_BOX = layout.AOB_NAME_BOX
local NAME_BOX = layout.NAME_BOX
local WIDTH_UNTIL_CURSOR_CALL = layout.WIDTH_UNTIL_CURSOR_CALL
local COLOUR_BOX_SURFACE = layout.COLOUR_BOX_SURFACE
local COLOUR_BOX_CLIP = layout.COLOUR_BOX_CLIP
local AOB_PIXEL_FORMAT = layout.AOB_PIXEL_FORMAT
local PIXEL_FORMAT_OPERAND = layout.PIXEL_FORMAT_OPERAND
local AOB_MENU_ITEM = layout.AOB_MENU_ITEM
local MENU_ITEM_MOUSE = layout.MENU_ITEM_MOUSE
local MENU_ITEM_IS_INSIDE = layout.MENU_ITEM_IS_INSIDE
local AOB_RENDER_GM = layout.AOB_RENDER_GM
local RENDER_GM = layout.RENDER_GM
local ANIMATION = layout.ANIMATION
local TEXTURES_MODE = layout.TEXTURES_MODE
local AOB_NEW_TREE = layout.AOB_NEW_TREE
local NEW_TREE = layout.NEW_TREE
local TREE_TYPES = layout.TREE_TYPES
local AOB_NEW_ROCK = layout.AOB_NEW_ROCK
local NEW_ROCK = layout.NEW_ROCK
local AOB_NEW_GROUP = layout.AOB_NEW_GROUP
local NEW_GROUP = layout.NEW_GROUP
local AOB_GROUPS = layout.AOB_GROUPS
local GROUPS_OBJECT = layout.GROUPS_OBJECT
local GROUPS_CALL = layout.GROUPS_CALL
local AOB_TREE_TYPE = layout.AOB_TREE_TYPE
local TREE_TYPE_START = layout.TREE_TYPE_START
local AOB_PLACE_TREE = layout.AOB_PLACE_TREE
local PLACE_TREE = layout.PLACE_TREE
local CREATE_TREE = layout.CREATE_TREE
local AOB_SCREEN_SIZE = layout.AOB_SCREEN_SIZE
local SCREEN_WIDTH_OPERAND = layout.SCREEN_WIDTH_OPERAND
local SCREEN_HEIGHT_OPERAND = layout.SCREEN_HEIGHT_OPERAND
local AOB_IMAGE_BUTTON = layout.AOB_IMAGE_BUTTON
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local readOperand = memory.readOperand
local readCallTarget = memory.readCallTarget
local item = memory.item
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8

---------------------------------------------------------------------------------------
-- Finding things
---------------------------------------------------------------------------------------

local function resolveMenu(G)
  G.site = memory.menuInitializer(0x5B0)
  G.table, G.menu, G.constructor = memory.menuTable(G.site, KEY_BUTTON_ITEM, LANDSCAPE_KEY_RECORD,
    "the landscape editor's menu")
  local index = 0
  while rd32(item(G.table, index, ITEM_TYPE)) ~= TYPE_END do
    index = index + 1
    if index > ITEM_COUNT then break end
  end
  if index ~= ITEM_COUNT then
    error(MODULE_NAME .. ": the landscape editor's menu is not the one this module knows")
  end
  if rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_TYPE)) ~= TYPE_CLICKABLE
      or rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_X)) ~= HOVER_TEXT_POSITION[1]
      or rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_Y)) ~= HOVER_TEXT_POSITION[2]
      or rd32(item(G.table, MAP_CLICK_ITEM, ITEM_TYPE)) ~= TYPE_EVERY_FRAME then
    error(MODULE_NAME .. ": the landscape editor's menu is not laid out as the module expects")
  end

  -- The buttons by command, the render function their groups give them, the block each one
  -- is in (the tab id of the 0x64 marker before it, 0 for the part that is always shown), and
  -- where the always shown part and each tab end.
  -- Rock tool buttons are listed per tab too (they are in both Rocks tabs), with the action
  -- their group gives them.
  G.buttons, G.blockEnd, G.rockButtons = {}, {}, {}
  local groupRender, groupAction, groupIndex, block = nil, nil, nil, 0
  for i = 0, ITEM_COUNT - 1 do
    local itemType = rd32(item(G.table, i, ITEM_TYPE))
    if itemType == TYPE_BLOCK then
      if block == 0 then G.firstBlock = i else G.blockEnd[block] = G.blockEnd[block] or i end
      block = rd32(item(G.table, i, ITEM_PARAM))
    elseif itemType == TYPE_GROUP_START then
      groupRender = rd32(item(G.table, i, ITEM_RENDER))
      groupAction = rd32(item(G.table, i, ITEM_ACTION))
      groupIndex = i
    elseif (itemType & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER then
      local param = rd32(item(G.table, i, ITEM_PARAM))
      if G.buttons[param] == nil then
        local render = rd32(item(G.table, i, ITEM_RENDER))
        if render == 0 then render = groupRender end
        local action = rd32(item(G.table, i, ITEM_ACTION))
        if action == 0 then action = groupAction end
        G.buttons[param] = { index = i, render = render, block = block, action = action }
      end
      if param >= K.FIRST_ROCK_COMMAND and param <= K.LAST_ROCK_COMMAND then
        local action = rd32(item(G.table, i, ITEM_ACTION))
        if action == 0 then action = groupAction end
        table.insert(G.rockButtons, { index = i, action = action, block = block, group = groupIndex })
      end
    end
  end
  if block ~= 0 then G.blockEnd[block] = G.blockEnd[block] or ITEM_COUNT end
  if G.firstBlock == nil or G.blockEnd[ANIMALS] == nil or G.blockEnd[VEGETATION] == nil
      or G.blockEnd[TEXTURES] == nil or G.blockEnd[ROCKS] == nil then
    error(MODULE_NAME .. ": the landscape editor's menu has not got the tabs this module knows")
  end
  local needed = { DEER, LION, RABBIT, CAMEL, VEGETATION, ANIMALS, ROCKS, IRON_COMMAND, TOP_ROW_SHRUB,
    table.unpack(SORTED_SHRUBS) }
  for _, row in ipairs(TEXTURE_ROWS) do
    for i = 1, 4 do needed[#needed + 1] = row[i] end
  end
  for _, param in ipairs(VEGETATION_TREES) do needed[#needed + 1] = param end
  for _, param in ipairs(needed) do
    if G.buttons[param] == nil then
      error(string.format("%s: button %d is missing from the landscape editor's menu", MODULE_NAME, param))
    end
  end
  G.plants = {}
  for param, button in pairs(G.buttons) do
    if button.block == VEGETATION then G.plants[#G.plants + 1] = param end
  end

  G.buttonRender = G.buttons[DEER].render
  for _, param in ipairs({ LION, RABBIT, CAMEL, table.unpack(G.plants) }) do
    if G.buttons[param].render ~= G.buttonRender then
      error(MODULE_NAME .. ": the landscape editor's buttons are drawn by an unknown function")
    end
  end
  local b = BUTTON_RENDER
  G.hover = readOperand(G.buttonRender, b.hover, "the editor button renderer")
  G.activeTab = readOperand(G.buttonRender, b.tab, "the editor button renderer")
  G.brush = readOperand(G.buttonRender, b.brush, "the editor button renderer")
  G.subtype = readOperand(G.buttonRender, b.subtype, "the editor button renderer")
  G.drawMode = readOperand(G.buttonRender, b.drawMode, "the editor button renderer")
  G.buttonImages = readOperand(G.buttonRender, b.images, "the editor button renderer")
  G.itemY = readOperand(G.buttonRender, b.y, "the editor button renderer")
  G.itemX = readOperand(G.buttonRender, b.x, "the editor button renderer")
  G.textures = readOperand(G.buttonRender, b.textures, "the editor button renderer")
  if G.drawMode ~= G.textures + TEXTURES_MODE then
    error(MODULE_NAME .. ": the texture renderer is not laid out as the module expects")
  end

  G.onMap = readOperand(rd32(item(G.table, MAP_CLICK_ITEM, ITEM_ACTION)), MAP_CLICK.onMap, "the map click handler")

  G.hoverRender = rd32(item(G.table, HOVER_TEXT_ITEM, ITEM_RENDER))
  expectBytes(G.hoverRender, HOVER_RENDER_BYTES, "the description line renderer")
  local describe = readCallTarget(G.hoverRender, HOVER_RENDER_CALL, "the description line renderer")
  G.cameraX = readOperand(describe, CAMERA_X, "the description line renderer")
  G.cameraY = readOperand(describe, CAMERA_Y, "the description line renderer")
  G.textLayer = readOperand(describe, TEXT_LAYER, "the description line renderer")
  G.imageButton = scan(AOB_IMAGE_BUTTON, "the image button renderer")
end

local nameBox
local function resolveButtonDrawing(G)
  if G.colourBox then return end
  nameBox = nameBox or scan(AOB_NAME_BOX, "the Save dialog's name box")
  local pencil = readOperand(nameBox, NAME_BOX.pencil, "the name box")
  local colourBox = readCallTarget(nameBox, NAME_BOX.colourBox, "the colour box")
  local pixelFormat = rd32(scan(AOB_PIXEL_FORMAT, "the pixel format") + PIXEL_FORMAT_OPERAND)
  G.pencil, G.colourBox, G.pixelFormat = pencil, colourBox, pixelFormat
end

local function resolveMouse(G)
  if G.isMouseInside then return end
  local menuItem = scan(AOB_MENU_ITEM, "the menu's mouse test")
  G.mouse = readOperand(menuItem, MENU_ITEM_MOUSE, "the menu's mouse test")
  G.isMouseInside = readCallTarget(menuItem, MENU_ITEM_IS_INSIDE, "the menu's mouse test")
end

local function resolveDrawing(G)
  resolveButtonDrawing(G)
  resolveMouse(G)
  local ammo = scan(AOB_AMMO_COUNT, "the ammunition count")
  if readOperand(ammo, AMMO_WIDTH, "the ammunition count") ~= G.itemX + BUTTON_WIDTH then
    error(MODULE_NAME .. ": the item position globals are not laid out as the module expects")
  end
  G.textManager = readOperand(ammo, AMMO_TEXT_MANAGER, "the ammunition count")
  G.renderNumber = readCallTarget(ammo, AMMO_RENDER_NUMBER, "the number drawing")

  G.roundedBox = readCallTarget(nameBox, NAME_BOX.roundedBox, "the name box background")
  local untilCursor = readCallTarget(nameBox, NAME_BOX.widthUntilCursor, "the name box cursor")
  G.textWidth = readCallTarget(untilCursor, WIDTH_UNTIL_CURSOR_CALL, "the text width")
  if readOperand(nameBox, NAME_BOX.textManager, "the name box") ~= G.textManager then
    error(MODULE_NAME .. ": the text manager is not the one this module knows")
  end
  G.shadowedText = readCallTarget(nameBox, NAME_BOX.shadowedText, "the text drawing")
  G.setupSurface = readCallTarget(G.colourBox, COLOUR_BOX_SURFACE, "the drawing surface")
  G.setupPencil = readCallTarget(G.colourBox, COLOUR_BOX_CLIP, "the drawing clip")
  local screenSize = memory.scanUnique(AOB_SCREEN_SIZE, "the screen size")
  G.screenWidth = rd32(screenSize + SCREEN_WIDTH_OPERAND)
  G.screenHeight = rd32(screenSize + SCREEN_HEIGHT_OPERAND)

  local renderGM = scan(AOB_RENDER_GM, "the picture renderer")
  G.renderGM = renderGM
  G.firstPictures = rd32(renderGM + RENDER_GM.firstPictures)
  G.pictureOffsets = readOperand(renderGM, RENDER_GM.offsets, "the picture renderer")
  expectBytes(renderGM + RENDER_GM.dataBase[1], RENDER_GM.dataBase[2], "the picture renderer")
  G.pictureHeights = readOperand(renderGM, RENDER_GM.heights, "the picture renderer")
  local animation = readCallTarget(renderGM, RENDER_GM.animation, "the sprite renderer")
  G.spritePalette = readOperand(animation, ANIMATION.palette, "the sprite renderer")
  G.sprite = readOperand(animation, ANIMATION.sprite, "the sprite renderer")
end

local function resolveUnitLimits(G)
  local unitTest = scan(K.AOB_UNITS, "the unit count")
  G.units = rd32(unitTest + K.UNITS_OPERAND)
  G.unitLimit = rd32(unitTest + K.UNITS_LIMIT)
end

local function resolveCounts(G)
  local ok, found = pcall(scan, K.AOB_UNIT_MAX, "the unit limit")
  if ok then G.unitMax = rd32(found + K.UNIT_MAX) end
  G.animals = {
    [DEER] = rd32(scan(K.AOB_DEER, "the deer count") + K.DEER_OPERAND),
    [LION] = rd32(scan(K.AOB_LIONS, "the lion count") + K.LIONS_OPERAND),
    [RABBIT] = rd32(scan(K.AOB_RABBITS, "the rabbit count") + K.RABBITS_OPERAND),
    [CAMEL] = rd32(scan(K.AOB_CAMELS, "the camel count") + K.CAMELS_OPERAND),
  }
end

local function resolveTreePlacement(G)
  local placeTree = scan(AOB_PLACE_TREE, "the tree placement")
  G.placeTree = placeTree
  G.landscape = rd32(placeTree + PLACE_TREE.landscape)
  G.createTree = readCallTarget(placeTree, PLACE_TREE.create, "createTree")
  G.treeSize = rd32(placeTree + PLACE_TREE.created + 4)
end

local function resolveTreePictures(G)
  G.logs = readOperand(G.createTree, CREATE_TREE.logs, "createTree")
  G.typeGm = readOperand(G.createTree, CREATE_TREE.gm, "createTree")
  G.updateTree = readOperand(G.createTree, CREATE_TREE.update, "createTree")
end

local function resolveTreeSlots(G)
  local newTree = scan(AOB_NEW_TREE, "the tree slot search")
  if newTree ~= G.createTree then
    error(MODULE_NAME .. ": createTree is not where the module expects it")
  end
  G.firstTree = G.landscape + rd32(newTree + NEW_TREE.first)
  G.treeSlots = rd32(newTree + NEW_TREE.last)
  if readOperand(newTree, NEW_TREE.size, "the tree slot search") ~= G.treeSize then
    error(MODULE_NAME .. ": the tree size is not the one this module knows")
  end
end

local function resolveRockSlots(G)
  local newRock = scan(AOB_NEW_ROCK, "the rock slot search")
  local call = scan(K.AOB_CREATE_ROCK_CALL, "the rock placement")
  if readCallTarget(call, K.CREATE_ROCK_CALL, "createRock") ~= newRock then
    error(MODULE_NAME .. ": createRock is not where the module expects it")
  end
  G.firstRock = rd32(call + K.CREATE_ROCK_LANDSCAPE) + rd32(newRock + NEW_ROCK.first)
  G.rockSlots = rd32(newRock + NEW_ROCK.last)
  expectBytes(newRock + NEW_ROCK.size[1], NEW_ROCK.size[2], "the rock slot search")
  G.rockSize = rd8(newRock + NEW_ROCK.size[1] + 2) & 0xFF
end

local function resolveGroupSlots(G)
  local newGroup = scan(AOB_NEW_GROUP, "the group slot search")
  local groupsCall = scan(AOB_GROUPS, "the group array")
  if readCallTarget(groupsCall, GROUPS_CALL, "the group array") ~= newGroup then
    error(MODULE_NAME .. ": the group array is not the one this module knows")
  end
  G.groupSize = rd32(newGroup + NEW_GROUP.size)
  G.firstGroup = rd32(groupsCall + GROUPS_OBJECT) + G.groupSize + (rd8(newGroup + NEW_GROUP.inUse) & 0xFF)
  G.groupSlots = rd32(newGroup + NEW_GROUP.limit) - 1
end

local function resolvePlantTypes(G)
  -- Tree types for the vegetation tools before the apple tree hook.
  G.treeTypeOf = scan(AOB_TREE_TYPE, "the plant types")
  expectBytes(G.treeTypeOf, TREE_TYPE_START, "the plant types")
  local treeType = core.exposeCode(G.treeTypeOf, 2, 1)
  G.plantTypes = {}
  for _, param in ipairs(G.plants) do
    G.plantTypes[param] = treeType(G.landscape, param) & (TREE_TYPES - 1)
  end
  for _, param in ipairs(SHRUB_COMMANDS) do
    G.plantTypes[param] = treeType(G.landscape, param) & (TREE_TYPES - 1)
  end
  G.plantTypes[APPLE_COMMAND] = APPLE_TYPE
end

-- Rocks: the rock tool's state, the placement and preview sites, and what the module needs to
-- draw rocks the way the map renderer does.
local function resolveRocks(G)
  G.rockPlace = scan(K.AOB_ROCK_PLACE, "the rock placement")
  G.rockParam = rd32(G.rockPlace + K.ROCK_PLACE.param)
  G.rockVariant = rd32(G.rockPlace + K.ROCK_PLACE.variant)
  G.chosenRockSize = G.rockVariant + 4
  G.rockPreview = scan(K.AOB_ROCK_PREVIEW, "the rock preview")
  G.mouseTileY = rd32(G.rockPreview + K.ROCK_PREVIEW.mouseY)
  G.tileMap = rd32(G.rockPreview + K.ROCK_PREVIEW.tileMap)
  local a = readOperand(G.rockPreview, K.ROCK_PREVIEW.first, "the rock preview")
  local b = readOperand(G.rockPreview, K.ROCK_PREVIEW.second, "the rock preview")
  if not ((a == G.rockVariant and b == G.chosenRockSize) or (b == G.rockVariant and a == G.chosenRockSize)) then
    error(MODULE_NAME .. ": the rock variant and size are not where the module expects them")
  end
  if G.tileMap + 0x5548F4 ~= G.rockVariant then
    error(MODULE_NAME .. ": the map tile state is not laid out as the module expects")
  end
  local stamp = scan(K.AOB_ROCK_STAMP, "the rock drawing")
  G.footprint = readCallTarget(stamp, K.ROCK_STAMP.mapping, "the footprint layout")
  local randomOffset = readCallTarget(stamp, K.ROCK_STAMP.randomOffset, "the rock pictures")
  G.rockBases = readOperand(randomOffset, K.ROCK_PICTURES, "the rock pictures")
  local newRock = scan(AOB_NEW_ROCK, "the rock slot search")
  G.rockGm = rd16(readOperand(newRock, K.ROCK_GM, "createRock") + 4)
end

-- Herds: per animal the herd code site and what it does.
local function resolveHerds(G)
  local sites = memory.scanAll(K.AOB_HERD, #K.HERD_ANIMALS + 1)
  if #sites ~= #K.HERD_ANIMALS then
    error(MODULE_NAME .. ": the herd code is not the one this module knows")
  end
  G.herds = {}
  for i, site in ipairs(sites) do
    local herd = { command = K.HERD_ANIMALS[i][1], name = K.HERD_ANIMALS[i][2], site = site + K.HERD.site }
    herd.mask = rd8(site + K.HERD.mask) & 0xFF
    herd.unit = rd32(site + K.HERD.unit)
    herd.base = rd8(site + K.HERD.base) & 0xFF
    expectBytes(site + K.HERD.group[1], K.HERD.group[2], "the herd code")
    herd.group = rd16(site + K.HERD.group[1] + #K.HERD.group[2])
    G.herds[herd.command] = herd
  end
end

return {
  resolveMenu = resolveMenu,
  resolveDrawing = resolveDrawing,
  resolveButtonDrawing = resolveButtonDrawing,
  resolveMouse = resolveMouse,
  resolveUnitLimits = resolveUnitLimits,
  resolveCounts = resolveCounts,
  resolveTreePlacement = resolveTreePlacement,
  resolveTreePictures = resolveTreePictures,
  resolveTreeSlots = resolveTreeSlots,
  resolveRockSlots = resolveRockSlots,
  resolveGroupSlots = resolveGroupSlots,
  resolvePlantTypes = resolvePlantTypes,
  resolveRocks = resolveRocks,
  resolveHerds = resolveHerds,
}
