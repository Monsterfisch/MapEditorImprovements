local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local K = layout.K
local C = layout.C
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local readOperand = memory.readOperand
local readCallTarget = memory.readCallTarget
local rd32 = memory.rd32
local rd16 = memory.rd16
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

-- In the map editor, any number of empty stockpiles, granaries and armouries.
function C.patchEmptyStorage(self, G)
  local E = K.EMPTY_STORAGE
  local sites, from = {}, 0x400000
  while #sites <= E.sites do
    local ok, found = pcall(core.scanForAOB, K.AOB_EMPTY_STORAGE, from, K.HERD_SEARCH_END)
    if not ok or found == nil or found == 0 then break end
    sites[#sites + 1] = found
    from = found + 1
  end
  if #sites ~= E.sites then error(MODULE_NAME .. ": the empty storage limits are not the ones this module knows") end
  for _, base in ipairs(sites) do
    local site = base + E.site
    patchJump(self, site, E.size, core.allocateAssembly(templates.storageLimit, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, LIMIT = rd8(base + E.limit) & 0xFF,
      FAIL = base + E.failRel + 4 + rd32(base + E.failRel), BACK = site + E.size,
    }))
  end
end

-- In the map editor, a player's new keep (and unique buildings: barracks, guilds, ...) no longer
-- destroys the earlier one, and further storage buildings need not touch the first.
function C.patchSeveralBuildings(self, G, O)
  local start = scan(K.AOB_EARLIER_BUILDING, "the earlier building removal")
  local calls, from = {}, start
  while #calls < 3 do
    local ok, found = pcall(core.scanForAOB, K.EARLIER_DESTROY, from, start + K.EARLIER_SEARCH)
    if not ok or found == nil or found == 0 then break end
    calls[#calls + 1] = found + K.EARLIER_DESTROY_CALL
    from = found + 1
  end
  if #calls ~= 3 then error(MODULE_NAME .. ": the earlier building removal is not the one this module knows") end
  local stub = core.allocateAssembly(templates.keepEarlier, {
    GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, DESTROY = readCallTarget(calls[1], 0, "destroyBuilding"),
    DESTROY_ARGUMENTS = K.DESTROY_ARGUMENTS,
  })
  local which = {}
  if O.severalKeeps then for _, i in ipairs(K.EARLIER_KEEP_CALLS) do which[#which + 1] = i end end
  if O.looseBuildings then for _, i in ipairs(K.EARLIER_UNIQUE_CALLS) do which[#which + 1] = i end end
  for _, i in ipairs(which) do C.patchCall(self, calls[i], stub) end
  if O.looseBuildings then
    local sites = {}
    for i, pattern in ipairs(K.AOB_STORAGE_NEIGHBOURS) do
      sites[i] = scan(pattern, "the storage placement test") + K.STORAGE_NEIGHBOUR_CALL
    end
    local neighbour = core.allocateAssembly(templates.anyNeighbour, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, HAS_NEIGHBOUR = readCallTarget(sites[1], 0, "the neighbour test"),
      NEIGHBOUR_ARGUMENTS = K.NEIGHBOUR_ARGUMENTS,
    })
    for _, site in ipairs(sites) do C.patchCall(self, site, neighbour) end
  end
end

-- In the map editor the tower mangonel and ballista can also be put on any tile without a unit
-- (ground, walls, gates, other towers, the keep): the click sends the game's own spawn command
-- for the clicked tile instead of refusing. The player's own big towers work as before.
-- Where a tower engine may go in the map editor, for the tile in rule.tile: 0 nowhere, 1 on
-- this very tile, 2 by the game's own tower rule (the current player's big towers).
function C.towerEngineRule(G, site)
  local T = K.TOWER_ENGINE
  local R = C.resolvePipette(G)
  local function operand(field) return readOperand(site, T[field], "the tower engine placement") end
  local types, owners, size = operand("types"), operand("owners"), operand("buildingSize")
  local base = types - K.BUILDING.type
  local player, units = operand("player"), operand("units")
  local onTile = readOperand(scan(K.AOB_TOWER_ENGINE_PREVIEW, "the tower engine preview"), { -0x0B, { 0x45 } },
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
  local function all(pattern)
    local from, sites = 0x400000, {}
    while #sites < 3 do
      local ok, found = pcall(core.scanForAOB, pattern, from, K.HERD_SEARCH_END)
      if not ok or found == nil or found == 0 then break end
      sites[#sites + 1] = found
      from = found + 1
    end
    return sites
  end
  local sites, previews = all(K.AOB_TOWER_ENGINE_CLICK), all(K.AOB_TOWER_ENGINE_PREVIEW)
  if #sites ~= 2 or #previews ~= 2 then
    error(MODULE_NAME .. ": the tower engine placement is not the one this module knows")
  end
  local rule = C.towerEngineRule(G, sites[1])
  for i, site in ipairs(sites) do
    local function operand(field) return readOperand(site, T[field], "the tower engine placement") end
    expectBytes(site + T.refuse[1] - 2, T.refuse[2], "the tower engine placement")
    expectBytes(site + T.command[1], T.command[2], "the tower engine placement")
    local stub = core.allocateAssembly(templates.towerEngineGround, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, TILE = rule.tile, ANSWER = rule.answer, RULE = rule.pad,
      HEIGHTS = operand("heights"),
      PARAM0 = operand("param0"), PARAM1 = operand("param1"), PARAM2 = operand("param2"),
      PARAM3 = operand("param3"), UNIT_TYPE = rd32(site + T.param3[1] + 6),
      COMMAND = rd8(site + T.command[1] + 1) & 0xFF, SYNC = operand("sync"),
      QUEUE = readCallTarget(site, T.queue, "the command queue"), EPILOGUE = site + T.epilogue,
      TOWER_PATH = site + T.size, REFUSE = site + T.size + rd32(site + 4),
    })
    patchJump(self, site, T.size, stub)
    local preview, P = previews[i], K.TOWER_PREVIEW
    expectBytes(preview + P.solid[1], P.solid[2], "the tower engine preview")
    expectBytes(preview + P.clear[1], P.clear[2], "the tower engine preview")
    patchJump(self, preview, P.size, core.allocateAssembly(templates.towerEnginePreview, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, TILE = rule.tile, ANSWER = rule.answer, RULE = rule.pad,
      BUILDING_SIZE = operand("buildingSize"), OPAQUE = preview + P.solid[1], TRANSPARENT = preview + P.clear[1],
      BACK = preview + P.size,
    }))
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

-- The game's language for the names it has no text for: German or English.
function C.language()
  local file = io.open(K.TEXT_FILE, "rb")
  if file == nil then return "en" end
  local data = file:read("a")
  file:close()
  if #data < K.TEXT_START + 4 * K.TEXT_GROUPS then return "en" end
  local at = K.TEXT_START + 1 + 2 * string.unpack("<I4", data, 1 + 4 * K.TEXT_GROUP)
  local index = 0
  while index < K.TEXT_INDEX and at < #data do
    if data:byte(at) == 0 and data:byte(at + 1) == 0 then index = index + 1 end
    at = at + 2
  end
  local chars = {}
  while at < #data and not (data:byte(at) == 0 and data:byte(at + 1) == 0) and #chars < 32 do
    chars[#chars + 1] = data:sub(at, at)
    at = at + 2
  end
  return table.concat(chars) == K.GERMAN_TEXT and "de" or "en"
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
    local from, found = 0x400000, {}
    while #found <= D.sites do
      local ok, at = pcall(core.scanForAOB, kind[1], from, 0x600000)
      if not ok or at == nil or at == 0 then break end
      found[#found + 1] = at
      from = at + 1
    end
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
  local data = nil
  if O.buildingCounts or O.towerRuins or O.armyExtras or O.statues or O.barrier or O.keepParts or O.damagedWalls
      or O.undo or O.moatKinds or O.ruinedCathedral then
    local newTable
    newTable, data = C.build(G, B, O)
    core.writeCodeInteger(B.site + 1, newTable)
    local construct = core.exposeCode(B.constructor, 2, 1)
    local function ensure()
      if rd32(B.menu) == B.table then construct(B.menu, newTable) end
    end
    ensure()
    hooks.registerHookCallback("afterInit", ensure)
  end
  -- Each patch on its own, so that one the game does not match leaves the others working.
  local function try(wanted, patch, what, ...)
    if not wanted then return end
    local ok, problem = pcall(patch, self, ...)
    if not ok then log(WARNING, tostring(problem) .. "; " .. what .. " left out") end
  end
  try(O.towerRuins, C.patchRuinSizes, "tower ruins", G)
  try(O.severalKeeps or O.looseBuildings, C.patchSeveralBuildings, "several keeps and storage buildings", G, O)
  try(O.looseBuildings, C.patchEmptyStorage, "any number of empty storage buildings", G)
  try(O.towerEngines, C.patchTowerEngines, "tower engines anywhere", G)
  try(O.keepParts, C.patchKeepParts, "the keep choices", G, data)
  try(O.damagedWalls, C.patchDamagedWalls, "damaged walls", G, data)
  try(O.wallTools, C.patchWallTools, "wall tools", G, data)
  try(O.allPlayers, C.patchAllPlayers, "all player shields")
  try(O.allKeeps, C.patchAllKeeps, "all keeps")
  try(O.hoverTextLeft, C.patchHoverText, "the hover text move")
  try(O.moatKinds and data ~= nil, C.patchMoatClick, "the moat kinds", data)
  try(O.moatKinds or O.moatRemoval, C.patchMoatModes, "the moat modes", O.moatKinds, O.moatRemoval)
  try(O.moatOnMarsh, C.patchMoatMarsh, "moat on marsh")
  try(O.variantPanels, C.patchVariantLocks, "the variant panels", G)
  log(INFO, string.format("%s: build menu changed (menu 0x%X, items 0x%X)", MODULE_NAME, B.menu, B.table))
end

return true
