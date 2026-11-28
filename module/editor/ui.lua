local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_PARAM = layout.ITEM_PARAM
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_HOVERED = layout.ITEM_HOVERED
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local PLACED_BY_CONTROL = layout.PLACED_BY_CONTROL
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local MENU_SCROLL = layout.MENU_SCROLL
local INFO_IMAGE = layout.INFO_IMAGE
local FIRST_TREE_COMMAND = layout.FIRST_TREE_COMMAND
local LAST_TREE_COMMAND = layout.LAST_TREE_COMMAND
local SHRUB_COMMANDS = layout.SHRUB_COMMANDS
local ROW_LEFT = layout.ROW_LEFT
local ROW_RIGHT = layout.ROW_RIGHT
local K = layout.K
local C = layout.C
local IMAGE_SIZE = layout.IMAGE_SIZE
local NUMBER_FONT = layout.NUMBER_FONT
local NUMBER_COLOUR = layout.NUMBER_COLOUR
local NUMBER_FROM_BOTTOM = layout.NUMBER_FROM_BOTTOM
local PENCIL_TARGET = layout.PENCIL_TARGET
local BOX_BLEND = layout.BOX_BLEND
local TOOLTIP_FONT = layout.TOOLTIP_FONT
local TOOLTIP_COLOUR = layout.TOOLTIP_COLOUR
local TOOLTIP_LINE = layout.TOOLTIP_LINE
local TOOLTIP_PADDING = layout.TOOLTIP_PADDING
local TOOLTIP_BOTTOM = layout.TOOLTIP_BOTTOM
local ALIGN_LEFT = layout.ALIGN_LEFT
local MAP_LAYER = layout.MAP_LAYER
local PICTURE_SIZE = layout.PICTURE_SIZE
local TEXTURES_MODE = layout.TEXTURES_MODE
local TEXTURES_DIRECT_PALETTE = layout.TEXTURES_DIRECT_PALETTE
local STAGES = layout.STAGES
local MAX_STAGE = layout.MAX_STAGE
local PLACED_STAGE = layout.PLACED_STAGE
local FELLED_PICTURE_BASE = layout.FELLED_PICTURE_BASE
local SHRUB_PALETTES = layout.SHRUB_PALETTES
local SHRUB_PICTURE = layout.SHRUB_PICTURE
local FELLED_PALETTE = layout.FELLED_PALETTE
local PANEL_PADDING = layout.PANEL_PADDING
local PANEL_GAP = layout.PANEL_GAP
local PANEL_MARGIN = layout.PANEL_MARGIN
local MOST_LOGS = layout.MOST_LOGS
local AOB_GAME_MODE = layout.AOB_GAME_MODE
local GAME_MODE_OPERAND = layout.GAME_MODE_OPERAND
local memory = require("editor.memory")
local scan = memory.scan
local readCallTarget = memory.readCallTarget
local writeCString = memory.writeCString
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local makeSpriteBoxes = require("editor.sprites").makeSpriteBoxes
local lane = require("editor.lane")

---------------------------------------------------------------------------------------
-- Map counts: the tooltip
---------------------------------------------------------------------------------------

-- A name as a string, or { en = ..., de = ... } chosen by the framework's game language (known
-- after the game's init).
local function localName(name)
  if type(name) ~= "table" then return name end
  return name[data.version.getGameLanguage() == "german" and "de" or "en"]
end

-- candidates: { item = button, name = text or localName table } or
-- { item = button, lines = function returning text lines or nil }.
local function makeTooltip(G, candidates)
  local isMouseInside = core.exposeCode(G.isMouseInside, 5, 1)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local lineBuffers = { core.allocate(96, true), core.allocate(96, true), core.allocate(96, true),
    core.allocate(96, true) }

  -- Like the description line, the tooltip is drawn on the map surface (at the screen
  -- position plus the camera offset), which is drawn afresh every frame: nothing of it stays
  -- behind once the mouse leaves the button. Lines are added upwards, away from the panel.
  return function()
    for _, candidate in ipairs(candidates) do
      local button = candidate.item
      local x = rd32(G.menu + MENU_X) + rd32(button + ITEM_X)
      local y = rd32(G.menu + MENU_Y) + rd32(button + ITEM_Y)
      local shown = rd16(button + ITEM_HOVERED) ~= 0
        and isMouseInside(G.mouse, x, y, rd32(button + ITEM_WIDTH), rd32(button + ITEM_HEIGHT)) ~= 0
        and (localName(candidate.name) or candidate.lines())
      if shown and candidate.name ~= nil then   -- a name on the description line, like the game's
        writeCString(lineBuffers[1], shown)
        local layer = rd32(G.textLayer)
        wr32(G.textLayer, MAP_LAYER)
        shadowedText(G.textManager, lineBuffers[1], rd32(G.menu + MENU_X) + G.describeAt[1] + rd32(G.cameraX),
          rd32(G.menu + MENU_Y) + G.describeAt[2] + rd32(G.cameraY), ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
        wr32(G.textLayer, layer)
        return
      end
      if shown then
        local widest = 0
        for i, text in ipairs(shown) do
          writeCString(lineBuffers[i], text)
          widest = math.max(widest, textWidth(G.textManager, lineBuffers[i], #text, TOOLTIP_FONT))
        end
        local left = x + rd32(G.cameraX)
        local right = left + widest + 2 * TOOLTIP_PADDING
        local bottom = rd32(G.menu + MENU_Y) + TOOLTIP_BOTTOM + rd32(G.cameraY) - (candidate.raise or 0)
        local top = bottom - #shown * TOOLTIP_LINE - TOOLTIP_PADDING
        local target = rd32(G.pencil + PENCIL_TARGET)
        wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
        roundedBox(G.pencil, left, top, right, bottom, BOX_BLEND)
        wr32(G.pencil + PENCIL_TARGET, target)
        local layer = rd32(G.textLayer)
        wr32(G.textLayer, MAP_LAYER)
        for i = 1, #shown do
          shadowedText(G.textManager, lineBuffers[i], left + TOOLTIP_PADDING,
            top + TOOLTIP_PADDING // 2 + (i - 1) * TOOLTIP_LINE, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT,
            0, 0)
        end
        wr32(G.textLayer, layer)
        return
      end
    end
  end
end

---------------------------------------------------------------------------------------
-- Rows of buttons above the panel: trees, shrubs, rocks
---------------------------------------------------------------------------------------

-- What the tree panel shows for the chosen tool: the felled trees of the chosen tree, or the
-- five shrubs, and with random mixes on a random standing tree (the tree's own button picture),
-- a random felled tree and a random shrub. Each entry: its item, a game sprite (gm, picture,
-- palette) or button image, the param its click gets, whether it is the chosen one, a label and
-- the counter to show on it.
local function makeTreeEntries(G, O, data, panel)
  local function stage()
    if not O.growth then return PLACED_STAGE end
    return math.max(0, math.min(MAX_STAGE, rd32(G.brush) - 1))
  end
  return function(command)
    local list = {}
    if O.felled and command >= FIRST_TREE_COMMAND and command <= LAST_TREE_COMMAND then
      local treeType, treeStage = G.plantTypes[command], stage()
      local most = math.min(rd32(G.logs + (treeType * STAGES + treeStage) * 4), MOST_LOGS)
      if treeStage == 0 then most = K.SMALLEST_FELLED_LOGS end
      local gm = rd16(G.typeGm + treeType * 4)
      local felledLogs, felledCommand = rd32(data.felledLogs), rd32(data.felledCommand)
      local function add(entry)
        entry.item = panel.felled[#list + 1]
        entry.chosen = felledLogs == entry.param and felledCommand == command
        list[#list + 1] = entry
      end
      local function felledPicture(logs)
        local shown = math.max(treeStage, K.SMALLEST_FELLED_STAGE)   -- see stageFromBrush
        return FELLED_PICTURE_BASE[math.min(shown, 4)] - logs
      end
      add({ image = panel.images[command], param = 0 })   -- the standing tree
      list[1].chosen = felledLogs == 0 or felledCommand ~= command
      if O.randomMix and treeStage >= 1 and treeStage <= K.MOST_RANDOM_STAGE then
        add({ image = panel.images[command], param = K.RANDOM_STANDING, label = K.RANDOM_LABEL })
      end
      for logs = most, 1, -1 do
        add({ gm = gm, picture = felledPicture(logs), palette = FELLED_PALETTE, param = logs })
      end
      if O.randomMix and most >= 2 then
        add({ gm = gm, picture = felledPicture(most), palette = FELLED_PALETTE, param = K.RANDOM_FELLED,
          label = K.RANDOM_LABEL })
      end
    elseif O.shrubs then
      local random = O.randomMix and rd8(data.randomShrub) ~= 0
      for i, shrub in ipairs(SHRUB_COMMANDS) do
        local shrubType = G.plantTypes[shrub]
        list[i] = { item = panel.shrubs[i], gm = rd16(G.typeGm + shrubType * 4), picture = SHRUB_PICTURE,
          palette = SHRUB_PALETTES[shrubType] or 0, chosen = command == shrub and not random,
          count = data.typeCounts and (data.typeCounts + shrubType * 4) }
      end
      if O.randomMix then
        local shrubType = G.plantTypes[SHRUB_COMMANDS[1]]
        list[#list + 1] = { item = panel.randomShrub, gm = rd16(G.typeGm + shrubType * 4), picture = SHRUB_PICTURE,
          palette = SHRUB_PALETTES[shrubType] or 0, chosen = random, label = K.RANDOM_LABEL }
      end
    end
    return list
  end
end

-- What the rock panel shows: the four variants of the chosen size, as the map would draw them
-- now (rotation and turn), and at size 1x1 the extra rock (number 16: type 0, base 0).
local function makeRockEntries(G, O, data, panel, rockPicture)
  return function(command)
    local size = rd32(G.chosenRockSize)
    if size < 0 or size > 3 then return {} end
    local lock = rd32(data.rockLock)
    if lock == K.EXTRA_VARIANT + 1 and size ~= 0 then
      wr32(data.rockLock, 0)                   -- the extra rock exists at 1x1 only
      lock = 0
    end
    local rotation = rd32(G.tileMap + K.TILE_MAP.rotation)
    local list = {}
    for v = 0, K.ROCK_VARIANTS - 1 do
      local base = rd32(G.rockBases + (size * K.ROCK_VARIANTS + v) * 4)
      local picture = rockPicture(size + 1, base, rotation)
      if picture == nil then return {} end
      list[#list + 1] = { item = panel.rocks[v + 1], picture = picture, param = v + 1, chosen = lock == v + 1 }
    end
    if O.extraRock and size == 0 then
      local picture = rockPicture(1, 0, rotation)
      if picture == nil then return {} end
      list[#list + 1] = { item = panel.rocks[K.EXTRA_VARIANT + 1], picture = picture,
        param = K.EXTRA_VARIANT + 1, chosen = lock == K.EXTRA_VARIANT + 1 }
    end
    return list
  end
end

-- The tooltip, drawn before the panels, again on top of them (see buildTable).
local function drawTooltipOnTop(data)
  if data.tooltip ~= nil then
    data.tooltipLate = true
    data.tooltip()
  end
end

-- Draws a row of buttons above the panel, where editor/lane.lua places it (squeezed together
-- when wider than the screen), on the map surface like the description line, and lays out the row's items to
-- match. Every frame while the panel is shown; the panel item hides the items otherwise.
-- The variant locks, shared by the castle panels and the pipette: the building variant the
-- rotation leaves alone (its placement id), and the hovel variant + 1 (0: the game's own).
function C.locks()
  C.lockWords = C.lockWords or { variant = core.allocate(4, true), hovel = core.allocate(4, true),
    ruined = core.allocate(4, true) }               -- and the ruined cathedral choice (1)
  return C.lockWords
end

-- A chosen variant stays chosen, a chosen hovel variant is placed every time (map editor).
function C.patchVariantLocks(self, G)
  local locks = C.locks()
  local turn = scan(K.AOB_VARIANT_TURN, "the variant rotation")
  local T = K.VARIANT_TURN
  C.patchJump(self, turn, T.size, core.allocateAssembly(templates.variantLock, {
    SUBTYPE = G.subtype, VARIANT_LOCK = locks.variant, TURN_ADD = rd32(turn + T.add) & 0xFFFFFFFF,
    TURN_END = turn + T.endRel + 1 + (rd8(turn + T.endRel) & 0xFF), BACK = turn + T.size,
  }))
  local hovel = scan(K.AOB_HOVEL_VARIANT, "the hovel variants")
  local H = K.HOVEL_VARIANT
  local counter = rd32(hovel + H.counter)
  C.patchJump(self, hovel, H.size, core.allocateAssembly(templates.hovelVariant, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, HOVEL_LOCK = locks.hovel, COUNTER = counter,
    BACK = hovel + H.size,
  }))
  local preview = scan(K.AOB_HOVEL_PREVIEW, "the hovel preview") + K.HOVEL_PREVIEW.site
  C.patchJump(self, preview, K.HOVEL_PREVIEW.size, core.allocateAssembly(templates.hovelPreview, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, HOVEL_LOCK = locks.hovel, COUNTER = counter,
    BACK = preview + K.HOVEL_PREVIEW.size,
  }))
  local advance = hovel + H.advance
  C.patchJump(self, advance, H.advanceSize, core.allocateAssembly(templates.hovelAdvance, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, HOVEL_LOCK = locks.hovel, COUNTER = counter,
    SKIP = hovel + H.skipRel + 1 + (rd8(hovel + H.skipRel) & 0xFF), BACK = advance + H.advanceSize,
  }))
end

-- A cathedral placed in the map editor while "Ruined" is chosen gets the ruined picture. Placing
-- leaves the new building's id at TileMapState + 0x554888; a check every frame (castle menu,
-- pipette) sees a new one there. (ClickPlaceBuilding's call to placeBuilding is not hooked:
-- interface-visual-fixes checks that call and its return address.)
function C.ruinWatch(G)
  if C.watchRuins ~= nil then return C.watchRuins end
  local ruined = scan(K.AOB_RUINED_CATHEDRAL, "the ruined cathedral")
  local RC = K.RUINED_CATHEDRAL
  local flagField, pictureField = rd32(ruined + RC.flag), rd32(ruined + RC.pictureField)
  local picture, tileMap = rd32(ruined + RC.picture), rd32(ruined + RC.tileMap)
  local update = core.exposeCode(readCallTarget(ruined, RC.update, "updateBuildingGraphicsLayer"), 2, 1)
  local stride = rd32(scan(K.AOB_BUILDING_TYPE, "the building types") + K.BUILDING_TYPE.stride)
  local gameMode = rd32(scan(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND)
  local choice = C.locks().ruined
  local warned = false
  -- The ruin is 169 pictures from RUINED on in tile_churches.gm1; older copies end before it.
  local function ruinThere(id)
    local gm = rd16(pictureField + K.GM_AFTER_PICTURE + id * stride)
    local first, after = rd32(G.firstPictures + gm * 4), rd32(G.firstPictures + (gm + 1) * 4)
    if after > first and picture + K.RUIN_PARTS - 1 <= after - first then return true end
    if not warned then
      warned = true
      log(WARNING, MODULE_NAME .. ": this game's tile_churches.gm1 has no ruined cathedral (it ends at picture "
        .. (after - first) .. "); cathedrals are placed whole")
    end
    return false
  end
  local seen = rd32(tileMap + K.LAST_PLACED)
  C.watchRuins = function()
    local id = rd32(tileMap + K.LAST_PLACED)
    if id == seen then return end
    seen = id
    if rd32(gameMode) ~= K.MAP_EDITOR or rd32(choice) ~= 1 or id <= 0 then return end
    if rd16(pictureField + K.TYPE_AFTER_PICTURE + id * stride) ~= K.CATHEDRAL_TYPE then return end
    if not ruinThere(id) then return end
    wr16(flagField + id * stride, 1)
    wr32(pictureField + id * stride, picture)
    update(tileMap, id)
  end
  return C.watchRuins
end

-- The rects a menu's guard keeps off the map (see K.GUARD_RECTS).
function C.guardRects(data)
  data.rects = core.allocate((K.GUARD_RECTS + 1) * K.RECT_SIZE, true)
  wr32(data.rects + K.GUARD_RECTS * K.RECT_SIZE, -1)
  data.nextRect = 0
  -- The floating items, which editor/lane.lua places, and the module's fixed boxes there.
  data.floating, data.laneExtra = {}, {}
end
function C.takeRect(data)
  if data == nil or data.rects == nil or data.nextRect >= K.GUARD_RECTS then return nil end
  local rect = data.rects + data.nextRect * K.RECT_SIZE
  data.nextRect = data.nextRect + 1
  return rect
end
function C.markRect(rect, x, y, width, height)
  if rect == nil then return end
  wr32(rect + 4, math.floor(x))
  wr32(rect + 8, math.floor(y))
  wr32(rect + 12, math.floor(width))
  wr32(rect + 16, math.floor(height))
  wr32(rect, 1)
end

local function makePanel(G, O, data, panel, entries)
  local rect = C.takeRect(data)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local colourBox = core.exposeCode(G.colourBox, 6, 1)
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local renderNumber = core.exposeCode(G.renderNumber, 10, 1)
  local blit = core.exposeCode(G.blit, 3, 0)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local labelBuffer = core.allocate(16, true)
  local spriteBox = makeSpriteBoxes(G)

  -- A button image's gm, picture and size; nil while it is not loaded.
  local function image(index)
    local entry = G.buttonImages + index * IMAGE_SIZE
    local gm, picture = rd32(entry), rd32(entry + 4)
    local first = rd32(G.firstPictures + gm * 4)
    if first <= 0 then return nil end
    local header = G.pictureHeights - 2 + (first + picture - 1) * PICTURE_SIZE
    local width, height = rd16(header), rd16(header + 2)
    if width <= 0 or height <= 0 then return nil end
    return { gm = gm, picture = picture, width = width, height = height }
  end

  local function drawSprite(entry, x, y)
    local t = G.textures
    local mode, direct = rd32(t + TEXTURES_MODE), rd32(t + TEXTURES_DIRECT_PALETTE)
    local sprite, palette = rd32(G.sprite), rd32(G.spritePalette)
    wr32(t + TEXTURES_MODE, MAP_LAYER)
    wr32(t + TEXTURES_DIRECT_PALETTE, 1)
    wr32(G.sprite, entry.gm)
    wr32(G.spritePalette, entry.palette)
    renderGM(t, entry.gm, entry.picture, x, y)
    wr32(G.sprite, sprite)
    wr32(G.spritePalette, palette)
    wr32(t + TEXTURES_DIRECT_PALETTE, direct)
    wr32(t + TEXTURES_MODE, mode)
  end

  return function()
    local list = entries(rd32(G.subtype))
    for _, address in ipairs(panel.items) do wr16(address + ITEM_HIDDEN, 1) end
    if #list == 0 then return end
    local tallest = 0
    for _, entry in ipairs(list) do
      if entry.gm ~= nil then
        entry.box = spriteBox(entry.gm, entry.picture)
        if entry.box == nil then return end    -- the pictures are not loaded yet
      elseif entry.image ~= nil then
        entry.button = image(entry.image)
        if entry.button == nil then return end
        entry.box = { x = 0, y = 0, width = entry.button.width, height = entry.button.height }
        if entry.image2 ~= nil then              -- a second picture right of the first
          entry.button2 = image(entry.image2)
          if entry.button2 == nil then return end
          entry.box.width = entry.button.width + K.PANEL_PICTURE_GAP + entry.button2.width
          entry.box.height = math.max(entry.button.height, entry.button2.height)
        end
      else
        entry.box = { x = 0, y = 0, width = entry.picture.width, height = entry.picture.height }
      end
      tallest = math.max(tallest, entry.box.height)
    end

    local height = tallest + 2 * PANEL_PADDING + (list.labelRoom or 0)   -- labelRoom: labels above the pictures
    local sum = 0
    for _, entry in ipairs(list) do
      entry.width = entry.box.width + 2 * PANEL_PADDING
      entry.inset = PANEL_PADDING
      if entry.minWidth ~= nil and entry.width < entry.minWidth then   -- room for a long label
        entry.inset = PANEL_PADDING + (entry.minWidth - entry.width) // 2
        entry.width = entry.minWidth
      end
      sum = sum + entry.width
    end
    local screen = rd32(G.screenWidth)
    local gap = PANEL_GAP
    local room = screen - 2 * PANEL_MARGIN - 2 * PANEL_GAP   -- the screen less the box's own edge
    if #list > 1 and sum + gap * (#list - 1) > room then
      gap = (room - sum) / (#list - 1)
    end
    local total = sum + gap * (#list - 1)
    local menuX = rd32(G.menu + MENU_X)
    -- The panel's box in the band: the entries (or the line above them, when wider: the pipette's),
    -- PANEL_GAP around them and the room above. The entries sit in its middle.
    local above = list.rectAbove or 0
    local inside = math.max(math.ceil(total), list.aboveWidth or 0)
    local boxLeft, boxTop = lane.spot(G, data, panel, inside + 2 * PANEL_GAP, height + 2 * PANEL_GAP + above)
    local top = boxTop + above + PANEL_GAP
    local bottom = top + height
    local x = boxLeft + PANEL_GAP + (inside - total) / 2
    local left = math.floor(x + 0.5)
    for _, entry in ipairs(list) do
      entry.x = math.floor(x + 0.5)
      wr32(entry.item + ITEM_X, entry.x)
      wr32(entry.item + ITEM_Y, top)
      wr32(entry.item + ITEM_WIDTH, entry.width)
      wr32(entry.item + ITEM_HEIGHT, height)
      if entry.param ~= nil then wr32(entry.item + ITEM_PARAM, entry.param) end
      wr16(entry.item + ITEM_HIDDEN, 0)
      x = x + entry.width + gap
    end
    local right = math.floor(x - gap + 0.5)
    C.markRect(rect, left - PANEL_GAP, top - PANEL_GAP - above, right - left + 2 * PANEL_GAP,
      bottom - top + 2 * PANEL_GAP + above)

    local offsetX = menuX - rd32(G.menu + MENU_SCROLL) + rd32(G.cameraX)
    local offsetY = rd32(G.menu + MENU_Y) + rd32(G.cameraY)
    local white = rd32(G.pixelFormat) == 0x565 and 0xFFFF or 0x7FFF
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, offsetX + left - PANEL_GAP, offsetY + top - PANEL_GAP,
      offsetX + right + PANEL_GAP, offsetY + bottom + PANEL_GAP, BOX_BLEND)
    for _, entry in ipairs(list) do
      local l, r = offsetX + entry.x, offsetX + entry.x + entry.width - 1
      local upper, lower = offsetY + top, offsetY + bottom - 1
      if rd16(entry.item + ITEM_HOVERED) ~= 0 then
        roundedBox(G.pencil, l, upper, r, lower, BOX_BLEND)
      end
      if entry.chosen then
        colourBox(G.pencil, l, upper, r, upper + 1, white)
        colourBox(G.pencil, l, lower - 1, r, lower, white)
        colourBox(G.pencil, l, upper, l + 1, lower, white)
        colourBox(G.pencil, r - 1, upper, r, lower, white)
      end
    end
    for _, entry in ipairs(list) do
      local sx = offsetX + entry.x + entry.inset - entry.box.x
      local sy = offsetY + bottom - PANEL_PADDING - entry.box.height - entry.box.y
      if entry.gm == nil and entry.button == nil then blit(entry.picture.address, sx, sy) end
    end
    wr32(G.pencil + PENCIL_TARGET, target)
    for _, entry in ipairs(list) do
      local sx = offsetX + entry.x + entry.inset - entry.box.x
      local sy = offsetY + bottom - PANEL_PADDING - entry.box.height - entry.box.y
      if entry.gm ~= nil then
        drawSprite(entry, sx, sy)
      elseif entry.button ~= nil then
        local mode = rd32(G.textures + TEXTURES_MODE)
        wr32(G.textures + TEXTURES_MODE, MAP_LAYER)
        local first, second = entry.button, entry.button2
        renderGM(G.textures, first.gm, first.picture, sx, sy + entry.box.height - first.height)
        if second ~= nil then
          renderGM(G.textures, second.gm, second.picture, sx + first.width + K.PANEL_PICTURE_GAP,
            sy + entry.box.height - second.height)
        end
        wr32(G.textures + TEXTURES_MODE, mode)
      end
    end
    -- Labels (the random mixes' "?"), at the top of their button.
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    for _, entry in ipairs(list) do
      if entry.label ~= nil then
        writeCString(labelBuffer, entry.label)
        local width = textWidth(G.textManager, labelBuffer, #entry.label, TOOLTIP_FONT)
        shadowedText(G.textManager, labelBuffer, offsetX + entry.x + (entry.width - width) // 2,
          offsetY + top + PANEL_PADDING, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
      end
    end
    wr32(G.textLayer, layer)
    if O.counts and rd8(data.shown) ~= 0 then
      local layer = rd32(G.textLayer)
      wr32(G.textLayer, MAP_LAYER)
      for _, entry in ipairs(list) do
        if entry.count ~= nil then
          renderNumber(G.textManager, rd32(entry.count), offsetX + entry.x + entry.width // 2,
            offsetY + bottom - NUMBER_FROM_BOTTOM, 1, NUMBER_COLOUR, 0, NUMBER_FONT, 0, 0)
        end
      end
      wr32(G.textLayer, layer)
    end

    -- The "i" was drawn before the panel (it belongs to the part of the menu that is always
    -- shown); draw it again on top, the way its own renderer does (picture + 1 under the mouse).
    if panel.info ~= nil then
      local image = G.buttonImages + INFO_IMAGE * IMAGE_SIZE
      local picture = rd32(image + 4)
      if rd16(panel.info + ITEM_HOVERED) ~= 0 then picture = picture + 1 end
      local mode = rd32(G.textures + TEXTURES_MODE)
      wr32(G.textures + TEXTURES_MODE, MAP_LAYER)
      renderGM(G.textures, rd32(image), picture, offsetX + rd32(panel.info + ITEM_X),
        offsetY + rd32(panel.info + ITEM_Y))
      wr32(G.textures + TEXTURES_MODE, mode)
    end
    drawTooltipOnTop(data)
  end
end

---------------------------------------------------------------------------------------
-- The herd panel above the Animals menu
---------------------------------------------------------------------------------------

-- Two lines of text in a box placed by editor/lane.lua: the chosen animal's herd (base + random
-- part, or 2 x brush - 1 with the check box on) and troop type, and the check box with its
-- label. The check box item is placed under its picture.
local function makeHerdPanel(G, O, data, herd)
  local rect = C.takeRect(data)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local buffers = { core.allocate(128, true), core.allocate(128, true) }
  local owner = { items = { herd.checkBox } }        -- what editor/lane.lua places

  return function()
    wr16(herd.checkBox + ITEM_HIDDEN, 1)
    local animal = G.herds[rd32(G.subtype)]
    if animal == nil then return end
    local brush = rd32(G.brush)
    local size
    if rd8(data.herdSync) ~= 0 then
      size = string.format("2 x brush %d - 1 = %d animals", brush, 2 * brush - 1)
    else
      size = string.format("%d + 0 to %d animals", animal.base, animal.mask)
    end
    local texts = {
      string.format("%s herd: %s, group behaviour type %d", animal.name, size, animal.group),
      "Herd size from the brush size: 2 x brush - 1",
    }
    local widths = {}
    for i, text in ipairs(texts) do
      writeCString(buffers[i], text)
      widths[i] = textWidth(G.textManager, buffers[i], #text, TOOLTIP_FONT)
    end
    local line = math.max(TOOLTIP_LINE, K.CHECK_BOX_SIZE + 2)
    local width = math.max(widths[1], K.CHECK_BOX_SIZE + TOOLTIP_PADDING + widths[2]) + 2 * TOOLTIP_PADDING
    local height = TOOLTIP_LINE + line + 2 * TOOLTIP_PADDING
    local menuX = rd32(G.menu + MENU_X)
    local left, top = lane.spot(G, data, owner, width, height)
    local bottom = top + height
    local boxX, boxY = left + TOOLTIP_PADDING, top + TOOLTIP_PADDING + TOOLTIP_LINE
    C.markRect(rect, left, top, width, bottom - top)
    wr32(herd.checkBox + ITEM_X, boxX)
    wr32(herd.checkBox + ITEM_Y, boxY)
    wr32(herd.checkBox + ITEM_WIDTH, K.CHECK_BOX_SIZE)
    wr32(herd.checkBox + ITEM_HEIGHT, K.CHECK_BOX_SIZE)
    wr16(herd.checkBox + ITEM_HIDDEN, 0)

    local offsetX = menuX - rd32(G.menu + MENU_SCROLL) + rd32(G.cameraX)
    local offsetY = rd32(G.menu + MENU_Y) + rd32(G.cameraY)
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, offsetX + left, offsetY + top, offsetX + left + width, offsetY + bottom, BOX_BLEND)
    wr32(G.pencil + PENCIL_TARGET, target)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    shadowedText(G.textManager, buffers[1], offsetX + left + TOOLTIP_PADDING, offsetY + top + TOOLTIP_PADDING // 2,
      ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    shadowedText(G.textManager, buffers[2], offsetX + boxX + K.CHECK_BOX_SIZE + TOOLTIP_PADDING,
      offsetY + boxY + (K.CHECK_BOX_SIZE - TOOLTIP_LINE) // 2 + 2, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    wr32(G.textLayer, layer)

    local image = G.buttonImages + (rd8(data.herdSync) ~= 0 and K.CHECKED_IMAGE or K.UNCHECKED_IMAGE) * IMAGE_SIZE
    local picture = rd32(image + 4)
    if rd16(herd.checkBox + ITEM_HOVERED) ~= 0 then picture = picture + 1 end
    local mode = rd32(G.textures + TEXTURES_MODE)
    wr32(G.textures + TEXTURES_MODE, MAP_LAYER)
    renderGM(G.textures, rd32(image), picture, offsetX + boxX, offsetY + boxY)
    wr32(G.textures + TEXTURES_MODE, mode)
    drawTooltipOnTop(data)
  end
end

---------------------------------------------------------------------------------------
-- Spreading rows of buttons over the panel
---------------------------------------------------------------------------------------

-- Once the buttons' pictures are loaded and the menu has placed them, spread rows of buttons
-- evenly between ROW_LEFT and ROW_RIGHT. Buttons keep their height; new ones (in `added`) are
-- centred on their left neighbour. A row with `bottom` set stands its buttons on a common
-- line instead (the lowest bottom edge among them). Buttons with their own pictures have their
-- size in `sizeOf`, the others are measured by their gm picture. Moved buttons are taken off
-- the user control table, which would put them back the next time the menu loads. Each of
-- `places` puts one more item somewhere once it can (it answers whether it has).
local function makeLayout(G, rows, added, sizeOf, places, finishes)
  local function measure(address)
    local size = sizeOf[address]
    if size ~= nil then return size[1], size[2] end
    return lane.measurePicture(G, address)
  end

  return function()
    for _, place in ipairs(places or {}) do
      if not place(measure) then return false end
    end
    for _, row in ipairs(rows) do
      local widths, heights, sum = {}, {}, 0
      for i, address in ipairs(row) do
        local width, height = measure(address)
        if width == nil then return false end
        if not added[address] and (rd32(address + ITEM_X) & 0xFFFFFFFF) == PLACED_BY_CONTROL then
          return false                         -- the menu has not been loaded yet
        end
        widths[i], heights[i], sum = width, height, sum + width
      end
      row.widths, row.heights, row.sum = widths, heights, sum
    end
    for _, row in ipairs(rows) do
      local line = nil
      if row.bottom then
        for i, address in ipairs(row) do
          if not added[address] then line = math.max(line or 0, rd32(address + ITEM_Y) + row.heights[i]) end
        end
      end
      local gap = (ROW_RIGHT - ROW_LEFT - row.sum) / (#row - 1)
      local x, y, h = ROW_LEFT, nil, nil
      for i, address in ipairs(row) do
        if line ~= nil then
          wr32(address + ITEM_Y, line - row.heights[i])
        elseif added[address] then
          wr32(address + ITEM_Y, y + (h - row.heights[i]) // 2)
        else
          y, h = rd32(address + ITEM_Y), row.heights[i]
        end
        wr32(address + ITEM_X, math.floor(x + 0.5))
        wr16(address + ITEM_CONTROL, -1)
        wr16(address + ITEM_HIDDEN, 0)
        x = x + row.widths[i] + gap
      end
    end
    for _, finish in ipairs(finishes or {}) do finish() end
    return true
  end
end

return {
  makeTooltip = makeTooltip,
  makeTreeEntries = makeTreeEntries,
  makeRockEntries = makeRockEntries,
  drawTooltipOnTop = drawTooltipOnTop,
  makePanel = makePanel,
  makeHerdPanel = makeHerdPanel,
  makeLayout = makeLayout,
}
