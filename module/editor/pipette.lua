local layout = require("editor.layout")
local templates = layout.templates
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_RENDER = layout.ITEM_RENDER
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local TYPE_EVERY_FRAME = layout.TYPE_EVERY_FRAME
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local RENDER_NONE = layout.RENDER_NONE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local MENU_SCROLL = layout.MENU_SCROLL
local APPLE_TYPE = layout.APPLE_TYPE
local K = layout.K
local C = layout.C
local PENCIL_TARGET = layout.PENCIL_TARGET
local TOOLTIP_FONT = layout.TOOLTIP_FONT
local TOOLTIP_COLOUR = layout.TOOLTIP_COLOUR
local ALIGN_LEFT = layout.ALIGN_LEFT
local MAP_LAYER = layout.MAP_LAYER
local MAX_STAGE = layout.MAX_STAGE
local TREES_IN_LANDSCAPE = layout.TREES_IN_LANDSCAPE
local TREE = layout.TREE
local LYING_FELLED = layout.LYING_FELLED
local memory = require("editor.memory")
local writeCString = memory.writeCString
local dwordList = memory.dwordList
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local buttonPictures = require("editor.images").buttonPictures
local makePanel = require("editor.ui").makePanel
local patchJump = require("editor.menu_install").patchJump
local keyCode = require("editor.pipette_native").keyCode
local actions = require("editor.actions")

-- The tree or rock on a tile, for the pipette: what placing the same again takes. Rocks the
-- game has no slot for (the invisible ones, number 2000) are left out.
function C.readPlant(G, T, R, plantOf, tile, logic)
  local number = rd16(T + R.organism + tile * 2)
  if number >= K.FIRST_ROCK_NUMBER and logic & K.ROCKY ~= 0 then
    local slot = number - K.FIRST_ROCK_NUMBER
    if slot < 1 or slot > G.rockSlots then return nil end
    local rock = G.firstRock - K.ROCK_SLOT.inUse + (slot - 1) * G.rockSize
    local rockType = rd16(rock + K.ROCK_SLOT.type)
    if rockType < 1 or rockType > K.ROCK_TYPES then return nil end
    local id = rockType - 1
    local size = id // 4 + 1
    return { kind = "rock", number = id, size = size, turn = rd16(rock + K.ROCK_SLOT.turn) & 0xFFFF,
      name = string.format("rock (size %d)", size) }
  end
  if number > 0 and number <= G.treeSlots and logic & K.TREE_FLAG ~= 0 then
    local tree = G.landscape + TREES_IN_LANDSCAPE + number * G.treeSize
    local treeType = rd16(tree + TREE.TYPE)
    local command = plantOf[treeType]
    if command == nil then return nil end
    local stage = rd8(tree + TREE.STAGE) & 0xFF
    local plant = { kind = "tree", command = command, stage = math.min(stage, MAX_STAGE),
      picture = rd32(tree + K.TREE_PICTURE) }
    local name = treeType == APPLE_TYPE and "apple tree" or K.PLANT_NAMES[command] or "shrub"
    if rd8(tree + TREE.LYING) & 0xFF == LYING_FELLED then
      plant.logs = math.max(1, rd8(tree + TREE.LOGS) & 0xFF)
      plant.name = string.format("felled %s, %d logs", name, plant.logs)
    else
      plant.name = string.format("%s, stage %d", name, plant.stage + 1)
    end
    return plant
  end
  return nil
end

-- The pipette button, its panel and the per-frame work, in the landscape menu being built.
function C.pipette(G, O, data, added, guarded, places, button)
  local S = O.pipette
  local R = C.resolvePipette(G)
  local T = R.tileMap
  local blit = core.exposeCode(G.blit, 3, 0)
  local tileForBrush = core.exposeCode(R.tileForBrush, 7, 1)
  local links = core.exposeCode(R.links, 3, 1)
  local removeRock = core.exposeCode(R.removeRock, 2, 1)
  local walk = core.exposeCode(R.walk, 4, 1)
  local redraw = core.exposeCode(R.redraw, 2, 1)
  local mouseSetup, flatSetup = core.exposeCode(R.mouseSetup, 1, 1), core.exposeCode(R.flatSetup, 1, 1)
  local asyncKey = core.exposeCode(core.allocateAssembly(templates.undoKeyState, { IMPORT = R.keyState }), 1, 0)
  local function down(key) return key ~= nil and (asyncKey(key) % 0x10000) >= 0x8000 end
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local text = core.allocate(256, true)
  local out = core.allocate(8, true)
  local commandOfType = core.exposeCode(R.commandOfType, 2, 1)
  local placeRock, placeTree = core.exposeCode(R.placeRock, 4, 1), core.exposeCode(R.placeTree, 4, 1)
  -- Which tool plants each tree type (the game's own answer, read by resolveCounters).
  local plantOf = {}
  for command, treeType in pairs(G.plantTypes or {}) do
    if plantOf[treeType] == nil or command < plantOf[treeType] then plantOf[treeType] = command end
  end
  data.pipetteRead = core.allocate(4, true)
  local activeFlag = core.allocate(4, true)    -- the pipette (or the tool it chose) is in use
  local P = { mode = 1, stored = nil, held = false, waitRelease = false, last = nil, keys = {} }
  local selectKey, readKey, anyKey = keyCode(S.selectKey), keyCode(S.readKey), keyCode(S.anyKey)

  local function chosen() return rd32(G.subtype) == K.PIPETTE_TOOL end
  -- The objects pipette's tool, while it holds an object.
  -- The tool that places what the objects pipette holds: a building's own, the tree's, or the
  -- rock tool.
  local function objectTool()
    if P.mode ~= K.PIPETTE_OBJECTS or P.stored == nil then return nil end
    if P.stored.kind == "rock" then return K.FIRST_ROCK_COMMAND end   -- the size comes from the brush
    return P.stored.command
  end
  -- What that tool needs set while the pipette holds a tree or rock (the brush for the tree's
  -- stage, its felled logs; the rock's size, variant and turn), and the user's own settings
  -- back afterwards.
  local function hold(stored)
    if P.saved ~= nil or stored.kind == "building" then return end
    local S2 = { brush = rd32(G.brush), turn = rd32(T + K.TILE_MAP.rotation), mode = rd32(T + K.TILE_MAP.mode),
      variant = rd32(T + K.ROCK_VARIANT_AT), size = rd32(T + K.ROCK_SIZE_AT) }
    if data.felledLogs ~= nil then S2.logs, S2.felled = rd32(data.felledLogs), rd32(data.felledCommand) end
    if data.rockLock ~= nil then S2.lock = rd32(data.rockLock) end
    P.saved = S2
    if stored.kind == "tree" then
      data.treePreview = { command = stored.command, picture = stored.picture }
      wr32(G.brush, stored.stage + 1)          -- the module's growth stage follows the brush size
      if data.felledLogs ~= nil then
        wr32(data.felledLogs, stored.logs or 0)
        wr32(data.felledCommand, stored.logs ~= nil and stored.command or 0)
      end
    else
      wr32(G.brush, 2 * (stored.size - 1) + 1)  -- the rock tools' size is brush / 2 (brushes 1, 3, 5, 7)
      wr32(T + K.ROCK_SIZE_AT, stored.size - 1)
      wr32(T + K.ROCK_VARIANT_AT, stored.number % 4)
      if data.rockLock ~= nil then wr32(data.rockLock, stored.number % 4 + 1) end
      wr32(T + K.TILE_MAP.rotation, stored.turn)
      wr32(T + K.TILE_MAP.mode, K.FIXED_TURN)
    end
  end
  local function release()
    local S2 = P.saved
    if S2 == nil then return end
    P.saved = nil
    data.treePreview = nil
    wr32(G.brush, S2.brush)
    wr32(T + K.TILE_MAP.rotation, S2.turn)
    wr32(T + K.TILE_MAP.mode, S2.mode)
    wr32(T + K.ROCK_VARIANT_AT, S2.variant)
    wr32(T + K.ROCK_SIZE_AT, S2.size)
    if S2.logs ~= nil then
      wr32(data.felledLogs, S2.logs)
      wr32(data.felledCommand, S2.felled)
    end
    if S2.lock ~= nil then wr32(data.rockLock, S2.lock) end
  end
  local function active()
    local tool = objectTool()
    return chosen() or (tool ~= nil and rd32(G.subtype) == tool)
  end
  local function choose()
    release()
    wr32(G.subtype, K.PIPETTE_TOOL)
    P.stored, P.waitRelease, P.last = nil, true, nil
  end
  local function reading() return P.stored == nil or P.reading end

  -- The tile at map x, y and the tiles of the brush around it (write mode: the brush size).
  local function tileOf(x, y) return rd32(R.rows + y * 12) + x end
  local function brushTiles(x, y, size)
    local count = rd32(R.brushSizes + size * 4)
    local base, list = tileOf(x, y), {}
    for i = 0, count - 1 do
      tileForBrush(T, 1, i, out, out + 4, base, y)
      local tile, ty = rd32(out), rd32(out + 4)
      if tile >= 0 and tile < K.MAP_TILES and ty >= 0 and ty < K.MAP_SIZE then list[#list + 1] = { tile, ty } end
    end
    return list
  end

  local function logicAt(tile) return rd32(T + R.logic + tile * 4) & 0xFFFFFFFF end
  local function read(x, y)
    local tile = tileOf(x, y)
    local logic = logicAt(tile)
    P.stored = {
      -- The height that is shown (a river tile lies RIVER_DEPTH below its base height).
      mode = P.mode, live = rd8(T + R.height + tile) & 0xFF,
      texture = logic & K.TEXTURE_FLAGS, decoration = rd8(T + K.TMS.decoration + tile) & 0xFF,
      random = rd16(T + K.TMS.random + tile * 2),
    }
    P.stored.base = P.stored.live
    if logic & K.RIVER_TERRAIN ~= 0 then P.stored.base = math.min(0xFF, P.stored.live + K.RIVER_DEPTH) end
  end

  -- The building or wall on a tile, as the tool that places it.
  local function readObject(x, y)
    local tile = tileOf(x, y)
    local id = rd16(T + K.TMS.building + tile * 2)
    local command, owner = 0, nil
    local variant, hovel = nil, nil
    if id > 0 then
      local buildingType = rd16(R.buildingType + id * R.buildingStride)
      command = commandOfType(0, buildingType) & 0xFFFF
      owner = rd16(R.buildingType + K.OWNER_AFTER_TYPE + id * R.buildingStride)
      -- The exact variant: its value found in its group's table.
      local group = K.VARIANT_GROUPS[buildingType]
      if group ~= nil then
        local value = rd32(R.buildingsState + id * R.buildingStride + R.variationField)
        local list = R.variationTables[group.table]
        for i = 0, group.count - 1 do
          if rd32(list + i * 4) == value then
            command, variant = group.first + i, string.format("%s %d", group.name, i + 1)
            break
          end
        end
      elseif buildingType == K.HOVEL_TYPE then
        hovel = rd16(R.hovelField + id * R.buildingStride) % K.HOVEL_VARIANTS
      elseif buildingType == K.CAMPFIRE_TYPE then
        command = K.BARRIER_COMMAND
      elseif buildingType == K.CATHEDRAL_TYPE and rd16(R.ruinedFlag + id * R.buildingStride) == 1 then
        variant = "ruined cathedral"
      end
    else
      owner = (rd8(T + K.TMS.wallOwner + tile) & K.WALL_OWNER_BITS) + 1
      local logic = logicAt(tile)
      if logic & K.STOCKPILE_FLAG ~= 0 then
        command = 0
      elseif logic & K.STAIRS_FLAG ~= 0 then
        command = K.STAIRS_TOOL
      elseif logic & K.CRENEL_FLAG ~= 0 then
        command = K.CRENEL_TOOL
      elseif logic & K.WALL_FLAG ~= 0 then
        local above = (rd8(T + R.height + tile) & 0xFF) - (rd8(T + R.defaultHeight + tile) & 0xFF)
        command = above >= K.HIGH_WALL_ABOVE and K.HIGH_WALL_TOOL or K.LOW_WALL_TOOL
      end
    end
    if command ~= 0 then
      P.nothing = false
      P.stored = { kind = "building", command = command, name = variant or K.OBJECT_NAMES[command] or ("object " .. command),
        variant = variant ~= nil and command ~= K.CATHEDRAL_TOOL, hovel = hovel,
        ruined = command == K.CATHEDRAL_TOOL and variant ~= nil }
      if hovel ~= nil then P.stored.name = string.format("hovel %d", hovel + 1) end
      if command == K.BARRIER_COMMAND then P.stored.name = "barrier" end
      if owner ~= nil and owner >= 1 and owner <= K.PLAYERS then
        P.stored.owner = owner
        P.stored.name = string.format("%s of player %d", P.stored.name, owner)
      end
      return
    end
    local plant = C.readPlant(G, T, R, plantOf, tile, logicAt(tile))
    P.nothing = plant == nil
    if plant ~= nil then P.stored = plant end
  end

  -- One tree or rock (as read by C.readPlant) at x, y, placed the way the landscape editor
  -- places one; for a tree its stage and felled logs through the module's tree hooks.
  local function placePlant(plant, x, y)
    if plant.kind == "rock" then
      local turn = T + K.TILE_MAP.rotation
      local before = rd32(turn)
      wr32(turn, plant.turn)
      placeRock(T, x, y, plant.number)
      wr32(turn, before)
      return
    end
    local brush = rd32(G.brush)
    local logs, felledCommand
    if data.felledLogs ~= nil then
      logs, felledCommand = rd32(data.felledLogs), rd32(data.felledCommand)
      wr32(data.felledLogs, plant.logs or 0)
      wr32(data.felledCommand, plant.logs ~= nil and plant.command or 0)
    end
    wr32(G.brush, plant.stage + 1)             -- the module's growth stage follows the brush size
    placeTree(T, x, y, plant.command)
    wr32(G.brush, brush)
    if data.felledLogs ~= nil then
      wr32(data.felledLogs, logs)
      wr32(data.felledCommand, felledCommand)
    end
  end

  -- Gives one tile the stored heights or textures; answers whether it changed it.
  local function blocked(tile, logic, mask)
    return logic & mask ~= 0 or rd16(T + K.TMS.building + tile * 2) ~= 0
  end
  local function setLive(tile, logic)
    local base = rd8(T + R.defaultHeight + tile) & 0xFF
    local live = base
    if logic & K.RIVER_TERRAIN ~= 0 then live = math.max(0, base - K.RIVER_DEPTH) end
    core.writeByte(T + R.height + tile, live)
  end
  -- A rocky tile: a rock stays (only the any-tile key takes it away, as the game's height tools
  -- do), a cliff rock goes. Answers the tile word without the rocky flag, or nil.
  local function unrock(tile, logic, any)
    if logic & K.ROCKY == 0 then return logic end
    local number = rd16(T + R.organism + tile * 2)
    if number >= K.FIRST_ROCK_NUMBER then
      -- A rock stays; with the any-tile key its tile still gets the heights or textures, like
      -- the plateau tools give them.
      if not any then return nil end
      return logic
    end
    return logic & ~K.ROCKY & 0xFFFFFFFF
  end
  local function giveHeights(tile, logic, any)
    if not any and (blocked(tile, logic, K.HEIGHT_REFUSED)
        or (rd8(T + K.TMS.decoration + tile) & 0xFF) & K.BEACH_DECORATION ~= 0) then
      return false
    end
    logic = unrock(tile, logic, any)
    if logic == nil then return false end
    wr32(T + R.logic + tile * 4, logic)
    core.writeByte(T + R.defaultHeight + tile, P.stored.base)
    setLive(tile, logic)
    return true
  end
  local function giveTextures(tile, logic, any)
    if not any and blocked(tile, logic, K.TEXTURE_REFUSED) then return false end
    logic = unrock(tile, logic, any)
    if logic == nil then return false end
    local new = (logic & ~K.TEXTURE_FLAGS & 0xFFFFFFFF) | P.stored.texture
    local decoration = rd8(T + K.TMS.decoration + tile) & 0xFF
    wr32(T + R.logic + tile * 4, new)
    core.writeByte(T + K.TMS.decoration + tile, P.stored.decoration)
    -- A new random number for a tile whose ground changes, and for one that still has the
    -- source's (pipette versions before 1.0.31 copied it, which made the ground repeat).
    if new ~= logic or decoration ~= P.stored.decoration or rd16(T + K.TMS.random + tile * 2) == P.stored.random then
      wr16(T + K.TMS.random + tile * 2, math.random(0, K.RANDOM_LIMIT))
    end
    if (new ~ logic) & K.RIVER_TERRAIN ~= 0 then setLive(tile, new) end
    return true
  end

  local anyTileHeld = actions.hold("pipette-any-tile")
  local readHeld = actions.hold("pipette-read")

  local function apply(x, y)
    local any = anyTileHeld() or (S.anyKeyOn and down(anyKey))
    local changed = false
    local tiles = brushTiles(x, y, rd32(T + R.brushField))
    if O.undo ~= nil then O.undo.beginEdit() end
    -- The mask decides on every tile before anything changes (painting changes the texture).
    local clicked, allowed = tileOf(x, y), {}
    for _, at in ipairs(tiles) do allowed[at[1]] = C.maskAllows(T, R, at[1], clicked) end
    for _, at in ipairs(tiles) do
      local tile, ty = at[1], at[2]
      local logic = logicAt(tile)
      if logic & K.MAP_BORDER == 0 and allowed[tile] then
        local done = false
        if P.mode == K.PIPETTE_TEXTURES or P.mode == K.PIPETTE_ALL then
          done = giveTextures(tile, logic, any) or done
          logic = logicAt(tile)
        end
        if P.mode == K.PIPETTE_HEIGHTS or P.mode == K.PIPETTE_ALL then done = giveHeights(tile, logic, any) or done end
        if done then
          links(R.pathFinding, ty, tile)
          changed = true
        end
      end
    end
    if P.mode == K.PIPETTE_ALL and P.stored.plant ~= nil then
      -- The mask already chose the tiles; the tree and rock placement would test them again,
      -- after their texture changed.
      local mask = C.maskState
      local on = mask ~= nil and rd32(mask.on) or 0
      if mask ~= nil then wr32(mask.on, 0) end
      for _, at in ipairs(tiles) do
        local tile, ty = at[1], at[2]
        if allowed[tile] then placePlant(P.stored.plant, tile - rd32(R.rows + ty * 12), ty) end
      end
      if mask ~= nil then wr32(mask.on, on) end
    end
    if not changed then return end
    -- What the game's height and terrain tools do afterwards.
    wr32(T + R.logicFlag, 1)
    wr32(R.macroFlag, 1)
    walk(R.pathFinding, K.WALK_RADIUS, x, y)
    redraw(R.minimap, 2)
  end

  local function editor() return rd32(R.gameMode) == K.MAP_EDITOR end
  local function typing() return rd32(R.menuGuard) ~= -1 end
  local function pressed(key)
    local now = down(key)
    local was = P.keys[key]
    P.keys[key] = now
    return now and not was
  end
  -- The select key: the pipette, or its next kind while it is in use.
  local function selectPipette()
    if active() then P.mode = P.mode % #K.PIPETTE_MODES + 1 end
    choose()
  end

  -- With Custom Hotkeys the select key is an action there (editor/actions.lua) and the tick leaves
  -- the key alone. Its context is the whole map editor; the pipette is a landscape tool, so the
  -- action does nothing unless the landscape menu is shown, and nothing before the pipette and the
  -- menu are in (data.pipette is set last below, data.installed once the menu is).
  local selectByAction = false
  local hotkeys = actions.provider()
  if hotkeys ~= nil then
    selectByAction = actions.pipette(hotkeys, S.selectKeyOn and S.selectKey or nil, function()
      if data.pipette == nil or not data.installed or not editor() or typing()
          or rd32(G.activeTab - K.MENU_VIEW_BEFORE_TAB) ~= K.LANDSCAPE_VIEW then
        return false
      end
      selectPipette()
      return true
    end)
  end

  -- Every frame, before the map click handler.
  local function tick()
    if not editor() then return end
    if C.watchRuins ~= nil then C.watchRuins() end   -- a ruined cathedral placed from here
    if not selectByAction and S.selectKeyOn and selectKey ~= nil and pressed(selectKey) and not typing() then
      selectPipette()
    end
    if not active() then
      P.held, P.waitRelease = false, false
      release()
      if P.mode == K.PIPETTE_OBJECTS then P.stored = nil end   -- another tool was chosen
      wr32(data.pipetteRead, K.NO_TOOL)
      wr32(activeFlag, 0)
      return
    end
    wr32(activeFlag, 1)
    P.reading = readHeld() or (S.readKeyOn and down(readKey))
    -- One tile in the brush preview while taking a tile, and for objects (placed one at a time).
    -- (a tree's own tool too: placed one per tile like the game's tree tool, whatever the brush)
    local oneTile = K.NO_TOOL
    if reading() or P.mode == K.PIPETTE_OBJECTS then oneTile = K.PIPETTE_TOOL end
    if not chosen() and P.stored ~= nil and P.stored.kind == "tree" then oneTile = P.stored.command end
    wr32(data.pipetteRead, oneTile)
    local held = rd32(R.clickHeld) ~= 0
    if P.mode == K.PIPETTE_OBJECTS and not held then
      -- Between clicks: the object's own tool to place it, the pipette to take one.
      local tool = objectTool()
      if reading() and not chosen() then
        release()
        wr32(G.subtype, K.PIPETTE_TOOL)
      elseif not reading() and tool ~= nil and chosen() then
        hold(P.stored)
        wr32(G.subtype, tool)
        -- This very variant, not turning into the next one.
        local locks = C.locks()
        if P.stored.variant then wr32(locks.variant, tool) end
        if P.stored.hovel ~= nil then wr32(locks.hovel, P.stored.hovel + 1) end
        if tool == K.CATHEDRAL_TOOL then wr32(locks.ruined, P.stored.ruined and 1 or 0) end
        -- Placed for the same player: chosen as if by that player's shield.
        local owner = P.stored.owner
        if owner ~= nil then
          for i = 0, K.PLAYERS do wr32(R.playerFlags + i * 4, 0) end
          wr32(R.playerFlags + owner * 4, 1)
          wr32(R.currentPlayer, owner)
          wr32(R.editorPlayer, owner)
        end
      end
    end
    if not held then
      P.held, P.waitRelease, P.last = false, false, nil
      return
    end
    if not chosen() then return end            -- the game places the object
    if P.waitRelease or rd32(G.onMap) == 0 then return end
    if rd32(R.flatView) ~= 0 then flatSetup(R.viewport) else mouseSetup(R.viewport) end
    local x, y = rd32(R.mouseX), rd32(R.mouseY)
    if x < 0 or y < 0 or x >= K.MAP_SIZE or y >= K.MAP_SIZE then return end
    if reading() then
      if P.mode == K.PIPETTE_OBJECTS then
        readObject(x, y)
      else
        read(x, y)
        if P.mode == K.PIPETTE_ALL then
          local tile = tileOf(x, y)
          local plant = C.readPlant(G, T, R, plantOf, tile, logicAt(tile))
          if plant ~= nil and (plant.kind == "tree" or plant.size == 1) then P.stored.plant = plant end
        end
      end
      P.waitRelease = true       -- the next click writes
      return
    end
    if P.mode == K.PIPETTE_OBJECTS then return end   -- the object's own tool places it
    local tile = tileOf(x, y)
    if tile == P.last then return end
    P.last = tile
    apply(x, y)
  end

  -- The button, in the column of brush size, ruler and eraser (all moved down for it).
  local pictures = buttonPictures("pipette")
  local pipette = added.pipette
  wr32(pipette + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(pipette + ITEM_X, K.PIPETTE_COLUMN.x)
  wr32(pipette + ITEM_Y, K.PIPETTE_COLUMN.tops[1])
  wr32(pipette + ITEM_WIDTH, pictures.width)
  wr32(pipette + ITEM_HEIGHT, pictures.height)
  wr32(pipette + ITEM_ACTION, C.luaPad(choose, "the pipette button"))
  wr32(pipette + ITEM_RENDER, core.allocateAssembly(templates.flagPictureButton, {
    NORMAL = pictures.normal, HOVERED = pictures.hover, CHOSEN = pictures.chosen, FLAG = activeFlag,
    HOVER = G.hover, PENCIL = G.pencil, PENCIL_TARGET = PENCIL_TARGET, ITEM_X = G.itemX, ITEM_Y = G.itemY,
    BLIT = G.blit,
  }))
  wr32(pipette + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  wr32(pipette + ITEM_TEXT, 0)
  guarded[#guarded + 1] = pipette
  guarded[#guarded + 1] = 0
  for i, param in ipairs(K.PIPETTE_COLUMN.moved) do
    local top = K.PIPETTE_COLUMN.tops[i + 1]
    for _, extra in ipairs(param) do
      if G.buttons[extra] ~= nil then
        local into = button(extra)
        wr32(into + ITEM_X, K.PIPETTE_COLUMN.x)
        wr32(into + ITEM_Y, top)
        wr16(into + ITEM_CONTROL, -1)
      end
    end
  end

  -- The panel: heights, textures, all; and above it what the pipette holds.
  local panel = { items = {}, info = added.info }
  local entries = {}
  for i, mode in ipairs(K.PIPETTE_MODES) do
    local into = added["pipetteMode" .. i]
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(into + ITEM_ACTION, C.luaPad(function()
      P.mode = i
      choose()
    end, "the pipette panel"))
    wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
    wr16(into + ITEM_HIDDEN, 1)
    panel.items[i] = into
    guarded[#guarded + 1] = into
    guarded[#guarded + 1] = 0
    entries[i] = { item = into, label = mode.label }
    if mode.image ~= nil then
      entries[i].image = mode.image
    else
      entries[i].picture = { address = pictures.normal, width = pictures.width, height = pictures.height }
    end
  end
  local storedLine                                 -- (below) the line drawn above the panel
  -- The line now in `text` and its width: written and measured again only when it changes.
  local written, writtenWidth = nil, 0
  local function lineWidth()
    local line = storedLine()
    if line ~= written or writtenWidth <= 0 then
      writeCString(text, line:sub(1, 250))
      written, writtenWidth = line, textWidth(G.textManager, text, math.min(#line, 250), TOOLTIP_FONT)
    end
    return writtenWidth
  end
  local paint = makePanel(G, { counts = false }, data, panel, function()
    local list = {}
    for i, entry in ipairs(entries) do
      list[i] = { item = entry.item, image = entry.image, picture = entry.picture, label = entry.label,
        chosen = P.mode == i, minWidth = K.PIPETTE_ENTRY_WIDTH }
    end
    list.labelRoom = K.PIPETTE_LABEL_ROOM
    list.rectAbove = K.PIPETTE_TEXT_ABOVE
    list.aboveWidth = lineWidth()                  -- the panel's place leaves room for its line
    return list
  end)
  function storedLine()
    local mode = K.PIPETTE_MODES[P.mode]
    if P.stored == nil then
      if P.mode == K.PIPETTE_OBJECTS and P.nothing then
        return "Pipette: nothing to take there - click a building, wall, tree or rock"
      end
      return "Pipette: click a tile to take its " .. mode.what
    end
    if P.mode == K.PIPETTE_OBJECTS then
      return (reading() and "Pipette (taking) holds: " or "Pipette places: ") .. P.stored.name
    end
    local parts = {}
    if P.mode ~= K.PIPETTE_HEIGHTS then
      parts[#parts + 1] = "textures: " .. C.textureNames(P.stored.texture, P.stored.decoration)
    end
    if P.mode == K.PIPETTE_ALL and P.stored.plant ~= nil then parts[#parts + 1] = P.stored.plant.name end
    if P.mode ~= K.PIPETTE_TEXTURES then
      local line = "height " .. P.stored.base
      if P.stored.live ~= P.stored.base then line = line .. " (water " .. P.stored.live .. ")" end
      parts[#parts + 1] = line
    end
    local prefix = reading() and "Pipette (taking): " or "Pipette holds "
    return prefix .. table.concat(parts, "; ")
  end
  local function painter()
    paint()
    local first = panel.items[1]
    if rd16(first + ITEM_HIDDEN) ~= 0 then return end
    local width = lineWidth()                      -- also leaves the line in `text`
    -- Centred over the panel, in the room the panel keeps above itself (rectAbove).
    local panelLeft, panelRight = rd32(first + ITEM_X), rd32(first + ITEM_X)
    for _, address in ipairs(panel.items) do
      if rd16(address + ITEM_HIDDEN) == 0 then
        panelLeft = math.min(panelLeft, rd32(address + ITEM_X))
        panelRight = math.max(panelRight, rd32(address + ITEM_X) + rd32(address + ITEM_WIDTH))
      end
    end
    local x = rd32(G.menu + MENU_X) - rd32(G.menu + MENU_SCROLL) + (panelLeft + panelRight - width) // 2
      + rd32(G.cameraX)
    local y = rd32(G.menu + MENU_Y) + rd32(first + ITEM_Y) - K.PIPETTE_TEXT_ABOVE + rd32(G.cameraY)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    shadowedText(G.textManager, text, x, y, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    wr32(G.textLayer, layer)
  end
  local painterItem = added.pipettePanel
  wr32(painterItem + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(painterItem + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  wr32(painterItem + ITEM_RENDER, core.allocateAssembly(templates.flagPanel, {
    FLAG = activeFlag, PANEL_ITEMS = dwordList(panel.items), ITEM_HIDDEN = ITEM_HIDDEN,
    PAD = C.luaPad(painter, "the pipette panel"),
  }))

  local tickItem = added.pipetteTick
  wr32(tickItem + ITEM_TYPE, TYPE_EVERY_FRAME)
  wr32(tickItem + ITEM_ACTION, C.luaPad(tick, "the pipette"))
  data.pipette = R
end

-- The brush preview while the pipette takes a tile: one tile, whatever the brush size.
function C.patchPipettePreview(self, R, readFlag)
  wr32(readFlag, K.NO_TOOL)
  patchJump(self, R.previewSite, K.PIPETTE_PREVIEW.size, core.allocateAssembly(templates.pipettePreview, {
    ONE_TILE = readFlag, BRUSH = R.brushField, BACK = R.previewSite + K.PIPETTE_PREVIEW.size,
  }))
end

return true
