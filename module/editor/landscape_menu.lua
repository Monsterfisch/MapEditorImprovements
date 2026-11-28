local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local ITEM_COUNT = layout.ITEM_COUNT
local MAP_CLICK_ITEM = layout.MAP_CLICK_ITEM
local MENU_ITEM_SIZE = layout.MENU_ITEM_SIZE
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_PARAM = layout.ITEM_PARAM
local ITEM_RENDER = layout.ITEM_RENDER
local ITEM_IMAGE = layout.ITEM_IMAGE
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_HOVERED = layout.ITEM_HOVERED
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local ITEM_MENU = layout.ITEM_MENU
local TYPE_EVERY_FRAME = layout.TYPE_EVERY_FRAME
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local RENDER_NONE = layout.RENDER_NONE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local RENDER_IMAGE = layout.RENDER_IMAGE
local PLACED_BY_CONTROL = layout.PLACED_BY_CONTROL
local IMAGE_INDEX_MASK = layout.IMAGE_INDEX_MASK
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local MENU_SCROLL = layout.MENU_SCROLL
local HOVER_TEXT_ITEM = layout.HOVER_TEXT_ITEM
local INFO_IMAGE = layout.INFO_IMAGE
local INFO_BUTTON = layout.INFO_BUTTON
local INFO_BEFORE_ITEM = layout.INFO_BEFORE_ITEM
local HOVER_TEXT_MOVED_X = layout.HOVER_TEXT_MOVED_X
local TEXTURES = layout.TEXTURES
local VEGETATION = layout.VEGETATION
local ANIMALS = layout.ANIMALS
local ROCKS = layout.ROCKS
local FIRST_TREE_COMMAND = layout.FIRST_TREE_COMMAND
local LAST_TREE_COMMAND = layout.LAST_TREE_COMMAND
local SHRUB_COMMANDS = layout.SHRUB_COMMANDS
local APPLE_COMMAND = layout.APPLE_COMMAND
local APPLE_TYPE = layout.APPLE_TYPE
local GRAVEL_COMMAND = layout.GRAVEL_COMMAND
local IRON_COMMAND = layout.IRON_COMMAND
local TEXTURE_ROWS = layout.TEXTURE_ROWS
local VEGETATION_TREES = layout.VEGETATION_TREES
local TOP_ROW_SHRUB = layout.TOP_ROW_SHRUB
local SORTED_SHRUBS = layout.SORTED_SHRUBS
local ROW_RIGHT = layout.ROW_RIGHT
local OBSTACLES_BUTTON = layout.OBSTACLES_BUTTON
local K = layout.K
local C = layout.C
local IMAGE_SIZE = layout.IMAGE_SIZE
local NUMBER_FONT = layout.NUMBER_FONT
local NUMBER_COLOUR = layout.NUMBER_COLOUR
local NUMBER_FROM_BOTTOM = layout.NUMBER_FROM_BOTTOM
local PENCIL_TARGET = layout.PENCIL_TARGET
local TREE_TYPE_FROM_IN_USE = layout.TREE_TYPE_FROM_IN_USE
local TREE_TYPES = layout.TREE_TYPES
local MOST_LOGS = layout.MOST_LOGS
local memory = require("editor.memory")
local item = memory.item
local dwordList = memory.dwordList
local rd32 = memory.rd32
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local buttonPictures = require("editor.images").buttonPictures
local makeRockPictures = require("editor.sprites").makeRockPictures
local ui = require("editor.ui")
local makeTooltip = ui.makeTooltip
local makeTreeEntries = ui.makeTreeEntries
local makeRockEntries = ui.makeRockEntries
local makePanel = ui.makePanel
local makeHerdPanel = ui.makeHerdPanel
local makeLayout = ui.makeLayout

---------------------------------------------------------------------------------------
-- The new item table
---------------------------------------------------------------------------------------

-- Copies the item table with the module's items inserted (in front of the original item
-- whose index they are listed under) and fills them in.
local function buildTable(G, O, bins)
  local data = {}
  C.guardRects(data)
  local pictures = {}
  if O.apple then pictures.apple = buttonPictures("apple") end
  if O.textures then pictures.gravel = buttonPictures("gravel") end
  local rockTabs, boxTabs = {}, {}
  for _, tab in ipairs({ ROCKS, K.ROCKS_SKIRMISH }) do
    if G.blockEnd[tab] ~= nil then
      if O.variants then rockTabs[#rockTabs + 1] = tab end
      if O.invisibleRocks then boxTabs[#boxTabs + 1] = tab end
    end
  end

  local inserts = {}
  local function insert(before, kind)
    inserts[before] = inserts[before] or {}
    table.insert(inserts[before], kind)
  end
  insert(MAP_CLICK_ITEM, "guard")
  if O.undo then
    insert(MAP_CLICK_ITEM, "undo")
    insert(MAP_CLICK_ITEM, "redo")
  end
  if O.compass then insert(MAP_CLICK_ITEM, "compass") end
  if O.rockPlaced then insert(MAP_CLICK_ITEM, "rockTick") end
  if O.counts then insert(INFO_BEFORE_ITEM, "info") end
  if O.treePreview then insert(INFO_BEFORE_ITEM, "treePreview") end
  local pipetteItems = { "pipetteTick", "pipette", "pipettePanel" }
  if O.pipette then
    insert(MAP_CLICK_ITEM, "pipetteTick")
    insert(INFO_BEFORE_ITEM, "pipette")
    for i = 1, #K.PIPETTE_MODES do
      insert(INFO_BEFORE_ITEM, "pipetteMode" .. i)
      pipetteItems[#pipetteItems + 1] = "pipetteMode" .. i
    end
    insert(INFO_BEFORE_ITEM, "pipettePanel")
  end
  if O.eraserChoice then
    for i = 1, #K.ERASER_MODES do insert(INFO_BEFORE_ITEM, "eraserMode" .. i) end
    insert(INFO_BEFORE_ITEM, "eraserPanel")
  end
  if O.textureMask then insert(G.firstBlock, "maskButton") end
  if O.counts or O.obstacles or O.rocksAndWater or O.invisibleRocks or O.apple or O.textures or O.waterDecorations
      or O.maxHeight or O.lostRocks or O.textureMask or #bins > 0 then
    insert(G.firstBlock, "tooltip")
  end
  if G.blockEnd[K.HEIGHTS_TAB] == nil or G.buttons[K.MIN_HEIGHT_TOOL] == nil then
    if O.maxHeight then log(ERROR, "Max Height is off. The Heights menu could not be found.") end
    if O.heightTools then log(ERROR, "The height brush controls are off. The Heights menu could not be found.") end
    O.maxHeight, O.heightTools = false, false
  end
  for _, kind in ipairs(C.heightItems(O)) do insert(G.blockEnd[K.HEIGHTS_TAB], kind) end
  if O.heightTools then insert(MAP_CLICK_ITEM, "heightTick") end
  local animalsEnd = G.blockEnd[ANIMALS]
  if O.herds then
    insert(animalsEnd, "herdCheck")
    insert(animalsEnd, "herdPanel")
  end
  if O.counts then insert(animalsEnd, "numbers" .. ANIMALS) end
  local binKinds = {}
  for _, bin in ipairs(bins) do
    insert(animalsEnd, bin.kind)
    binKinds[#binKinds + 1] = bin.kind
  end
  local vegetationEnd = G.blockEnd[VEGETATION]
  if O.apple then insert(vegetationEnd, "apple") end
  if O.shrubs then
    for i = 1, #SHRUB_COMMANDS do insert(vegetationEnd, "shrub" .. i) end
    if O.randomMix then insert(vegetationEnd, "randomShrub") end
  end
  local felledButtons = 1 + MOST_LOGS + (O.randomMix and 2 or 0)
  if O.obstacles then insert(vegetationEnd, OBSTACLES_BUTTON) end
  if O.rocksAndWater then insert(vegetationEnd, "rocksAndWater") end
  if O.felled then
    for i = 1, felledButtons do insert(vegetationEnd, "felled" .. i) end
  end
  if O.shrubs or O.felled then insert(vegetationEnd, "panel") end
  if O.counts then insert(vegetationEnd, "numbers" .. VEGETATION) end
  if O.spreadOutlines then insert(vegetationEnd, "spreadOutline") end
  if O.textures then
    insert(G.blockEnd[TEXTURES], "gravel")
    insert(G.blockEnd[TEXTURES], "iron")
  end
  -- New items that are not button copies go after the copies: the menu only gives a copy its
  -- group's renderer while the copies follow the group's buttons with nothing in between.
  if O.textureMask then insert(MAP_CLICK_ITEM, "maskTick") end
  if O.waterDecorations and G.blockEnd[K.WATER] ~= nil then
    for _, decoration in ipairs(K.WATER_DECORATIONS) do insert(G.blockEnd[K.WATER], "water" .. decoration.command) end
  end
  for _, tab in ipairs(rockTabs) do
    for v = 1, K.ROCK_VARIANTS + 1 do insert(G.blockEnd[tab], "rock" .. tab .. "/" .. v) end
    insert(G.blockEnd[tab], "rockPanel" .. tab)
  end
  for _, tab in ipairs(boxTabs) do insert(G.blockEnd[tab], "invisible" .. tab) end
  if O.lostRocks then
    for _, tab in ipairs({ ROCKS, K.ROCKS_SKIRMISH }) do
      if G.blockEnd[tab] ~= nil then insert(G.blockEnd[tab], "lostRocks" .. tab) end
    end
  end

  local count = ITEM_COUNT + 1
  for _, list in pairs(inserts) do count = count + #list end
  local newTable = core.allocate(count * MENU_ITEM_SIZE, true)
  local movedTo, added, slot = {}, {}, 0
  for i = 0, ITEM_COUNT do
    for _, kind in ipairs(inserts[i] or {}) do
      added[kind] = item(newTable, slot)
      slot = slot + 1
    end
    core.writeBytes(item(newTable, slot), core.readBytes(item(G.table, i), MENU_ITEM_SIZE))
    movedTo[i] = slot
    slot = slot + 1
  end
  local function moved(index) return movedTo[index] end
  local function button(param) return item(newTable, moved(G.buttons[param].index)) end
  local function copyOf(param, into)
    core.writeBytes(into, core.readBytes(item(G.table, G.buttons[param].index), MENU_ITEM_SIZE))
  end
  -- A lua function called from injected code: a pad that runs it, switched off after an error.
  local function luaPad(fn, what)
    local pad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
    local broken = false
    core.detourCode(function(registers)
      if not broken then
        local ok, problem = pcall(fn)
        if not ok then
          broken = true
          log(WARNING, string.format("%s: %s stopped after an error: %s", MODULE_NAME, what, tostring(problem)))
        end
      end
      return registers
    end, pad, 5)
    return pad
  end
  -- A button with no picture of its own, never drawn by the menu.
  local function plainButton(into, action)
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(into + ITEM_ACTION, action)
    wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
    wr16(into + ITEM_HIDDEN, 1)
  end

  data.shown = core.allocate(4, true)
  wr32(data.shown, O.shown and 1 or 0)
  data.felledLogs = core.allocate(4, true)
  data.felledCommand = core.allocate(4, true)
  data.rockLock = core.allocate(4, true)
  data.herdSync = core.allocate(4, true)
  data.nearObstacles = core.allocate(4, true)
  data.rocksAndWater = core.allocate(4, true)
  data.randomShrub = core.allocate(4, true)
  data.invisibleRocks = core.allocate(4, true)
  data.seed = core.allocate(4, true)
  wr32(data.seed, os.time())
  local unused = core.allocate(8, true)        -- the panel template's felled tree state, for panels without it
  if next(pictures) ~= nil or #rockTabs > 0 then
    G.blit = core.allocateAssembly(templates.blit, {
      PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
      SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
    })
  end
  local guarded = {}
  local tooltips = {}

  -- Map counts.
  if O.counts then
    data.totals = core.allocate(12, true)
    data.typeCounts = core.allocate(TREE_TYPES * 4, true)
    local countSlots = core.allocateAssembly(templates.countSlots, {
      TYPE_COUNTS = data.typeCounts, TREE_TYPES = TREE_TYPES, TOTALS = data.totals,
      FIRST_TREE = G.firstTree, TREE_SLOTS = G.treeSlots, TREE_SIZE = G.treeSize,
      TREE_TYPE_FROM_IN_USE = TREE_TYPE_FROM_IN_USE,
      FIRST_ROCK = G.firstRock, ROCK_SLOTS = G.rockSlots, ROCK_SIZE = G.rockSize,
      FIRST_GROUP = G.firstGroup, GROUP_SLOTS = G.groupSlots, GROUP_SIZE = G.groupSize,
    })
    wr32(item(newTable, moved(HOVER_TEXT_ITEM), ITEM_RENDER), core.allocateAssembly(templates.descriptionLine, {
      SHOWN = data.shown, COUNT_SLOTS = countSlots, HOVER_RENDER = G.hoverRender,
    }))
    wr32(item(newTable, moved(HOVER_TEXT_ITEM), ITEM_X), HOVER_TEXT_MOVED_X)

    -- The numbers of the Animals and Vegetation tabs: per tab a list of (button, counter).
    local counted = { [ANIMALS] = {}, [VEGETATION] = {} }
    for param, address in pairs(G.animals) do
      table.insert(counted[ANIMALS], button(param))
      table.insert(counted[ANIMALS], address)
    end
    for _, param in ipairs(G.plants) do
      table.insert(counted[VEGETATION], button(param))
      table.insert(counted[VEGETATION], data.typeCounts + G.plantTypes[param] * 4)
    end
    if O.apple then
      table.insert(counted[VEGETATION], added.apple)
      table.insert(counted[VEGETATION], data.typeCounts + APPLE_TYPE * 4)
    end
    local tabNumbers = core.allocateAssembly(templates.tabNumbers, {
      SHOWN = data.shown, ITEM_MENU = ITEM_MENU, ITEM_HIDDEN = ITEM_HIDDEN, MENU_X = MENU_X, MENU_Y = MENU_Y,
      MENU_SCROLL = MENU_SCROLL, ITEM_X = ITEM_X, ITEM_Y = ITEM_Y, ITEM_WIDTH = ITEM_WIDTH,
      ITEM_HEIGHT = ITEM_HEIGHT, NUMBER_FROM_BOTTOM = NUMBER_FROM_BOTTOM, NUMBER_FONT = NUMBER_FONT,
      NUMBER_COLOUR = NUMBER_COLOUR, TEXT_MANAGER = G.textManager, RENDER_NUMBER = G.renderNumber,
    })
    for tab, list in pairs(counted) do
      local numbers = added["numbers" .. tab]
      wr32(numbers + ITEM_TYPE, TYPE_CLICKABLE)    -- no size, so never under the mouse
      wr32(numbers + ITEM_PARAM, dwordList(list))
      wr32(numbers + ITEM_RENDER, tabNumbers)
      wr32(numbers + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    end

    -- The "i" button.
    local info = added.info
    wr32(info + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(info + ITEM_X, INFO_BUTTON[1])
    wr32(info + ITEM_Y, INFO_BUTTON[2])
    wr32(info + ITEM_ACTION, core.allocateAssembly(templates.toggle, { SHOWN = data.shown }))
    wr32(info + ITEM_RENDER, core.allocateAssembly(templates.infoButton, {
      CAMERA_X = G.cameraX, CAMERA_Y = G.cameraY, ITEM_X = G.itemX, ITEM_Y = G.itemY,
      DRAW_MODE = G.drawMode, IMAGE_BUTTON = G.imageButton,
    }))
    wr32(info + ITEM_IMAGE, INFO_IMAGE)
    wr32(info + ITEM_RENDER_TYPE, RENDER_IMAGE)
    wr32(info + ITEM_TEXT, 0)              -- no description, the usual hover sound
    guarded[#guarded + 1] = info
    guarded[#guarded + 1] = 0

    -- The category tooltips.
    local function counts(...)
      local lines = { ... }
      return function()
        if rd8(data.shown) == 0 then return nil end
        local texts = {}
        for i, line in ipairs(lines) do
          texts[i] = line.text ~= nil and line.text() or string.format("%s: %d/%d", line[1], line[2](), line[3])
        end
        return texts
      end
    end
    local birds = { text = function()
      local ok, D = pcall(C.resolveBirds, G)
      if not ok then return "Birds: -" end
      local crows, gulls = C.birdCounts(G, D)
      return string.format("Birds: %d crows, %d/%d seagulls", crows, gulls, D.gullSlots - 1)
    end }
    tooltips[#tooltips + 1] = { item = button(ANIMALS), lines = counts(
      { "Animals and units", function() return rd32(G.units) end, G.unitMax or G.unitLimit },
      { "Herds and groups", function() return rd32(data.totals + 8) end, G.groupSlots }, birds) }
    tooltips[#tooltips + 1] = { item = button(VEGETATION), lines = counts(
      { "Trees and shrubs", function() return rd32(data.totals) end, G.treeSlots }) }
    tooltips[#tooltips + 1] = { item = button(ROCKS), lines = counts(
      { "Rocks", function() return rd32(data.totals + 4) end, G.rockSlots }) }
  end

  -- Buttons drawn from PNG pictures: a copy of a button of their tab, their own command and
  -- pictures, hidden until laid out.
  local function pictureButton(into, model, command, set)
    copyOf(model, into)
    wr32(into + ITEM_X, 0)
    wr32(into + ITEM_Y, 0)
    wr32(into + ITEM_WIDTH, set.width)
    wr32(into + ITEM_HEIGHT, set.height)
    wr32(into + ITEM_PARAM, command)
    wr32(into + ITEM_IMAGE, 0)
    wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(into + ITEM_TEXT, 0)
    wr16(into + ITEM_HIDDEN, 1)
    wr32(into + ITEM_RENDER, core.allocateAssembly(templates.pictureButton, {
      NORMAL = set.normal, HOVERED = set.hover, CHOSEN = set.chosen, COMMAND = command,
      SUBTYPE = G.subtype, HOVER = G.hover, PENCIL = G.pencil, PENCIL_TARGET = PENCIL_TARGET,
      ITEM_X = G.itemX, ITEM_Y = G.itemY, BLIT = G.blit,
    }))
  end

  local rows, newButtons, sizeOf = {}, {}, {}
  local hoverText = item(newTable, moved(HOVER_TEXT_ITEM))
  G.describeAt = { rd32(hoverText + ITEM_X), rd32(hoverText + ITEM_Y) }
  if O.apple then
    tooltips[#tooltips + 1] = { item = added.apple, name = K.NAMES.apple }
    pictureButton(added.apple, VEGETATION_TREES[1], APPLE_COMMAND, pictures.apple)
    sizeOf[added.apple] = { pictures.apple.width, pictures.apple.height }
    newButtons[added.apple] = true
  end

  -- The obstacles check box: in the Vegetation menu, drawn like the menu's buttons.
  if O.obstacles then
    local box = added[OBSTACLES_BUTTON]
    wr32(box + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(box + ITEM_WIDTH, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_HEIGHT, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_ACTION, core.allocateAssembly(templates.flip, { FLAG = data.nearObstacles }))
    wr32(box + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(box + ITEM_RENDER, core.allocateAssembly(templates.checkBox, {
      FLAG = data.nearObstacles, ON_IMAGE = G.buttonImages + K.CHECKED_IMAGE * IMAGE_SIZE,
      OFF_IMAGE = G.buttonImages + K.UNCHECKED_IMAGE * IMAGE_SIZE,
      HOVER = G.hover, DRAW_MODE = G.drawMode, ITEM_X = G.itemX, ITEM_Y = G.itemY,
      TEXTURES = G.textures, RENDER_GM = G.renderGM,
    }))
    wr16(box + ITEM_HIDDEN, 1)
    sizeOf[box] = { K.CHECK_BOX_SIZE, K.CHECK_BOX_SIZE }
    newButtons[box] = true
    tooltips[#tooltips + 1] = { item = box, lines = function()
      return { "Trees next to obstacles: " .. (rd8(data.nearObstacles) ~= 0 and "allowed" or "not allowed") }
    end, raise = K.CHECK_BOX_TOOLTIP_RAISE }
  end

  -- The Vegetation on rocks and water check box: right of the Vegetation menu, below the
  -- obstacles check box (which moves up and left to make room).
  local finishes = {}
  if O.obstacles then
    local box = added[OBSTACLES_BUTTON]
    finishes[#finishes + 1] = function()
      wr32(box + ITEM_X, rd32(box + ITEM_X) + K.OBSTACLES_NUDGE[1])
      wr32(box + ITEM_Y, rd32(box + ITEM_Y) + K.OBSTACLES_NUDGE[2])
    end
  end
  if O.rocksAndWater then
    local box = added.rocksAndWater
    wr32(box + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(box + ITEM_WIDTH, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_HEIGHT, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_ACTION, core.allocateAssembly(templates.flip, { FLAG = data.rocksAndWater }))
    wr32(box + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(box + ITEM_RENDER, core.allocateAssembly(templates.checkBox, {
      FLAG = data.rocksAndWater, ON_IMAGE = G.buttonImages + K.CHECKED_IMAGE * IMAGE_SIZE,
      OFF_IMAGE = G.buttonImages + K.UNCHECKED_IMAGE * IMAGE_SIZE,
      HOVER = G.hover, DRAW_MODE = G.drawMode, ITEM_X = G.itemX, ITEM_Y = G.itemY,
      TEXTURES = G.textures, RENDER_GM = G.renderGM,
    }))
    wr16(box + ITEM_HIDDEN, 1)
    tooltips[#tooltips + 1] = { item = box, lines = function()
      return { "Vegetation on rocks and water: " .. (rd8(data.rocksAndWater) ~= 0 and "allowed" or "not allowed") }
    end, raise = K.CHECK_BOX_TOOLTIP_RAISE }
    local above = O.obstacles and added[OBSTACLES_BUTTON] or nil
    local top = button(VEGETATION_TREES[1])
    finishes[#finishes + 1] = function()
      if above ~= nil then
        wr32(box + ITEM_X, rd32(above + ITEM_X))
        wr32(box + ITEM_Y, rd32(above + ITEM_Y) + K.CHECK_BOX_SIZE + K.ROCKS_AND_WATER_GAP)
      else
        wr32(box + ITEM_X, ROW_RIGHT + K.CHECK_BOX_GAP)
        wr32(box + ITEM_Y, rd32(top + ITEM_Y))
      end
      wr16(box + ITEM_HIDDEN, 0)
    end
  end

  -- The Vegetation menu's rows: the trees, the apple tree and the check box on top (the
  -- shrub moves down, unless the rows are left as they are), the shrubs sorted below.
  if O.apple or O.obstacles or O.sortedRows or O.spreadOrder then
    local top = {}
    for _, param in ipairs(O.spreadOrder and K.SPREAD_TREES or VEGETATION_TREES) do top[#top + 1] = button(param) end
    if O.apple then top[#top + 1] = added.apple end
    if not O.sortedRows then top[#top + 1] = button(TOP_ROW_SHRUB) end
    if O.obstacles then top[#top + 1] = added[OBSTACLES_BUTTON] end
    rows[#rows + 1] = top
  end
  if O.sortedRows then
    local bottom = { bottom = true }
    for _, param in ipairs(SORTED_SHRUBS) do bottom[#bottom + 1] = button(param) end
    rows[#rows + 1] = bottom
  end

  if O.textures then
    tooltips[#tooltips + 1] = { item = added.gravel, name = K.NAMES.gravel }
    pictureButton(added.gravel, TEXTURE_ROWS[1][1], GRAVEL_COMMAND, pictures.gravel)
    sizeOf[added.gravel] = { pictures.gravel.width, pictures.gravel.height }
    newButtons[added.gravel] = true
    -- Iron: a copy of the Heights menu's iron button, picture and description included.
    copyOf(IRON_COMMAND, added.iron)
    wr32(added.iron + ITEM_X, 0)
    wr32(added.iron + ITEM_Y, 0)
    wr16(added.iron + ITEM_HIDDEN, 1)
    newButtons[added.iron] = true
    for _, rowCommands in ipairs(TEXTURE_ROWS) do
      local row = {}
      for _, param in ipairs(rowCommands) do
        if param == GRAVEL_COMMAND then
          row[#row + 1] = added.gravel
        elseif param == IRON_COMMAND then
          row[#row + 1] = added.iron
        else
          row[#row + 1] = button(param)
        end
      end
      rows[#rows + 1] = row
    end
  end
  -- The invisible rocks check box: right of the Rocks menu's last button.
  local places = {}
  for _, tab in ipairs(boxTabs) do
    local box = added["invisible" .. tab]
    wr32(box + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(box + ITEM_WIDTH, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_HEIGHT, K.CHECK_BOX_SIZE)
    wr32(box + ITEM_ACTION, core.allocateAssembly(templates.flip, { FLAG = data.invisibleRocks }))
    wr32(box + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(box + ITEM_RENDER, core.allocateAssembly(templates.checkBox, {
      FLAG = data.invisibleRocks, ON_IMAGE = G.buttonImages + K.CHECKED_IMAGE * IMAGE_SIZE,
      OFF_IMAGE = G.buttonImages + K.UNCHECKED_IMAGE * IMAGE_SIZE,
      HOVER = G.hover, DRAW_MODE = G.drawMode, ITEM_X = G.itemX, ITEM_Y = G.itemY,
      TEXTURES = G.textures, RENDER_GM = G.renderGM,
    }))
    wr16(box + ITEM_HIDDEN, 1)
    tooltips[#tooltips + 1] = { item = box, lines = function()
      return { "Invisible rocks: " .. (rd8(data.invisibleRocks) ~= 0 and "on" or "off") }
    end, raise = K.CHECK_BOX_TOOLTIP_RAISE }
    local buttons = {}
    for _, rock in ipairs(G.rockButtons) do
      if rock.block == tab then buttons[#buttons + 1] = item(newTable, moved(rock.index)) end
    end
    if tab == ROCKS and G.buttons[K.SIGNPOST] ~= nil then buttons[#buttons + 1] = button(K.SIGNPOST) end
    places[#places + 1] = function(measure)
      local right, y, height = nil, 0, 0
      for _, address in ipairs(buttons) do
        local x = rd32(address + ITEM_X)
        if (x & 0xFFFFFFFF) == PLACED_BY_CONTROL then return false end
        local width, h = measure(address)
        if width == nil then return false end
        if right == nil or x + width > right then right, y, height = x + width, rd32(address + ITEM_Y), h end
      end
      wr32(box + ITEM_X, right + K.CHECK_BOX_GAP)
      wr32(box + ITEM_Y, y + (height - K.CHECK_BOX_SIZE) // 2)
      wr16(box + ITEM_HIDDEN, 0)
      return true
    end
  end
  -- Foam and small waves: copies of the river button with their own command and picture, put
  -- at the end of the water menu's shortest rows once the menu has placed its buttons.
  if O.waterDecorations and G.blockEnd[K.WATER] ~= nil then
    local waters, decorations = {}, {}
    for _, button in pairs(G.buttons) do
      if button.block == K.WATER then waters[#waters + 1] = item(newTable, moved(button.index)) end
    end
    for _, decoration in ipairs(K.WATER_DECORATIONS) do
      local into = added["water" .. decoration.command]
      copyOf(K.RIVER, into)
      wr32(into + ITEM_X, 0)
      wr32(into + ITEM_Y, 0)
      wr32(into + ITEM_PARAM, decoration.command)
      wr32(into + ITEM_IMAGE, decoration.image)
      wr32(into + ITEM_TEXT, 0)
      wr16(into + ITEM_CONTROL, -1)
      wr16(into + ITEM_HIDDEN, 1)
      decorations[#decorations + 1] = into
      tooltips[#tooltips + 1] = { item = into, name = K.NAMES[decoration.name] }
    end
    -- Once the menu has placed its buttons: the two join its shortest rows (a row: buttons whose
    -- middles are within K.ROW_TOLERANCE of each other). Every button keeps its height on the
    -- panel; a row keeps its left edge and only its gaps shrink, so that it ends no further
    -- right than ROW_RIGHT (or its own right edge, if that is further).
    places[#places + 1] = function(measure)
      local buttons = {}
      for _, address in ipairs(waters) do
        local x = rd32(address + ITEM_X)
        if (x & 0xFFFFFFFF) == PLACED_BY_CONTROL then return false end
        local width, height = measure(address)
        if width == nil then return false end
        local y = rd32(address + ITEM_Y)
        buttons[#buttons + 1] = { address = address, x = x, y = y, width = width, height = height,
          middle = y + height / 2 }
      end
      if #buttons == 0 then return false end
      table.sort(buttons, function(a, b) return a.middle < b.middle end)
      local list = {}
      for _, button in ipairs(buttons) do
        local row = list[#list]
        if row == nil or button.middle - row.middle > K.ROW_TOLERANCE then
          row = { middle = button.middle, items = {} }
          list[#list + 1] = row
        end
        table.insert(row.items, button)
      end
      for _, row in ipairs(list) do
        table.sort(row.items, function(a, b) return a.x < b.x end)
        row.left = row.items[1].x
        row.right = row.items[#row.items].x + row.items[#row.items].width
      end
      for _, into in ipairs(decorations) do
        local width, height = measure(into)
        if width == nil then return false end
        local shortest = list[1]
        for _, row in ipairs(list) do
          if #row.items < #shortest.items then shortest = row end
        end
        table.insert(shortest.items, { address = into, width = width, height = height,
          y = math.floor(shortest.middle - height / 2 + 0.5), added = true })
      end
      for _, row in ipairs(list) do
        local sum = 0
        for _, button in ipairs(row.items) do sum = sum + button.width end
        local right = math.max(row.right, ROW_RIGHT)
        local gap = #row.items > 1 and (right - row.left - sum) / (#row.items - 1) or 0
        if not row.items[#row.items].added then gap = nil end   -- no new button: left alone
        local x = row.left
        for _, button in ipairs(row.items) do
          if gap ~= nil then
            wr32(button.address + ITEM_X, math.floor(x + 0.5))
            wr32(button.address + ITEM_Y, button.y)
            wr16(button.address + ITEM_CONTROL, -1)
            x = x + button.width + gap
          end
          wr16(button.address + ITEM_HIDDEN, 0)
        end
      end
      return true
    end
  end
  -- The heights menu's iron goes; the Textures menu's copy of it stays.
  if O.noHeightsIron and O.textures then
    -- Hidden alone is not enough: the user control table places it (and shows it) again.
    local iron = button(IRON_COMMAND)
    wr32(iron + ITEM_X, 0)
    wr32(iron + ITEM_Y, 0)
    wr32(iron + ITEM_WIDTH, 0)
    wr32(iron + ITEM_HEIGHT, 0)
    wr32(iron + ITEM_IMAGE, 0)
    wr32(iron + ITEM_RENDER_TYPE, RENDER_NONE)
    wr16(iron + ITEM_CONTROL, -1)
    wr16(iron + ITEM_HIDDEN, 1)
  end
  if O.maxHeight or O.heightTools or O.lostRocks then
    local counts = { rows = #rows, places = #places, tooltips = #tooltips, guarded = #guarded }
    local ok, problem = pcall(C.heightsMenu, { G = G, O = O, data = data, added = added, copyOf = copyOf,
      button = button, moved = moved, newTable = newTable, rows = rows, newButtons = newButtons, places = places,
      tooltips = tooltips, guarded = guarded })
    if not ok then
      if O.maxHeight then log(ERROR, "Max Height is off.") end
      if O.heightTools then log(ERROR, "The height brush controls are off.") end
      if O.lostRocks then log(ERROR, "Clearing lost rock records is off.") end
      log(WARNING, tostring(problem))
      for i = #rows, counts.rows + 1, -1 do rows[i] = nil end
      for i = #places, counts.places + 1, -1 do places[i] = nil end
      for i = #tooltips, counts.tooltips + 1, -1 do tooltips[i] = nil end
      for i = #guarded, counts.guarded + 1, -1 do guarded[i] = nil end
      data.heights = nil
      local kinds = C.heightItems(O)
      if O.heightTools then kinds[#kinds + 1] = "heightTick" end
      for _, tab in ipairs({ ROCKS, K.ROCKS_SKIRMISH }) do kinds[#kinds + 1] = "lostRocks" .. tab end
      for _, kind in ipairs(kinds) do              -- harmless: never hit, never drawn, no action
        local into = added[kind]
        if into ~= nil then
          wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
          wr32(into + ITEM_X, 0)
          wr32(into + ITEM_Y, 0)
          wr32(into + ITEM_WIDTH, 0)
          wr32(into + ITEM_HEIGHT, 0)
          wr32(into + ITEM_ACTION, 0)
          wr32(into + ITEM_RENDER, 0)
          wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
          wr16(into + ITEM_CONTROL, -1)
          wr16(into + ITEM_HIDDEN, 1)
        end
      end
    end
  end
  -- 36, 37, 39: the wastebins, the eraser panel, the tree outlines; each on its own, left out
  -- harmlessly if it fails.
  local function extra(wanted, fn, kinds, message)
    if not wanted then return end
    local counts = { places = #places, tooltips = #tooltips, guarded = #guarded }
    local ok, problem = pcall(fn, { G = G, O = O, data = data, added = added, button = button, places = places,
      tooltips = tooltips, guarded = guarded })
    if ok then return true end
    log(ERROR, message)
    log(WARNING, tostring(problem))
    for i = #places, counts.places + 1, -1 do places[i] = nil end
    for i = #tooltips, counts.tooltips + 1, -1 do tooltips[i] = nil end
    for i = #guarded, counts.guarded + 1, -1 do guarded[i] = nil end
    for _, kind in ipairs(kinds) do               -- harmless: never hit, never drawn, no action
      local into = added[kind]
      if into ~= nil then
        wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
        wr32(into + ITEM_WIDTH, 0)
        wr32(into + ITEM_HEIGHT, 0)
        wr32(into + ITEM_ACTION, 0)
        wr32(into + ITEM_RENDER, 0)
        wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
        wr16(into + ITEM_CONTROL, -1)
        wr16(into + ITEM_HIDDEN, 1)
      end
    end
  end
  extra(#bins > 0, function(M) C.animalsMenu(M, bins) end, binKinds, "The animal removal buttons are off.")
  local eraserKinds = { "eraserPanel" }
  for i = 1, #K.ERASER_MODES do eraserKinds[#eraserKinds + 1] = "eraserMode" .. i end
  data.eraserChoice = extra(O.eraserChoice, C.eraserMenu, eraserKinds, "The eraser mode panel is off.")
  extra(O.spreadOutlines, C.spreadOutlines, { "spreadOutline" }, "Tree spreading outlines are off.")
  if O.groupWarning then
    local ok, problem = pcall(function() data.groupWarning = C.groupWarning(G, data) end)
    if not ok then
      log(ERROR, "The herd limit warning is off.")
      log(WARNING, tostring(problem))
    end
  end
  if O.textureMask then
    local counts = { places = #places, tooltips = #tooltips }
    local ok, problem = pcall(C.textureMask, { G = G, O = O, data = data, added = added, moved = moved,
      newTable = newTable, places = places, tooltips = tooltips })
    if not ok then
      log(ERROR, "The texture mask is off.")
      log(WARNING, tostring(problem))
      for i = #places, counts.places + 1, -1 do places[i] = nil end
      for i = #tooltips, counts.tooltips + 1, -1 do tooltips[i] = nil end
      data.mask = nil
      for _, kind in ipairs({ "maskButton", "maskTick" }) do   -- harmless: never hit, never drawn
        local into = added[kind]
        if into == nil then goto skip end
        wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
        wr32(into + ITEM_WIDTH, 0)
        wr32(into + ITEM_HEIGHT, 0)
        wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
        wr16(into + ITEM_HIDDEN, 1)
        ::skip::
      end
    end
  end
  local layout = makeLayout(G, rows, newButtons, sizeOf, places, finishes)

  -- A panel item at the end of a tab: shows its panel (lua) while one of its tools is chosen.
  local function panelItem(into, items, first, last, firstShrub, lastShrub, pad, felledLogs, felledCommand)
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(into + ITEM_RENDER, core.allocateAssembly(templates.panel, {
      SUBTYPE = G.subtype, FELLED_LOGS = felledLogs or unused, FELLED_COMMAND = felledCommand or unused + 4,
      FIRST_TREE = first, LAST_TREE = last, FIRST_SHRUB = firstShrub, LAST_SHRUB = lastShrub,
      PANEL_ITEMS = dwordList(items), ITEM_HIDDEN = ITEM_HIDDEN, PAD = pad,
    }))
  end

  -- The shrub and felled tree panels.
  if O.shrubs or O.felled then
    local panel = { items = {}, shrubs = {}, felled = {}, images = {}, info = added.info }
    if O.shrubs then
      -- With random mixes, choosing a shrub (here or in the menu) ends the random shrub.
      local shrubAction = nil
      if O.randomMix then
        shrubAction = core.allocateAssembly(templates.rockButton, {
          ROCK_LOCK = data.randomShrub, ACTION = G.buttons[SHRUB_COMMANDS[1]].action,
        })
        wr32(button(SHRUB_COMMANDS[1]) + ITEM_ACTION, shrubAction)
      end
      for i, command in ipairs(SHRUB_COMMANDS) do
        local into = added["shrub" .. i]
        copyOf(SHRUB_COMMANDS[1], into)        -- the shrub button: its group's action and description
        wr32(into + ITEM_X, 0)
        wr32(into + ITEM_Y, 0)
        wr32(into + ITEM_PARAM, command)
        wr32(into + ITEM_IMAGE, 0)
        wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
        wr16(into + ITEM_HIDDEN, 1)
        if shrubAction ~= nil then wr32(into + ITEM_ACTION, shrubAction) end
        panel.shrubs[i] = into
        panel.items[#panel.items + 1] = into
      end
      if O.randomMix then
        panel.randomShrub = added.randomShrub
        plainButton(panel.randomShrub, core.allocateAssembly(templates.flip, { FLAG = data.randomShrub }))
        panel.items[#panel.items + 1] = panel.randomShrub
      end
    end
    if O.felled then
      local click = core.allocateAssembly(templates.felledClick, {
        SUBTYPE = G.subtype, FELLED_LOGS = data.felledLogs, FELLED_COMMAND = data.felledCommand,
      })
      for command = FIRST_TREE_COMMAND, LAST_TREE_COMMAND do
        panel.images[command] = rd32(item(G.table, G.buttons[command].index, ITEM_IMAGE)) & IMAGE_INDEX_MASK
        -- The menu's tree buttons place standing trees again.
        wr32(button(command) + ITEM_ACTION, core.allocateAssembly(templates.rockButton, {
          ROCK_LOCK = data.felledLogs, ACTION = G.buttons[command].action,
        }))
      end
      for i = 1, felledButtons do
        plainButton(added["felled" .. i], click)
        panel.felled[i] = added["felled" .. i]
        panel.items[#panel.items + 1] = added["felled" .. i]
      end
    end
    for _, address in ipairs(panel.items) do
      guarded[#guarded + 1] = address
      guarded[#guarded + 1] = VEGETATION
    end
    local pad = luaPad(makePanel(G, O, data, panel, makeTreeEntries(G, O, data, panel)), "the tree panels")
    local first, last = 1, 0                   -- an empty range when the felled panel is off
    if O.felled then first, last = FIRST_TREE_COMMAND, LAST_TREE_COMMAND end
    local firstShrub, lastShrub = 1, 0
    if O.shrubs then firstShrub, lastShrub = SHRUB_COMMANDS[1], SHRUB_COMMANDS[#SHRUB_COMMANDS] end
    panelItem(added.panel, panel.items, first, last, firstShrub, lastShrub, pad, data.felledLogs, data.felledCommand)
  end

  -- The rock variant panels (one per Rocks tab), and the Rocks menu's own buttons going back
  -- to cycling variants.
  if #rockTabs > 0 then
    local click = core.allocateAssembly(templates.rockClick, { ROCK_LOCK = data.rockLock })
    local rockPicture = makeRockPictures(G)
    for _, tab in ipairs(rockTabs) do
      local panel = { items = {}, rocks = {}, info = added.info }
      for v = 1, K.ROCK_VARIANTS + 1 do
        local into = added["rock" .. tab .. "/" .. v]
        plainButton(into, click)
        panel.rocks[v] = into
        panel.items[#panel.items + 1] = into
        guarded[#guarded + 1] = into
        guarded[#guarded + 1] = tab
      end
      local pad = luaPad(makePanel(G, O, data, panel, makeRockEntries(G, O, data, panel, rockPicture)),
        "the rock panel")
      panelItem(added["rockPanel" .. tab], panel.items, K.FIRST_ROCK_COMMAND, K.LAST_ROCK_COMMAND, 1, 0, pad)
    end
    -- The buttons and their groups' headers, whose action the Menu constructor may copy into
    -- them.
    local wrapped = {}
    local function wrap(index, action)
      if wrapped[index] or action == 0 then return end
      wrapped[index] = true
      wr32(item(newTable, moved(index), ITEM_ACTION), core.allocateAssembly(templates.rockButton, {
        ROCK_LOCK = data.rockLock, ACTION = action,
      }))
    end
    for _, rock in ipairs(G.rockButtons) do
      wrap(rock.index, rock.action)
      if rock.group ~= nil then wrap(rock.group, rd32(item(G.table, rock.group, ITEM_ACTION))) end
    end
  end

  -- The herd panel.
  if O.herds then
    local herd = { checkBox = added.herdCheck }
    plainButton(herd.checkBox, core.allocateAssembly(templates.flip, { FLAG = data.herdSync }))
    guarded[#guarded + 1] = herd.checkBox
    guarded[#guarded + 1] = ANIMALS
    local pad = luaPad(makeHerdPanel(G, O, data, herd), "the herd panel")
    panelItem(added.herdPanel, { herd.checkBox }, K.HERD_ANIMALS[1][1], K.HERD_ANIMALS[#K.HERD_ANIMALS][1], 1, 0, pad)
  end

  -- The tooltip: drawn after everything else that is always shown, never hit by the mouse.
  if added.tooltip ~= nil then
    local hoverWords = {}
    for _, candidate in ipairs(tooltips) do hoverWords[#hoverWords + 1] = candidate.item + ITEM_HOVERED end
    -- A panel drawn later would cover it: the panels draw it again on top of themselves, and
    -- then it is left out here the next frame.
    data.tooltip = makeTooltip(G, tooltips)
    local function early()
      if data.tooltipLate then data.tooltipLate = false else data.tooltip() end
    end
    local tooltip = added.tooltip
    wr32(tooltip + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(tooltip + ITEM_RENDER, core.allocateAssembly(templates.tooltip, {
      HOVER_WORDS = dwordList(hoverWords), PAD = luaPad(early, "the tooltip"),
    }))
    wr32(tooltip + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  end

  if O.undo then C.undoButtons(G, added, guarded, O.undo) end
  if added.rockTick ~= nil then
    local ok, problem = pcall(function()
      local R = C.resolvePipette(G)
      local gameMode = C.gameModeOf()
      local mode, rotation = R.tileMap + K.TILE_MAP.mode, R.tileMap + K.TILE_MAP.rotation
      local asyncKey = core.exposeCode(core.allocateAssembly(templates.undoKeyState, { IMPORT = R.keyState }), 1, 0)
      local wasDown, placedAtPress = false, nil
      local pad = C.luaPad(function()
        local down = (asyncKey(K.LEFT_BUTTON) & 0x8000) ~= 0
        if down == wasDown then return end
        wasDown = down
        local tool = rd32(G.subtype)
        local eligible = rd32(gameMode) == K.MAP_EDITOR and tool >= K.FIRST_ROCK_COMMAND
          and tool <= K.LAST_ROCK_COMMAND and rd32(mode) == K.ROCK_TURN_MODE
        if down then
          placedAtPress = eligible and rd32(G.onMap) ~= 0 and rd32(O.rockPlaced) or nil
        elseif eligible and placedAtPress ~= nil and placedAtPress == rd32(O.rockPlaced) then
          wr32(rotation, (rd32(rotation) + 2 * math.random(1, 3)) % 8)
        end
      end, "the rock click turn")
      wr32(added.rockTick + ITEM_TYPE, TYPE_EVERY_FRAME)
      wr32(added.rockTick + ITEM_ACTION, pad)
    end)
    if not ok then log(WARNING, tostring(problem) .. "; refused rock clicks keep the rotation") end
  end
  if added.compass ~= nil then
    local ok, problem = pcall(C.compassItem, G, added.compass, O.undo)
    if not ok then
      log(ERROR, "The landscape editor compass is off.")
      log(WARNING, tostring(problem))
    end
  end
  if O.treePreview then
    local into = added.treePreview
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)    -- no size, so never under the mouse
    wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
    local ok, problem = pcall(function()
      local pad = C.luaPad(C.makeTreePreview(G, O, data), "the tree preview")
      wr32(into + ITEM_RENDER, pad)
      wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
      data.treePreviewPad, data.treePreviewItem = pad, into
    end)
    if not ok then
      log(ERROR, "The vegetation preview is off.")
      log(WARNING, tostring(problem))
    end
  end
  if O.pipette then
    if G.blit == nil then
      G.blit = core.allocateAssembly(templates.blit, {
        PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
        SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
      })
    end
    local count = #guarded
    local ok, problem = pcall(C.pipette, G, O, data, added, guarded, places, button)
    if not ok then
      log(ERROR, "The terrain pipette is off.")
      log(WARNING, tostring(problem))
      for i = #guarded, count + 1, -1 do guarded[i] = nil end
      for _, kind in ipairs(pipetteItems) do      -- harmless: never hit, never drawn, no action
        local into = added[kind]
        wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
        wr32(into + ITEM_WIDTH, 0)
        wr32(into + ITEM_HEIGHT, 0)
        wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
        wr16(into + ITEM_HIDDEN, 1)
      end
    end
  end

  -- The guard, in front of the game's map click handler; it also runs the layout until it
  -- has worked.
  data.laidOut = core.allocate(4, true)
  wr32(data.laidOut, (#rows == 0 and #places == 0) and 1 or 0)
  local layoutPad = core.allocateCode({ 0x90, 0x90, 0x90, 0x90, 0x90, 0xC3 })
  core.detourCode(function(registers)
    local ok, done = pcall(layout)
    if not ok then
      log(WARNING, MODULE_NAME .. ": the new buttons could not be laid out: " .. tostring(done))
      done = true
    end
    if done then wr32(data.laidOut, 1) end
    return registers
  end, layoutPad, 5)
  local guard = added.guard
  wr32(guard + ITEM_TYPE, TYPE_EVERY_FRAME)
  wr32(guard + ITEM_ACTION, core.allocateAssembly(templates.guard, {
    LAID_OUT = data.laidOut, LAYOUT = layoutPad, GUARDED = dwordList(guarded),
    ACTIVE_TAB = G.activeTab, ITEM_HIDDEN = ITEM_HIDDEN, ITEM_HEIGHT = ITEM_HEIGHT,
    ITEM_WIDTH = ITEM_WIDTH, ITEM_MENU = ITEM_MENU, MENU_X = MENU_X, MENU_Y = MENU_Y, ITEM_X = ITEM_X,
    ITEM_Y = ITEM_Y, MOUSE = G.mouse, IS_MOUSE_INSIDE = G.isMouseInside, ON_MAP = G.onMap,
    RECTS = data.rects, THE_MENU = G.menu,
  }))

  data.rockTabs = #rockTabs
  -- The band the floating panels share: this menu's items and its description line.
  require("editor.lane").prepare(data, newTable, item(newTable, moved(HOVER_TEXT_ITEM)))
  return newTable, data
end

return {
  buildTable = buildTable,
}
