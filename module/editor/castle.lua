local layout = require("editor.layout")
local AOB_GAME_MODE = layout.AOB_GAME_MODE
local GAME_MODE_OPERAND = layout.GAME_MODE_OPERAND
local ITEM_X, ITEM_Y = layout.ITEM_X, layout.ITEM_Y
local ITEM_PARAM = layout.ITEM_PARAM
local ITEM_ACTION = layout.ITEM_ACTION
local TYPE_GROUP_MEMBER_MASK = layout.TYPE_GROUP_MEMBER_MASK
local TYPE_GROUP_MEMBER = layout.TYPE_GROUP_MEMBER
local RENDER_IMAGE = layout.RENDER_IMAGE
local ITEM_IMAGE = layout.ITEM_IMAGE
local IMAGE_INDEX_MASK = layout.IMAGE_INDEX_MASK
local IMAGE_SIZE = layout.IMAGE_SIZE
local PANEL_BOTTOM = layout.PANEL_BOTTOM
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local ITEM_HOVERED = layout.ITEM_HOVERED
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_TEXT = layout.ITEM_TEXT
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_RENDER = layout.ITEM_RENDER
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local TEXTURES_MODE = layout.TEXTURES_MODE
local PENCIL_TARGET = layout.PENCIL_TARGET
local MAP_LAYER = layout.MAP_LAYER
local BOX_BLEND = layout.BOX_BLEND
local ALIGN_LEFT = layout.ALIGN_LEFT
local TOOLTIP_COLOUR = layout.TOOLTIP_COLOUR
local TOOLTIP_FONT = layout.TOOLTIP_FONT
local TOOLTIP_PADDING = layout.TOOLTIP_PADDING
local TOOLTIP_LINE = layout.TOOLTIP_LINE
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local K = layout.K
local C = layout.C
local memory = require("editor.memory")
local scan = memory.scan
local item = memory.item
local scanUnique = memory.scanUnique
local buttonPictures = require("editor.images").buttonPictures
local expectBytes = memory.expectBytes
local readOperand = memory.readOperand
local readCallTarget = memory.readCallTarget
local rd32 = memory.rd32
local rd16 = memory.rd16
local wr16 = memory.wr16
local writeCString = memory.writeCString
local rd8 = memory.rd8
local wr32 = memory.wr32
local native = require("editor.native")
local resolveMenu = native.resolveMenu
local resolveDrawing = native.resolveDrawing
local patchJump = require("editor.menu_install").patchJump

function C.signedByte(address)
  local value = rd8(address) & 0xFF
  if value >= 0x80 then value = value - 0x100 end
  return value
end

-- A lua function called from injected code: a pad that runs it, switched off after an error.
function C.luaPad(fn, what)
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

-- Replaces the call at site with a call to stub, remembering it for disable.
function C.patchCall(self, site, stub)
  self.saved = self.saved or {}
  table.insert(self.saved, { address = site, bytes = core.readBytes(site, 5) })
  core.writeCode(site, { 0xE8, core.itob(core.getRelativeAddress(site, stub, -5)) })
end

-- Empty stockpiles, granaries and armouries can exceed their game limits in the editor.
local function prepareEmptyStorage(gameMode)
  local E = K.EMPTY_STORAGE
  local sites = memory.scanAll(K.AOB_EMPTY_STORAGE, E.sites + 1)
  if #sites ~= E.sites then error(MODULE_NAME .. ": the empty storage limits are not the ones this module knows") end
  local patches = {}
  for _, base in ipairs(sites) do
    local site = base + E.site
    patches[#patches + 1] = { site = site, stub = core.allocateAssembly(templates.storageLimit, {
      GAME_MODE = gameMode, MAP_EDITOR = K.MAP_EDITOR, LIMIT = rd8(base + E.limit) & 0xFF,
      FAIL = base + E.failRel + 4 + rd32(base + E.failRel), BACK = site + E.size,
    }) }
  end
  return patches
end

-- Replacing a keep or a unique building leaves its earlier instance in the editor.
local function prepareEarlierBuildings()
  local gameMode = C.gameModeOf()
  local start = scan(K.AOB_EARLIER_BUILDING, "the earlier building removal")
  local calls, from = {}, start
  for i = 1, 3 do
    local found = core.scanForAOB(K.EARLIER_DESTROY, from, start + K.EARLIER_SEARCH)
    if not found or found == 0 then error(MODULE_NAME .. ": unexpected earlier building removal") end
    calls[i], from = found + K.EARLIER_DESTROY_CALL, found + 1
  end
  local target = readCallTarget(calls[1], 0, "destroyBuilding")
  for i = 2, #calls do
    if readCallTarget(calls[i], 0, "destroyBuilding") ~= target then
      error(MODULE_NAME .. ": the building removal calls have different targets")
    end
  end
  local stub = core.allocateAssembly(templates.keepEarlier, {
    GAME_MODE = gameMode, MAP_EDITOR = K.MAP_EDITOR, DESTROY = target,
    DESTROY_ARGUMENTS = K.DESTROY_ARGUMENTS,
  })
  return calls, stub, gameMode
end

function C.enableExtraBuildings(self, O)
  local bound, calls, stub, gameMode = pcall(prepareEarlierBuildings)
  local function install(option, name, patch)
    if not O[option] then return end
    local ok, problem = pcall(function()
      if not bound then error(calls, 0) end
      patch()
    end)
    if not ok then
      O[option] = false
      log(ERROR, name .. " is off. " .. tostring(problem))
    end
  end
  install("severalKeeps", "Placing extra keeps", function()
    for _, i in ipairs(K.EARLIER_KEEP_CALLS) do C.patchCall(self, calls[i], stub) end
  end)
  install("looseBuildings", "Placing extra storage and recruitment buildings", function()
    local sites = {}
    local target
    for i, pattern in ipairs(K.AOB_STORAGE_NEIGHBOURS) do
      local site = scan(pattern, "the storage placement test") + K.STORAGE_NEIGHBOUR_CALL
      local callee = readCallTarget(site, 0, "the neighbour test")
      if target ~= nil and callee ~= target then error("the storage placement calls have different targets") end
      sites[i], target = site, callee
    end
    local neighbour = core.allocateAssembly(templates.anyNeighbour, {
      GAME_MODE = gameMode, MAP_EDITOR = K.MAP_EDITOR, HAS_NEIGHBOUR = target,
      NEIGHBOUR_ARGUMENTS = K.NEIGHBOUR_ARGUMENTS,
    })
    local limits = prepareEmptyStorage(gameMode)
    for _, i in ipairs(K.EARLIER_UNIQUE_CALLS) do C.patchCall(self, calls[i], stub) end
    for _, site in ipairs(sites) do C.patchCall(self, site, neighbour) end
    for _, limit in ipairs(limits) do patchJump(self, limit.site, K.EMPTY_STORAGE.size, limit.stub) end
  end)
end

local function towerEngineClicks(G)
  if G.towerEngineClicks == nil then
    local sites = memory.scanAll(K.AOB_TOWER_ENGINE_CLICK, 3)
    if #sites ~= 2 then error("the tower engine click sites could not be verified", 0) end
    G.towerEngineClicks = sites
  end
  return G.towerEngineClicks
end

-- In the map editor the tower mangonel and ballista can also be put on any tile without a unit
-- (ground, walls, gates, other towers, the keep): the click sends the game's own spawn command
-- for the clicked tile instead of refusing. The player's own big towers work as before.
-- Where a tower engine may go in the map editor, for the tile in rule.tile: 0 nowhere, 1 on
-- this very tile, 2 by the game's own tower rule (the current player's big towers).
local function towerEngineRule(G, site, preview)
  local T = K.TOWER_ENGINE
  local R = C.resolvePipette(G)
  local function operand(field) return readOperand(site, T[field], "the tower engine placement") end
  local types, owners, size = operand("types"), operand("owners"), operand("buildingSize")
  local base = types - K.BUILDING.type
  local player, units = operand("player"), operand("units")
  local onTile = readOperand(preview, { -0x0B, { 0x45 } },
    "the tower engine preview")
  expectBytes(site + K.TOWER_PREVIEW.flags[1], K.TOWER_PREVIEW.flags[2], "the tower engine placement")
  local flags = rd32(site + K.TOWER_PREVIEW.flags[1] + #K.TOWER_PREVIEW.flags[2])
  local mask = rd32(scan(K.AOB_UNIT_MASK, "the unit tool's tile test") + K.UNIT_MASK)
  local walk = scan(K.AOB_UNIT_WALK, "the units on a tile")   -- the eraser may have patched the middle
  local stride, nextOnTile = rd32(walk + K.UNIT_WALK.stride), rd32(walk + K.UNIT_WALK.next)
  local status = nextOnTile - K.UNIT_WALK.nextAfterState
  local rule = { tile = core.allocate(4, true), answer = core.allocate(4, true) }
  local function engines(tile)
    local count, id, guard = 0, rd16(units + tile * 2), 0
    while id > 0 and guard < 200 do
      if K.TOWER_ENGINE_UNITS[rd16(status + K.UNIT_TYPE_AFTER_STATE + id * stride) & 0xFFFF] then count = count + 1 end
      id, guard = rd16(nextOnTile + id * stride), guard + 1
    end
    return count
  end
  local function decide(tile)
    if tile < 0 or tile >= K.MAP_TILES or engines(tile) > 0 then return 0 end
    local b = rd16(onTile + tile * 2)
    if b > 0 then
      local at = base + b * size
      local kind = rd16(at + K.BUILDING.type) & 0xFFFF
      if (kind == K.TOWER_4 or kind == K.TOWER_5) and rd16(at + K.BUILDING.owner) == rd32(player) then return 2 end
    end
    if (rd32(flags + tile * 4) & mask) ~= 0 then return 0 end
    if b <= 0 then return 1 end
    local at = base + b * size
    local most = K.TOWER_ENGINE_MOST[rd16(at + K.BUILDING.type) & 0xFFFF] or 1
    local x0, y0, side = rd16(at + K.BUILDING.x), rd16(at + K.BUILDING.y), rd8(at + K.BUILDING.size) & 0xFF
    local count = 0
    for y = math.max(0, y0 - 1), math.min(K.MAP_SIZE - 1, y0 + side) do
      for x = math.max(0, x0 - 1), math.min(K.MAP_SIZE - 1, x0 + side) do
        local t = rd32(R.rows + y * 12) + x
        if rd16(onTile + t * 2) == b then count = count + engines(t) end
      end
    end
    return count < most and 1 or 0
  end
  rule.pad = C.luaPad(function() wr32(rule.answer, decide(rd32(rule.tile))) end, "the tower engine placement")
  return rule
end

-- Tower engines anywhere in the map editor where a unit could stand, one to a tile, on the
-- clicked tile, with up to K.TOWER_ENGINE_MOST on keeps and large gatehouses; the preview is
-- solid wherever a click would place one.
function C.patchTowerEngines(self, G)
  local T = K.TOWER_ENGINE
  local sites, previews = towerEngineClicks(G), memory.scanAll(K.AOB_TOWER_ENGINE_PREVIEW, 3)
  if #previews ~= 2 then
    error(MODULE_NAME .. ": the tower engine placement is not the one this module knows")
  end
  local rule = towerEngineRule(G, sites[1], previews[1])
  local busy = scan(K.AOB_ENGINE_BUSY, "the tower engine spawn command") + K.ENGINE_BUSY.site
  local EB = K.ENGINE_BUSY
  local busyStub = core.allocateAssembly(templates.towerEngineBusy, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, HAS_ENGINE = rd32(busy + EB.field),
    BUSY = busy + EB.size + rd32(busy + EB.jump), BACK = busy + EB.size,
  })
  local clickStubs, previewStubs = {}, {}
  for i, site in ipairs(sites) do
    local function operand(field) return readOperand(site, T[field], "the tower engine placement") end
    expectBytes(site + T.refuse[1] - 2, T.refuse[2], "the tower engine placement")
    expectBytes(site + T.command[1], T.command[2], "the tower engine placement")
    clickStubs[i] = core.allocateAssembly(templates.towerEngineGround, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, TILE = rule.tile, ANSWER = rule.answer, RULE = rule.pad,
      HEIGHTS = operand("heights"),
      PARAM0 = operand("param0"), PARAM1 = operand("param1"), PARAM2 = operand("param2"),
      PARAM3 = operand("param3"), UNIT_TYPE = rd32(site + T.param3[1] + 6),
      COMMAND = rd8(site + T.command[1] + 1) & 0xFF, SYNC = operand("sync"),
      QUEUE = readCallTarget(site, T.queue, "the command queue"), EPILOGUE = site + T.epilogue,
      TOWER_PATH = site + T.size, REFUSE = site + T.size + rd32(site + 4),
    })
    local preview, P = previews[i], K.TOWER_PREVIEW
    expectBytes(preview + P.solid[1], P.solid[2], "the tower engine preview")
    expectBytes(preview + P.clear[1], P.clear[2], "the tower engine preview")
    previewStubs[i] = core.allocateAssembly(templates.towerEnginePreview, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, TILE = rule.tile, ANSWER = rule.answer, RULE = rule.pad,
      BUILDING_SIZE = operand("buildingSize"), OPAQUE = preview + P.solid[1], TRANSPARENT = preview + P.clear[1],
      BACK = preview + P.size,
    })
  end
  patchJump(self, busy, EB.size, busyStub)
  for i, site in ipairs(sites) do
    patchJump(self, site, T.size, clickStubs[i])
    patchJump(self, previews[i], K.TOWER_PREVIEW.size, previewStubs[i])
  end
end

-- The rotation list in the castle menu (head: the box showing the choice, options: one item each)
-- and, every frame in the map editor while the castle menu is up, the building orientation it
-- asks for (Location based: as the keep would turn at the start of a match, from the tile under
-- the mouse).
function C.buildingRotation(self, G, B, data, head, options)
  local site = scanUnique(K.AOB_ORIENTATION, "the building orientation") + K.ORIENTATION - 1
  expectBytes(site, { 0xA1 }, "the building orientation")
  local nativeOrientation = rd32(site + 1)
  local default = rd32(nativeOrientation)
  local gameMode = C.gameModeOf()
  local R = C.resolvePipette(G)
  local validTiles = C.resolveValidTiles()
  local turn = scanUnique(K.AOB_KEEP_TURN, "the keep's turn at the start of a match")
  local direction = rd32(turn + K.KEEP_TURN.this)
  local towards = core.exposeCode(readCallTarget(turn, K.KEEP_TURN.call, "the direction"), 5, 1)
  local result = rd32(turn + K.KEEP_TURN.result)
  local mouseSetup, flatSetup = core.exposeCode(R.mouseSetup, 1, 1), core.exposeCode(R.flatSetup, 1, 1)
  local placeRotation = R.tileMap + rd32(scanUnique(K.AOB_PLACE_ROTATION, "the placement rotation") + K.PLACE_ROTATION)
  local chosenTool = rd32(scanUnique(K.AOB_CHOSEN_TOOL, "the chosen building") + 2)
  local wanted = core.allocate(4, true)
  local wantedTool = core.allocate(4, true)
  wr32(wanted, -1)
  local typeOf = core.exposeCode(B.typeOfCommand, 2, 1)
  local function turns(tool)
    if tool <= 0 or tool > 0x200 then return false end
    return K.ROTATING_TYPES[typeOf(B.buildings, tool) & 0xFFFF] == true
  end
  local reset = scanUnique(K.AOB_PREVIEW_ROTATION_RESET, "the cursor's orientation reset") + K.PREVIEW_ROTATION_RESET
  if rd32(reset + 2) ~= placeRotation then
    error(MODULE_NAME .. ": the cursor and placement do not use the same rotation word")
  end
  local resetStub = core.allocateAssembly(templates.previewRotationReset, {
    GAME_MODE = gameMode, MAP_EDITOR = K.MAP_EDITOR, ROTATION = placeRotation,
    TOOL = chosenTool, WANTED = wanted, WANTED_TOOL = wantedTool, BACK = reset + 6,
  })
  local KT = K.KEEP_TABLES
  local previewSite = scanUnique(K.AOB_KEEP_PREVIEW_CALL, "the building preview") + KT.call
  local validator = scanUnique(K.AOB_BUILDING_VALIDATOR, "the building placement validator")
  local keepLayout = {
    GAME_MODE = gameMode, MAP_EDITOR = K.MAP_EDITOR, ROTATION = placeRotation,
    TABLE_A = rd32(scanUnique(K.AOB_KEEP_TABLE_A, "the keep layout") + KT.a),
    TABLE_B = rd32(scanUnique(K.AOB_KEEP_CAMPFIRE, "the keep's campfire area") + KT.b),
    TABLE_C = rd32(scanUnique(K.AOB_KEEP_STOCKPILE, "the keep's stockpile") + KT.c),
    KEEP_ROWS = KT.rows,
    PREVIEW = readCallTarget(previewSite, 0, "the building preview"), ARG_BYTES = 16,
  }
  -- Allowed origins for the rejected renderer's three doors, campfire and stockpile.
  keepLayout.KEEP_BOUNDS = core.allocate(KT.rows * 4 * 16, true)
  for row = 0, KT.rows * 4 - 1 do
    local minX, minY, maxX, maxY = 0, 0, K.MAP_SIZE - 1, K.MAP_SIZE - 1
    local function include(part, side)
      local x, y = rd32(part), rd32(part + 4)
      minX, minY = math.max(minX, -x), math.max(minY, -y)
      maxX, maxY = math.min(maxX, K.MAP_SIZE - x - side), math.min(maxY, K.MAP_SIZE - y - side)
    end
    for door = 0, 2 do include(keepLayout.TABLE_A + row * 24 + door * 8, 1) end
    include(keepLayout.TABLE_B + row * 8, KT.campfireSize)
    include(keepLayout.TABLE_C + row * 8, KT.stockpileSize)
    local bounds = keepLayout.KEEP_BOUNDS + row * 16
    wr32(bounds, minX)
    wr32(bounds + 4, maxX)
    wr32(bounds + 8, minY)
    wr32(bounds + 12, maxY)
  end
  local previewStub = core.allocateAssembly(templates.keepPreviewTurn, keepLayout)
  keepLayout.PREVIEW = core.allocateAssembly("sub esp,0x2C\npush ebx\npush ebp\njmp BACK", { BACK = validator + 5 })
  keepLayout.ARG_BYTES = 20
  local validatorStub = core.allocateAssembly(templates.keepPreviewTurn, keepLayout)

  local barracks = rd32(scanUnique(K.AOB_BARRACKS_ROWS, "the barracks layouts") + K.PREVIEW_PART_ROWS.barracks)
  local oil = rd32(scanUnique(K.AOB_OIL_ROWS, "the oil smelter layouts") + K.PREVIEW_PART_ROWS.oil)
  local parts = {}
  for _, entry in ipairs(K.PREVIEW_PART_CALLS) do
    local pattern, offset, skip, x, y, part = table.unpack(entry)
    local call = scanUnique(pattern, "a building preview part") + offset
    expectBytes(call + skip + 2, { 0x01, 0x3B }, "the building preview part loop")
    local source = templates.rotatedPreviewPart:gsub("X_ORIGIN", x):gsub("Y_ORIGIN", y)
    parts[#parts + 1] = {
      call, core.allocateAssembly(source, {
        GAME_MODE = gameMode, MAP_EDITOR = K.MAP_EDITOR, ROTATION = placeRotation,
        WALK = readCallTarget(call, 0, "the preview footprint iterator"), SKIP = call + skip,
        TILE_X = K.TILE_MAP.tileX, TILE_Y = K.TILE_MAP.tileY, VALID = validTiles, MAP_SIZE = K.MAP_SIZE,
        PART = part and (barracks + part * 8) or oil, ROW_SIZE = part and 24 or 8,
      }),
    }
  end
  local placementStub = core.allocateAssembly(templates.rotationRead, {
    GAME_MODE = gameMode, MAP_EDITOR = K.MAP_EDITOR, WANTED = wanted,
    TOOL = chosenTool, WANTED_TOOL = wantedTool, ORIENTATION = nativeOrientation, BACK = site + 5,
  })
  for _, part in ipairs(parts) do C.patchCall(self, part[1], part[2]) end
  C.patchCall(self, previewSite, previewStub)
  patchJump(self, validator, 5, validatorStub)
  patchJump(self, reset, 6, resetStub)
  patchJump(self, site, 5, placementStub)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local colourBox = core.exposeCode(G.colourBox, 6, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local text = core.allocate(64, true)
  local open = false
  local editorRotation = false
  local choice = 1
  local rect = C.takeRect(data)            -- clicks on the list do not reach the map
  local function location()
    if rd32(R.flatView) ~= 0 then flatSetup(R.viewport) else mouseSetup(R.viewport) end
    local x, y = rd32(R.mouseX), rd32(R.mouseY)
    if x < 0 or y < 0 or x >= K.MAP_SIZE or y >= K.MAP_SIZE then return nil end
    towards(direction, x, y, K.MAP_CENTRE, K.MAP_CENTRE)
    local o = rd32(result)
    if o == 0xF then return o end
    o = o & 0xFFFE
    if o == 6 then o = 2 elseif o == 2 then o = 6 end
    return o
  end
  local function orientation()
    local entry = K.ROTATIONS[choice]
    if entry[2] == nil then return default end
    if entry[2] == "location" then return location() or default end
    return entry[2]
  end
  local box = K.ROTATION_BOX
  local function write(str, x, y)
    writeCString(text, str)
    shadowedText(G.textManager, text, x, y, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
  end
  local function clearRotation()
    wr32(wanted, -1)
    if editorRotation then
      wr32(placeRotation, 0)
      editorRotation = false
    end
  end
  local function draw()
    if rd32(gameMode) ~= K.MAP_EDITOR then
      clearRotation()
      wr32(head + ITEM_WIDTH, 0)             -- stays drawn (and so able to come back), never clicked
      for _, o in ipairs(options) do wr16(o + ITEM_HIDDEN, 1) end
      open = false
      C.markRect(rect, 0, 0, 0, 0)
      return
    end
    wr32(head + ITEM_WIDTH, box.width)
    local listHeight = open and #K.ROTATIONS * box.option or 0
    C.markRect(rect, box.x, box.y - listHeight, box.width, box.height + listHeight)
    for _, o in ipairs(options) do wr16(o + ITEM_HIDDEN, open and 0 or 1) end
    local tool = rd32(chosenTool)
    if turns(tool) then
      local o = orientation()
      wr32(wanted, o)
      wr32(wantedTool, tool)
      editorRotation = true
    else
      clearRotation()
    end
    local ox = rd32(B.menu + MENU_X) + rd32(G.cameraX)
    local oy = rd32(B.menu + MENU_Y) + rd32(G.cameraY)
    local white = rd32(G.pixelFormat) == 0x565 and 0xFFFF or 0x7FFF
    local function frame(l, t, r, b)
      colourBox(G.pencil, l, t, r, t + 1, white)
      colourBox(G.pencil, l, b - 1, r, b, white)
      colourBox(G.pencil, l, t, l + 1, b, white)
      colourBox(G.pencil, r - 1, t, r, b, white)
    end
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    local l, t = ox + box.x, oy + box.y
    roundedBox(G.pencil, l, t, l + box.width, t + box.height, BOX_BLEND)
    frame(l, t, l + box.width, t + box.height)
    local listTop = t - #K.ROTATIONS * box.option
    if open then
      roundedBox(G.pencil, l, listTop, l + box.width, t, BOX_BLEND)
      for i, o in ipairs(options) do
        local ot = listTop + (i - 1) * box.option
        if rd16(o + ITEM_HOVERED) ~= 0 then roundedBox(G.pencil, l, ot, l + box.width, ot + box.option, BOX_BLEND) end
        if i == choice then frame(l, ot, l + box.width, ot + box.option) end
      end
    end
    wr32(G.pencil + PENCIL_TARGET, target)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    local entry = K.ROTATIONS[choice]
    write("Rotation: " .. entry[1], l + TOOLTIP_PADDING, t + (box.height - TOOLTIP_LINE) // 2 + 2)
    write("v", l + box.width - TOOLTIP_PADDING - 6, t + (box.height - TOOLTIP_LINE) // 2 + 2)
    if open then
      for i, option in ipairs(K.ROTATIONS) do
        write(option[1], l + TOOLTIP_PADDING, listTop + (i - 1) * box.option + (box.option - TOOLTIP_LINE) // 2 + 2)
      end
    end
    wr32(G.textLayer, layer)
  end
  C.luaItem(head, box.x, box.y, box.width, box.height, function() open = not open end, draw, "the rotation list")
  wr16(head + ITEM_HIDDEN, 0)              -- a hidden item is not drawn, so it could never show itself
  for i, o in ipairs(options) do
    C.luaItem(o, box.x, box.y - (#K.ROTATIONS - i + 1) * box.option, box.width, box.option, function()
      choice = i
      open = false
    end, nil, "the rotation list")
    wr16(o + ITEM_HIDDEN, 1)
  end
end

-- Ctrl + the compass of the right-click ring turns the map counter-clockwise.
function C.patchCompassTurn(self, G)
  local R = C.resolvePipette(G)
  local current = R.tileMap + K.TILE_MAP.orientation
  local setRotation = nil
  for _, entry in ipairs(K.AOB_COMPASS_TURN) do
    local site = scan(entry[1], "the compass of the right-click ring") + K.COMPASS_TURN_SITE
    local target = readCallTarget(site, entry[3] + 6, "setMapRotation")
    if setRotation ~= nil and target ~= setRotation then
      error(MODULE_NAME .. ": the compass does not turn the map the way this module knows")
    end
    setRotation = target
    patchJump(self, site, entry[3], core.allocateAssembly(templates[entry[2]], {
      IMPORT = R.keyState, NEXT = rd32(site + entry[3] - 4), CURRENT = current, BACK = site + entry[3],
    }))
  end
end

-- The compass of the right-click ring, always shown in the map editor below the undo buttons
-- (at the undo buttons' place without them): an item drawn every frame, never under the mouse.
function C.compassItem(G, at, undo)
  local R = C.resolvePipette(G)
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local site = scan(K.AOB_COMPASS_DRAW, "the compass picture")
  local first, gm = rd8(site + K.COMPASS_DRAW.first) & 0xFF, rd8(site + K.COMPASS_DRAW.gm) & 0xFF
  local orientation = R.tileMap + K.TILE_MAP.orientation
  wr32(at + ITEM_TYPE, TYPE_CLICKABLE)
  wr32(at + ITEM_WIDTH, 0)
  wr32(at + ITEM_HEIGHT, 0)
  wr32(at + ITEM_RENDER_TYPE, RENDER_SIMPLE)
  wr32(at + ITEM_TEXT, 0)
  wr16(at + ITEM_CONTROL, -1)
  wr16(at + ITEM_HIDDEN, 0)
  wr32(at + ITEM_RENDER, C.luaPad(function()
    if rd32(R.gameMode) ~= K.MAP_EDITOR then return end
    local index = K.COMPASS_PICTURE[rd32(orientation)]
    if index == nil then return end
    local top = K.UNDO_BUTTONS.top
    if undo ~= nil and undo.pictures ~= nil then
      top = top + math.max(undo.pictures.undo.height, undo.pictures.redo.height) + K.UNDO_BUTTONS.gap
    end
    local t = G.textures
    local mode = rd32(t + TEXTURES_MODE)
    wr32(t + TEXTURES_MODE, MAP_LAYER)
    renderGM(t, gm, first + index, K.UNDO_BUTTONS.left + rd32(G.cameraX), top + rd32(G.cameraY))
    wr32(t + TEXTURES_MODE, mode)
  end, "the compass"))
end

-- The unit display player (46.1): a panel above the castle menu's unit tabs with a crest per
-- player 0..8; new units placed in the map editor are drawn in the chosen player's colours. It
-- follows the current player whenever that changes.
function C.unitColours(self, G, B, data, panel, crests)
  local R = C.resolvePipette(G)
  local site = scan(K.AOB_UNIT_COLOUR, "the unit placement") + K.UNIT_COLOUR.site
  local clicks = towerEngineClicks(G)
  local player = readOperand(clicks[1], K.TOWER_ENGINE.player, "the current player")
  if player ~= readOperand(clicks[2], K.TOWER_ENGINE.player, "the current player") then
    error("the tower engine commands disagree on the current player", 0)
  end
  local walk = scan(K.AOB_UNIT_WALK, "the units")
  local SEL = K.SELECTION
  local stride = rd32(walk + K.UNIT_WALK.stride)
  local first = rd32(walk + K.UNIT_WALK.next) - K.UNIT_WALK.nextAfterState - SEL.state   -- unit 0
  local colour = core.allocate(4, true)
  wr32(colour, rd32(player))
  -- read before the patch below overwrites these bytes
  local units = rd32(site + K.UNIT_COLOUR.units)
  local stub = core.allocateAssembly(templates.unitColour, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, COLOUR = colour,
    UNITS = units, BACK = site + K.UNIT_COLOUR.size,
  })
  local group = K.GROUP_COLOUR
  local sites = memory.scanAll(K.AOB_GROUP_COLOUR, group.sites + 1)
  local groupStubs = {}
  if #sites == group.sites then
    for _, address in ipairs(sites) do
      local at = address + group.site
      groupStubs[#groupStubs + 1] = { at, core.allocateAssembly(templates.unitColourEdi, {
        GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, COLOUR = colour,
        UNITS = rd32(at + group.units), BACK = at + group.size,
      }) }
    end
  else
    log(ERROR, "Choosing group unit colors separately is off.")
  end
  patchJump(self, site, K.UNIT_COLOUR.size, stub)
  for _, patch in ipairs(groupStubs) do patchJump(self, patch[1], group.size, patch[2]) end
  data.unitColour = colour
  -- The crest pictures, as the keep crests take them from the player shields.
  local crest = {}
  for i = 0, B.count - 1 do
    local p = -9 - rd32(item(B.table, i, ITEM_PARAM))
    if p >= 1 and p <= K.PLAYERS and crest[p] == nil
        and (rd32(item(B.table, i, ITEM_TYPE)) & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER
        and rd32(item(B.table, i, ITEM_RENDER_TYPE)) == RENDER_IMAGE then
      local image = G.buttonImages + (rd32(item(B.table, i, ITEM_IMAGE)) & IMAGE_INDEX_MASK) * IMAGE_SIZE
      crest[p] = { gm = rd32(image), picture = rd32(image + 4) }
    end
  end
  local zero = buttonPictures("shield0")
  local w, h = zero.width, zero.height
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local blit = core.exposeCode(G.blit or core.allocateAssembly(templates.blit, {
    PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
    SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
  }), 3, 0)
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local text = core.allocate(64, true)
  writeCString(text, K.UNIT_COLOUR_PANEL.label)
  local labelWidth = textWidth(G.textManager, text, #K.UNIT_COLOUR_PANEL.label, TOOLTIP_FONT)
  local P = K.UNIT_COLOUR_PANEL
  local width = 2 * TOOLTIP_PADDING + labelWidth + TOOLTIP_PADDING + (K.PLAYERS + 1) * (w + P.gap) - P.gap
  local height = h + 2 * TOOLTIP_PADDING
  local top = PANEL_BOTTOM - P.above - height       -- above the building counts
  local rect = C.takeRect(data)
  local lastPlayer = rd32(player)
  for p = 0, K.PLAYERS do
    local x = P.x + 2 * TOOLTIP_PADDING + labelWidth + p * (w + P.gap)
    C.luaItem(crests[p], x, top + TOOLTIP_PADDING, w, h, function() wr32(colour, p) end, nil, "the unit display player")
    wr16(crests[p] + ITEM_HIDDEN, 1)
  end
  -- Selected units: the current player's (1-8) selection takes the panel over; a crest then
  -- recolours them.
  local selectedColour = nil
  -- In the unit tabs the crests always choose the colour of new units; elsewhere a selection of
  -- the current player's units (1-8) takes them over.
  local function selecting()
    if K.UNIT_TABS[rd32(G.activeTab)] then return false end
    local p = rd32(player)
    return p >= 1 and p <= K.PLAYERS and rd32(units + SEL.counts + p * 4) > 0
  end
  local function eachSelected(fn)
    local p = rd32(player)
    for id = 1, rd32(units) - 1 do
      local u = first + id * stride
      if rd16(u + SEL.state) == SEL.alive and rd16(u + SEL.selectedBy) == p then fn(u) end
    end
  end
  for p = 0, K.PLAYERS do
    wr32(crests[p] + ITEM_ACTION, C.luaPad(function()
      if selecting() then
        eachSelected(function(u) wr16(u + SEL.colour, p) end)
        selectedColour = p
      else
        wr32(colour, p)
      end
    end, "the unit display player"))
  end
  local lastCount = -1
  local function shown()
    if rd32(R.gameMode) ~= K.MAP_EDITOR then return false end
    if selecting() then
      local count = rd32(units + SEL.counts + rd32(player) * 4)
      if count ~= lastCount then          -- a new selection: show the colour its first unit has
        lastCount, selectedColour = count, nil
        eachSelected(function(u) if selectedColour == nil then selectedColour = rd16(u + SEL.colour) end end)
      end
      return true
    end
    lastCount = -1
    return K.UNIT_TABS[rd32(G.activeTab)] == true
  end
  C.luaItem(panel, 0, 0, 0, 0, nil, function()
    -- a new current player brings the choice along
    local now = rd32(player)
    if now ~= lastPlayer then
      lastPlayer = now
      wr32(colour, now)
    end
    if not shown() then
      C.markRect(rect, 0, 0, 0, 0)
      for p = 0, K.PLAYERS do wr16(crests[p] + ITEM_HIDDEN, 1) end
      return
    end
    for p = 0, K.PLAYERS do wr16(crests[p] + ITEM_HIDDEN, 0) end
    C.markRect(rect, P.x, top, width, height)
    local ox = rd32(B.menu + MENU_X) + rd32(G.cameraX)
    local oy = rd32(B.menu + MENU_Y) + rd32(G.cameraY)
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, ox + P.x, oy + top, ox + P.x + width, oy + top + height, BOX_BLEND)
    local t = G.textures
    local mode = rd32(t + TEXTURES_MODE)
    wr32(t + TEXTURES_MODE, MAP_LAYER)
    local chosen = rd32(colour)
    if selecting() then chosen = selectedColour or -1 end
    for p = 0, K.PLAYERS do
      local sx, sy = ox + rd32(crests[p] + ITEM_X), oy + rd32(crests[p] + ITEM_Y)
      if p == 0 then
        blit(chosen == 0 and zero.chosen or zero.normal, sx, sy)
      elseif crest[p] ~= nil then
        renderGM(t, crest[p].gm, crest[p].picture + (chosen == p and K.CREST.selected or 0), sx, sy)
      end
    end
    wr32(t + TEXTURES_MODE, mode)
    wr32(G.pencil + PENCIL_TARGET, target)
    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    writeCString(text, selecting() and P.selectedLabel or P.label)
    shadowedText(G.textManager, text, ox + P.x + TOOLTIP_PADDING, oy + top + (height - TOOLTIP_LINE) // 2 + 2,
      ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
    wr32(G.textLayer, layer)
  end, "the unit display player")
  wr16(panel + ITEM_HIDDEN, 0)
end

-- Callers without a menu context share the checked game mode binding.
local checkedGameMode
function C.gameModeOf(G)
  if checkedGameMode == nil then
    checkedGameMode = rd32(scanUnique(AOB_GAME_MODE, "the game mode") + GAME_MODE_OPERAND)
  end
  if G then G.gameMode = checkedGameMode end
  return checkedGameMode
end

-- 47.1: a smaller map size takes the cut-off tiles away at once (no reload needed).
function C.patchSizeRefresh(self, G)
  local validTiles = C.resolveValidTiles()
  local load = scan(K.AOB_VIEWPORT_LOAD, "the map load's viewport setup")
  local V = K.VIEWPORT_LOAD
  local site = scan(K.AOB_SIZE_TAIL, "the map size change") + K.SIZE_TAIL.site
  local sizeSite = scan(K.AOB_SIZE_WORD, "the map size")
  local sizeWord = rd32(sizeSite + K.SIZE_WORD)
  expectBytes(site, { 0xB9 }, "the map size change")
  patchJump(self, site, K.SIZE_TAIL.size, core.allocateAssembly(templates.sizeRefresh, {
    GAME_MODE = C.gameModeOf(G), MAP_EDITOR = K.MAP_EDITOR, VIEWPORT = rd32(load + V.viewport),
    BUILD = readCallTarget(load, V.build, "the viewport's tile map"),
    TWEAK = readCallTarget(load, V.tweak, "the viewport's border tiles"),
    BOUNDS = readCallTarget(load, V.bounds, "the camera bounds"),
    TILEMAP = rd32(site - K.SIZE_TAIL.site + 1), SIZE_WORD = sizeWord,
    -- resetHeightAndMapBorders: the size action calls it, then resetAreaBasedOnLogicalLayer
    -- empties every border tile and clears its flags as well; flagged again, the tiles turn off
    -- below and are drawn black, as after loading the map.
    BORDERS = readCallTarget(sizeSite, K.SIZE_WORD + 4, "the map borders"),
    CHANGED = readCallTarget(scan(K.AOB_ALL_CHANGED, "the map redraw"), K.ALL_CHANGED, "the map redraw"),
    PAD = C.luaPad(function()
      -- every tile the resize marked as border (0x10 / 0x20) is off, whatever the tweak did
      local R = C.resolvePipette(G)
      local T = R.tileMap
      for y = 0, K.MAP_SIZE - 1 do
        local row = rd32(R.rows + y * 12)
        for x = 0, K.MAP_SIZE - 1 do
          local at = validTiles + y * K.MAP_SIZE + x
          if rd8(at) ~= 0 and (rd32(T + R.logic + (row + x) * 4) & K.MAP_BORDER) ~= 0 then
            core.writeByte(at, 0)
          end
        end
      end
    end, "the map size change"),
    AFTER_THIS = rd32(site + 1), BACK = site + K.SIZE_TAIL.size,
  }))
end

-- 47.2: the map editor's camera goes one tile further on every side, so the edge tiles show whole.
function C.patchCameraEdge(self, G)
  local site = scan(K.AOB_CAMERA_CLAMP, "the camera bounds")
  patchJump(self, site, K.CAMERA_CLAMP.size, core.allocateAssembly(templates.cameraEdge, {
    GAME_MODE = C.gameModeOf(G), MAP_EDITOR = K.MAP_EDITOR, TILE_X = K.CAMERA_EDGE.x, TILE_Y = K.CAMERA_EDGE.y,
    BACK = site + K.CAMERA_CLAMP.size,
  }))
end

-- Keeps leave the ground as it is in the map editor: placeKeep's two calls of the ground painter
-- (keep tiles: earth and stones 6 around, or thick scrub 3 around on scrub and oasis grass; the
-- campfire area likewise) do nothing there.
function C.patchKeepGround(self, G)
  local stub = core.allocateAssembly(templates.keepGround, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR,
    PAINT = readCallTarget(scan(K.AOB_KEEP_GROUND[1], "the keep's ground painting"), K.KEEP_GROUND_CALL, "the ground painter"),
  })
  for _, pattern in ipairs(K.AOB_KEEP_GROUND) do
    local site = scan(pattern, "the keep's ground painting") + K.KEEP_GROUND_CALL
    C.patchCall(self, site, stub)
  end
end

-- The keep panel's choices: in the map editor placeKeep stops after the keep and its doors
-- (keep only) or before the stockpile.
function C.patchKeepParts(self, G, data)
  local campfire = scan(K.AOB_KEEP_CAMPFIRE, "the keep's campfire area")
  local stockpile = scan(K.AOB_KEEP_STOCKPILE, "the keep's stockpile")
  local epilogue = stockpile + K.KEEP_EPILOGUE[1]
  expectBytes(epilogue, K.KEEP_EPILOGUE[2], "the end of placeKeep")
  local function stop(site, size, modes, replay)
    patchJump(self, site, size, core.allocateAssembly(templates.keepPart .. replay .. "\njmp BACK\n", {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, KEEP_MODE = data.keepMode, FIRST_MODE = modes[1],
      SECOND_MODE = modes[2] or modes[1], EPILOGUE = epilogue, BACK = site + size, TABLE = rd32(site + 7),
    }))
  end
  stop(campfire, K.KEEP_CAMPFIRE_SIZE, { K.KEEP_ONLY }, "mov eax,[esp+0x3C]\nmov ecx,[esp+0x48]")
  stop(stockpile, K.KEEP_STOCKPILE_SIZE, { K.KEEP_ONLY, K.KEEP_NO_STOCKPILE }, "mov eax,[esp+0x3C]\nmov edi,[eax*8+TABLE]")

  -- The placement check and the preview leave out the same parts.
  local function leaveOut(site, size, modes, replay, done, table)
    patchJump(self, site, size, core.allocateAssembly(templates.keepPart .. replay .. "\njmp BACK\n", {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, KEEP_MODE = data.keepMode, FIRST_MODE = modes[1],
      SECOND_MODE = modes[2] or modes[1], EPILOGUE = done, BACK = site + size, TABLE = table,
    }))
  end
  local KC, KP = K.KEEP_CHECK, K.KEEP_PREVIEW
  local check = scan(K.AOB_KEEP_CHECK, "the keep placement check")
  local checkStockpile = check + KC.stockpile
  expectBytes(checkStockpile, { 0x8B, 0x44, 0x24, 0x4C, 0x8B, 0x98 }, "the keep placement check")
  expectBytes(checkStockpile + KC.done, KC.doneBytes, "the end of the placement check")
  local preview = scan(K.AOB_KEEP_PREVIEW, "the keep preview")
  local previewStockpile = scan(K.AOB_KEEP_PREVIEW_STOCKPILE, "the keep preview")
  expectBytes(previewStockpile + KP.done, KP.doneBytes, "the keep preview")
  leaveOut(check, KC.size, { K.KEEP_ONLY }, "mov eax,[esp+0x48]\nshl eax,5", checkStockpile + KC.done, 0)
  leaveOut(checkStockpile, KC.stockpileSize, { K.KEEP_ONLY, K.KEEP_NO_STOCKPILE }, "mov eax,[esp+0x4C]\nmov ebx,[eax+TABLE]",
    checkStockpile + KC.done, rd32(checkStockpile + KC.table))
  leaveOut(preview, KP.size, { K.KEEP_ONLY }, "shl edx,5\nadd ebp,[edx+TABLE]", previewStockpile + KP.done,
    rd32(preview + KP.table))
  leaveOut(previewStockpile, KP.stockpileSize, { K.KEEP_ONLY, K.KEEP_NO_STOCKPILE }, "mov eax,[esp+0x38]\nmov ebp,[eax+TABLE]",
    previewStockpile + KP.done, rd32(previewStockpile + KP.stockpileTable))
end

-- All eight player shields beside the minimap on every map type. The shields' render function,
-- in the map editor, shows players 1-5 on scenario maps and only player 1 on other single
-- player maps (`cmp [map type],ebp / jne <shown>`): the jne becomes a jmp.
K.AOB_PLAYER_SHIELDS = "B8 F7 FF FF FF 2B C6 39 2D ? ? ? ? 75 ? 39 1D ? ? ? ? 75 ? 83 F8 05 7E"
K.PLAYER_SHIELDS_JUMP = 0x0D
function C.patchAllPlayers(self)
  local site = scan(K.AOB_PLAYER_SHIELDS, "the player shields") + K.PLAYER_SHIELDS_JUMP
  self.saved = self.saved or {}
  table.insert(self.saved, { address = site, bytes = core.readBytes(site, 1) })
  core.writeCodeByte(site, 0xEB)
end

-- The manor house and the stronghold in the keeps menu on multiplayer maps too. isMapperAvailable
-- refuses placement ids 60 (manor house) and 62-64 there in the map editor (`cmp edx,0x3C / je
-- <no> / cmp edx,0x3D / jle <yes> / cmp edx,0x40 / jle <no>`); 0x3F and 0x3E leave only 63-64 out.
K.AOB_MAPPER_KEEPS = "83 3D ? ? ? ? 01 7C 17 83 FA 3C 74 E3 83 FA 3D 7E 05 83 FA 40 7E D9"
K.MAPPER_KEEPS = { first = 0x0B, second = 0x10 }
function C.patchAllKeeps(self)
  local site = scan(K.AOB_MAPPER_KEEPS, "the keep buttons' availability")
  self.saved = self.saved or {}
  for _, at in ipairs({ K.MAPPER_KEEPS.first, K.MAPPER_KEEPS.second }) do
    table.insert(self.saved, { address = site + at, bytes = core.readBytes(site + at, 1) })
  end
  core.writeCodeByte(site + K.MAPPER_KEEPS.first, 0x3F)
  core.writeCodeByte(site + K.MAPPER_KEEPS.second, 0x3E)
end

-- Damaged walls: in the map editor, with the choice on, every wall tile placeWalls builds or
-- repairs gets the damaged look (its damage byte; the height stays).
-- A dust cloud whose speed is 0 skips its step instead of dividing by zero (all four steps).
function C.patchDustClouds(self)
  local D = K.DUST_STEP
  local sites = {}
  for _, kind in ipairs({ { K.AOB_DUST_X, D.x, D.xSize }, { K.AOB_DUST_Y, 0, D.ySize } }) do
    local found = memory.scanAll(kind[1], D.sites + 1)
    if #found ~= D.sites then error(MODULE_NAME .. ": the dust clouds' steps are not the ones this module knows") end
    for _, at in ipairs(found) do
      -- The step's code ends in `jge rel8`: its next instruction is the negative case, its
      -- target the positive one, and the step ends 10 bytes after that.
      local step = at + kind[2]
      local negative = step + kind[3]
      expectBytes(negative - 2, { 0x7D }, "the dust clouds' steps")
      local positive = negative + (rd8(negative - 1) & 0xFF)
      sites[#sites + 1] = { site = step, size = kind[3], stub = core.allocateAssembly(templates.dustStep, {
        STEP_NEGATIVE = negative, STEP_POSITIVE = positive, STEP_SKIP = positive + D.skip,
      }) }
    end
  end
  for _, s in ipairs(sites) do patchJump(self, s.site, s.size, s.stub) end
end

function C.patchDamagedWalls(self, G, data)
  local site = scan(K.AOB_WALL_TILE_DONE, "the wall placement")
  local damage = rd32(scan(K.AOB_WALL_DAMAGE, "the wall drawing") + K.WALL_DAMAGE_OPERAND)
  local R = C.resolvePipette(G)
  local W = C.wallWords()
  patchJump(self, site, K.WALL_TILE_DONE_SIZE, core.allocateAssembly(templates.damagedWall, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, FLAG = data.damagedWalls, DAMAGE = damage,
    CRENEL_HEIGHT = W.height, LOGIC = R.logic, BASE = R.defaultHeight, LIVE = R.height,
    CLEAR_MOAT = readCallTarget(site, K.WALL_CLEAR_MOAT_CALL, "the wall placement"),
    BACK = site + K.WALL_TILE_DONE_SIZE,
  }))
end

-- The building hover text of castle mode ("Player 1's Keep") moves left, clear of the building
-- counts. The code is the map editor's branch only.
function C.patchHoverText(self)
  local site = scan(K.AOB_HOVER_TEXT, "the building hover text")
  patchJump(self, site, K.HOVER_TEXT_SIZE, core.allocateAssembly(templates.hoverTextLeft, {
    SHIFT = K.HOVER_TEXT_SHIFT, PLAYER = rd32(site + K.HOVER_TEXT_PLAYER), BACK = site + K.HOVER_TEXT_SIZE,
  }))
end

-- Tower ruins get the size of their tower (the game has none for them) in the map editor.
function C.patchRuinSizes(self, G)
  local size = scan(K.AOB_BUILDING_SIZE, "the building sizes")
  patchJump(self, size, K.BUILDING_SIZE_START, core.allocateAssembly(templates.ruinSize, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, FIRST_RUIN = K.TOWER_RUINS[1],
    LAST_RUIN = K.TOWER_RUINS[#K.TOWER_RUINS], TOWER_FROM_RUIN = K.TOWER_RUINS[1] - K.FIRST_TOWER,
    SIZE_BASE = C.signedByte(size + 6) & 0xFFFFFFFF, BACK = size + K.BUILDING_SIZE_START,
  }))
end

function C.enable(self, O)
  -- What the landscape menu found, if it ran: its constructor no longer pushes the table the
  -- search looks for once the module's copy is in.
  local G = self.landscape
  if G == nil then
    G = {}
    resolveMenu(G)
    resolveDrawing(G)
  end
  local B = C.resolve(G)
  local data, barrierGM
  if O.barrier then
    local ok, result = pcall(C.resolveBarrierPicture, G)
    if ok then
      barrierGM = result
    else
      log(ERROR, "The Barrier button is off. " .. tostring(result))
    end
  end
  if O.buildingCounts or O.towerRuins or O.armyExtras or O.statues or barrierGM or O.keepParts or O.damagedWalls
      or O.undo or O.moatKinds or O.ruinedCathedral or O.rotation then
    local newTable
    C.owner = self                         -- for patches made while the table is built
    newTable, data = C.build(G, B, O, barrierGM)
    core.writeCodeInteger(B.site + 1, newTable)
    local construct = core.exposeCode(B.constructor, 2, 1)
    local function ensure()
      if rd32(B.menu) == B.table then construct(B.menu, newTable) end
    end
    ensure()
    hooks.registerHookCallback("afterInit", ensure)
  end
  -- Each patch on its own, so that one the game does not match leaves the others working.
  local function try(wanted, patch, message, ...)
    if not wanted then return end
    local ok, problem = pcall(patch, self, ...)
    if not ok then
      log(ERROR, message)
      log(WARNING, tostring(problem))
    end
  end
  try(O.towerRuins, C.patchRuinSizes, "Placing tower ruins is off.", G)
  try(O.towerEngines, C.patchTowerEngines, "Placing tower engines away from towers is off.", G)
  try(O.keepParts, C.patchKeepParts, "Placing parts of a keep is off.", G, data)
  try(O.keepGround, C.patchKeepGround, "Preserving ground when placing keeps is off.", G)
  try(O.damagedWalls, C.patchDamagedWalls, "Placing damaged walls and stairs is off.", G, data)
  try(O.wallTools, C.patchWallTools, "Editor wall placement changes are off.", G, data)
  try(O.allPlayers, C.patchAllPlayers, "Showing all eight player shields is off.")
  try(O.allKeeps, C.patchAllKeeps, "Manor and stronghold placement on all maps is off.")
  try(O.hoverTextLeft, C.patchHoverText, "Moving building hover text away from the counts is off.")
  try(O.moatKinds and data ~= nil, C.patchMoatClick, "Choosing the moat type is off.", data)
  try(O.moatKinds or O.moatRemoval, C.patchMoatModes, "The moat terrain and placement changes are off.", O.moatKinds, O.moatRemoval)
  try(O.moatOnMarsh, C.patchMoatMarsh, "Placing moats on marsh is off.")
  try(O.variantPanels, C.patchVariantLocks, "Locking the chosen building variant is off.", G)
end

return true
