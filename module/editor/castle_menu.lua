local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
local MENU_ITEM_SIZE = layout.MENU_ITEM_SIZE
local ITEM_TYPE = layout.ITEM_TYPE
local ITEM_X = layout.ITEM_X
local ITEM_Y = layout.ITEM_Y
local ITEM_WIDTH = layout.ITEM_WIDTH
local ITEM_HEIGHT = layout.ITEM_HEIGHT
local ITEM_ACTION = layout.ITEM_ACTION
local ITEM_PARAM = layout.ITEM_PARAM
local ITEM_RENDER = layout.ITEM_RENDER
local ITEM_RENDER_TYPE = layout.ITEM_RENDER_TYPE
local ITEM_CONTROL = layout.ITEM_CONTROL
local ITEM_HIDDEN = layout.ITEM_HIDDEN
local ITEM_MENU = layout.ITEM_MENU
local TYPE_EVERY_FRAME = layout.TYPE_EVERY_FRAME
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local TYPE_GROUP_START = layout.TYPE_GROUP_START
local TYPE_GROUP_MEMBER_MASK = layout.TYPE_GROUP_MEMBER_MASK
local TYPE_GROUP_MEMBER = layout.TYPE_GROUP_MEMBER
local RENDER_NONE = layout.RENDER_NONE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local PLACED_BY_CONTROL = layout.PLACED_BY_CONTROL
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local K = layout.K
local C = layout.C
local memory = require("editor.memory")
local scan = memory.scan
local readCallTarget = memory.readCallTarget
local item = memory.item
local dwordList = memory.dwordList
local rd32 = memory.rd32
local wr32 = memory.wr32
local wr16 = memory.wr16
local resolveRocks = require("editor.native").resolveRocks
local makeRockPictures = require("editor.sprites").makeRockPictures
local ui = require("editor.ui")
local makePanel = ui.makePanel
local makeLayout = ui.makeLayout
local lane = require("editor.lane")

-- Copies the build menu's item table with the module's items added, like buildTable.
function C.build(G, B, O, barrierGM)
  local data = { shown = core.allocate(4, true) }
  C.guardRects(data)
  local inserts = {}
  local function insert(before, kind)
    inserts[before] = inserts[before] or {}
    table.insert(inserts[before], kind)
  end
  insert(0, "guard")
  -- (switching the active keep calls the game's keep entry, which destroys the old keep unless
  -- several keeps are allowed)
  if O.keepCrests and O.severalKeeps then insert(0, "keepCrests") end
  if O.rotation then
    for i = 1, #K.ROTATIONS do insert(0, "rotation" .. i) end
    insert(0, "rotationHead")                -- after the options: drawn on top of them
  end
  if O.ruinedCathedral then insert(0, "ruinWatch") end
  if O.undo then
    insert(0, "undo")
    insert(0, "redo")
  end
  if O.compass then insert(0, "compass") end
  if O.unitColour then
    for p = 0, K.PLAYERS do insert(0, "unitColour" .. p) end
    insert(0, "unitColourPanel")
  end
  if O.buildingCounts then insert(B.firstBlock, "counts") end
  local shieldGroup, shieldEnd
  if O.playerZero then
    for i = 0, B.count - 1 do
      if shieldGroup == nil and rd32(item(B.table, i, ITEM_PARAM)) == K.SHIELD_ZERO.firstParam
          and (rd32(item(B.table, i, ITEM_TYPE)) & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER then
        local start = i
        while start > 0 and (rd32(item(B.table, start, ITEM_TYPE)) & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER do
          start = start - 1
        end
        local finish = i
        while finish < B.count and (rd32(item(B.table, finish, ITEM_TYPE)) & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_MEMBER do
          finish = finish + 1
        end
        if (rd32(item(B.table, start, ITEM_TYPE)) & TYPE_GROUP_MEMBER_MASK) == TYPE_GROUP_START then
          shieldGroup, shieldEnd = start, finish
        end
      end
    end
    if shieldGroup == nil then
      log(ERROR, "The neutral player shield is off. The player shields could not be found.")
    else
      insert(shieldGroup, "shieldZeroClick")
      insert(shieldEnd, "shieldZeroDraw")
    end
  end
  local panels = {}
  local function lookup(tab, command) return B.buttons[tab][command].image end
  if O.towerRuins then
    local row = {}
    -- Each ruin's own picture, made small like the variant panels' (the tower's button
    -- picture if that cannot be made).
    local okThumbs, thumb = pcall(C.buildingPictures, G, B)
    if not okThumbs then log(WARNING, tostring(thumb) .. "; the tower ruins show the towers' pictures") end
    for i, ruin in ipairs(K.TOWER_RUINS) do
      row[i] = { command = ruin, image = lookup(K.TAB_TOWERS, K.FIRST_TOWER + i - 1), label = K.RUIN_LABEL }
      if okThumbs then row[i].compose = function() return thumb(ruin) end end
    end
    panels[#panels + 1] = { tab = K.TAB_TOWERS, rows = { row } }
  end
  if O.armyExtras then
    -- The tunnel entrance as the map shows it, composed from its tiles like a rock.
    local sprites = scan(K.AOB_BUILDING_SPRITES, "the building pictures")
    local convert = core.exposeCode(readCallTarget(sprites, 0, "the building types"), 2, 1)
    local firstPicture = core.exposeCode(readCallTarget(sprites, K.BUILDING_SPRITES.sprite, "the building pictures"), 2, 1)
    local tunnelGm = rd32(rd32(sprites + K.BUILDING_SPRITES.gms) + (convert(B.buildings, K.TUNNEL_COMMAND) & 0xFFFF) * 4)
    local tunnelBase = firstPicture(B.buildings, K.TUNNEL_COMMAND)
    if G.footprint == nil then resolveRocks(G) end
    local tilePicture = makeRockPictures(G)
    local tunnel = { when = K.TUNNEL_WHEN, { command = K.TUNNEL_COMMAND, label = K.TUNNEL_LABEL,
      compose = function() return tilePicture(K.TUNNEL_SIZE, tunnelBase, 0, tunnelGm, true) end } }
    local tents = { when = K.TENTS_WHEN }
    for i, tent in ipairs(K.TENTS) do
      tents[i] = { command = tent, image = lookup(K.TAB_UNIT_COMMANDS, tent) }
    end
    panels[#panels + 1] = { tab = K.TAB_ARMY, rows = { tunnel, tents } }
  end
  local resets = {}                        -- menu buttons that end a panel choice: { tab, command, flag }
  if O.variantPanels then
    -- One panel per tab, a row per building: its variants by placement id (chosen ones do not
    -- turn into the next), and on the statue and shrine rows the module's own.
    local lock = C.locks().variant
    local okThumbs, thumb = pcall(C.buildingPictures, G, B)
    if not okThumbs then
      log(WARNING, tostring(thumb) .. "; the variant panels show the menu's pictures")
      thumb = nil
    end
    local function thumbOf(command, base)
      if thumb == nil then return nil end
      return function() return thumb(command, base) end
    end
    local extraLabel = {}
    for _, statue in ipairs(K.STATUES) do extraLabel[statue[1]] = statue[3] end
    for tab, groups in pairs(K.VARIANT_ROWS) do
      local rows = {}
      for _, group in ipairs(groups) do
        local first, count = group[1], group[2]
        local row = { when = {} }
        local ids = {}
        for i = 0, count - 1 do ids[#ids + 1] = first + i end
        if O.statues then
          for _, extra in ipairs(group[3] or {}) do ids[#ids + 1] = extra end
        end
        for i, id in ipairs(ids) do
          row.when[id] = true
          row[i] = { command = id, image = lookup(tab, first), label = extraLabel[id] or tostring(i), lock = lock,
            compose = thumbOf(id) }
        end
        rows[#rows + 1] = row
        resets[#resets + 1] = { tab, first, lock }
      end
      panels[#panels + 1] = { tab = tab, rows = rows, lock = lock }
    end
    -- The hovel: one of its seven variants every time, instead of the player's next one.
    local hovelLock = C.locks().hovel
    local hovelPictures = rd32(scan(K.AOB_HOVEL_PREVIEW, "the hovel pictures") + K.HOVEL_PICTURES)
    local row = {}
    for i = 1, K.HOVEL_VARIANTS do
      row[i] = { images = { [K.HOVEL_TOOL] = lookup(K.TAB_TOWN, K.HOVEL_TOOL) }, tool = K.HOVEL_TOOL,
        label = tostring(i), flag = hovelLock, value = i, compose = thumbOf(K.HOVEL_TOOL, rd32(hovelPictures + (i - 1) * 4)) }
    end
    row.when = { [K.HOVEL_TOOL] = true }
    resets[#resets + 1] = { K.TAB_TOWN, K.HOVEL_TOOL, hovelLock }
    panels[#panels + 1] = { tab = K.TAB_TOWN, rows = { row } }
  elseif O.statues then
    local row = {}
    for i, statue in ipairs(K.STATUES) do
      row[i] = { command = statue[1], image = lookup(K.TAB_GOOD, statue[2]), label = statue[3] }
    end
    panels[#panels + 1] = { tab = K.TAB_GOOD, rows = { row } }
  end
  data.keepMode = core.allocate(4, true)
  data.damagedWalls = core.allocate(4, true)
  local function choices(tab, commands, flag, labels)
    local images, when, row = {}, {}, {}
    for _, command in ipairs(commands) do
      images[command], when[command] = lookup(tab, command), true
      resets[#resets + 1] = { tab, command, flag }
    end
    row.when = when
    for _, choice in ipairs(labels) do
      row[#row + 1] = { images = images, label = choice[2], flag = flag, value = choice[1] }
    end
    panels[#panels + 1] = { tab = tab, rows = { row } }
  end
  if O.keepParts then
    choices(K.TAB_KEEPS, K.KEEPS, data.keepMode, { { K.KEEP_ONLY, K.KEEP_LABELS[K.KEEP_ONLY] },
      { K.KEEP_NO_STOCKPILE, K.KEEP_LABELS[K.KEEP_NO_STOCKPILE] } })
  end
  if O.wallTools then
    -- The crenellations get a panel of their own: low, high and both damaged.
    if O.damagedWalls then
      choices(K.TAB_CASTLE, { K.STAIRS, K.LOW_WALL, K.HIGH_WALL }, data.damagedWalls, { { 1, K.DAMAGED_LABEL } })
      data.wallPanel = panels[#panels]
    end
    local labels = {}
    for _, choice in ipairs(K.CRENEL_LABELS) do
      local damaged = choice[1] == K.CRENEL_DAMAGED or choice[1] >= K.CRENEL_LOW_DAMAGED
      if O.damagedWalls or not damaged then labels[#labels + 1] = choice end
    end
    choices(K.TAB_CASTLE, { K.CRENEL_WALL }, C.wallWords().mode, labels)
    data.crenelPanel = panels[#panels]
  elseif O.damagedWalls then
    choices(K.TAB_CASTLE, K.WALLS, data.damagedWalls, { { 1, K.DAMAGED_LABEL } })
  end
  data.ruinedCathedral = C.locks().ruined
  if O.ruinedCathedral then
    choices(K.TAB_TOWN, { K.CATHEDRAL_TOOL }, data.ruinedCathedral, { { 1, K.RUINED_LABEL } })
    -- The ruin's own picture (when tile_churches.gm1 has it).
    local okThumbs, thumb = pcall(C.buildingPictures, G, B)
    if okThumbs then
      local ruin = rd32(scan(K.AOB_RUINED_CATHEDRAL, "the ruined cathedral") + K.RUINED_CATHEDRAL.picture)
      local entry = panels[#panels].rows[1][1]
      entry.compose = function() return thumb(K.CATHEDRAL_TOOL, ruin) end
    end
    data.ruinWatch = C.ruinWatch(G)
  end
  data.moatMode = core.allocate(4, true)
  if O.moatKinds then
    -- The moat tool (chosen as 0x2D) placed dug, planned or permanent; the menu's moat button
    -- goes back to dug.
    local row = { when = { [K.MOAT_TOOL] = true } }
    local images = { [K.MOAT_TOOL] = lookup(K.TAB_GATEHOUSES, K.MOAT_BUTTON) }
    for _, kind in ipairs({ K.MOAT_DUG, K.MOAT_PLANNED, K.MOAT_PERMANENT }) do
      row[#row + 1] = { images = images, tool = K.MOAT_BUTTON, label = K.MOAT_LABELS[kind], flag = data.moatMode,
        value = kind, minWidth = K.MOAT_ENTRY_WIDTH }
    end
    resets[#resets + 1] = { K.TAB_GATEHOUSES, K.MOAT_BUTTON, data.moatMode }
    panels[#panels + 1] = { tab = K.TAB_GATEHOUSES, rows = { row } }
  end
  for p, panel in ipairs(panels) do
    local most = 0
    for _, row in ipairs(panel.rows) do most = math.max(most, #row) end
    panel.size = most
    for i = 1, most do insert(B.blockEnd[panel.tab], "panel" .. p .. "/" .. i) end
    insert(B.blockEnd[panel.tab], "painter" .. p)
  end
  if barrierGM then insert(B.blockEnd[K.TAB_RUINS], "barrier") end
  if O.wallTools then
    insert(B.blockEnd[K.TAB_CASTLE], "wallSlider")
    insert(B.blockEnd[K.TAB_CASTLE], "wallSliderReset")
    insert(B.blockEnd[K.TAB_CASTLE], "wallSliderPaint")
  end

  local total = B.count + 1
  for _, list in pairs(inserts) do total = total + #list end
  local newTable = core.allocate(total * MENU_ITEM_SIZE, true)
  local movedTo, added, slot = {}, {}, 0
  for i = 0, B.count do
    for _, kind in ipairs(inserts[i] or {}) do
      added[kind] = item(newTable, slot)
      slot = slot + 1
    end
    core.writeBytes(item(newTable, slot), core.readBytes(item(B.table, i), MENU_ITEM_SIZE))
    movedTo[i] = slot
    slot = slot + 1
  end

  local guarded, places = {}, {}
  if G.blit == nil then
    G.blit = core.allocateAssembly(templates.blit, {
      PENCIL = G.pencil, SETUP_SURFACE = G.setupSurface, SETUP_PENCIL = G.setupPencil,
      SCRATCH = core.allocate(32, true), PIXEL_FORMAT = G.pixelFormat,
    })
  end
  local GB = setmetatable({ menu = B.menu }, { __index = G })   -- G with the build menu
  -- The toolbar action takes the siege tents for an order to selected engineers: those are
  -- chosen straight away, like the game's hotkeys do.
  local direct = core.allocateAssembly(templates.directTool, {
    DIRECT = dwordList(K.TENTS), SUBTYPE = G.subtype, TOOLBAR = B.toolbar,
  })
  for p, panel in ipairs(panels) do
    panel.items = {}
    for i = 1, panel.size do
      local into = added["panel" .. p .. "/" .. i]
      local entry = panel.rows[1][i]
      local action = direct
      if panel.lock ~= nil then             -- a variant: locked, then chosen like its menu button
        action = core.allocateAssembly(templates.variantChoice, { VARIANT_LOCK = panel.lock, ACTION = B.toolbar })
      elseif #panel.rows == 1 and entry ~= nil and entry.flag ~= nil then
        action = core.allocateAssembly(templates.setChoice, { FLAG = entry.flag, VALUE = entry.value, ACTION = B.toolbar })
      end
      wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
      wr32(into + ITEM_ACTION, action)
      wr32(into + ITEM_RENDER_TYPE, RENDER_NONE)
      wr16(into + ITEM_HIDDEN, 1)
      panel.items[i] = into
      guarded[#guarded + 1] = into
      guarded[#guarded + 1] = panel.tab
    end
    local paint = makePanel(GB, { counts = false }, data, panel, C.makeEntries(GB, panel, panel.rows))
    local painter = added["painter" .. p]
    wr32(painter + ITEM_TYPE, TYPE_CLICKABLE)
    wr32(painter + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(painter + ITEM_RENDER, core.allocateAssembly(templates.editorPanel, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, PANEL_ITEMS = dwordList(panel.items),
      ITEM_HIDDEN = ITEM_HIDDEN, PAD = C.luaPad(paint, "a castle panel"),
    }))
  end

  if O.buildingCounts then
    local counts = core.allocate(12, true)
    local count = core.allocateAssembly(templates.buildingCounts, {
      BUILDINGS = B.buildings, MAX_BUILDINGS = K.MAX_BUILDINGS, FIRST_STATE = B.firstState,
      BUILDING_SIZE = B.buildingSize, TYPE_FROM_STATE = B.typeFromState, OWNER_FROM_STATE = B.ownerFromState,
      REMOVED = K.BUILDING_REMOVED, PLAYER_TYPES = B.playerTypes, CURRENT_PLAYER = B.currentPlayer, COUNTS = counts,
    })
    local into = added.counts
    wr32(into + ITEM_TYPE, TYPE_CLICKABLE)    -- no size, so never under the mouse
    wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(into + ITEM_RENDER, core.allocateAssembly(templates.editorOnly, {
      GAME_MODE = G.gameMode, MAP_EDITOR = K.MAP_EDITOR, FIRST = count,
      PAD = C.luaPad(C.makeCounts(G, B, counts, data), "the building counts"),
    }))
  end

  -- The barrier: a copy of the first ruin button with the barrier's command, placed in the
  -- free spot at the end of the ruins' grid once the menu has placed them.
  if barrierGM then
    local barrier = added.barrier
    local model = B.buttons[K.TAB_RUINS][K.FIRST_RUIN]
    core.writeBytes(barrier, core.readBytes(item(B.table, model.index), MENU_ITEM_SIZE))
    wr32(barrier + ITEM_X, 0)
    wr32(barrier + ITEM_Y, 0)
    wr32(barrier + ITEM_PARAM, K.BARRIER_COMMAND)
    wr32(barrier + ITEM_ACTION, B.toolbar)
    wr32(barrier + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr16(barrier + ITEM_CONTROL, -1)
    wr16(barrier + ITEM_HIDDEN, 1)
    local draw = C.makeBarrier(G, barrierGM)
    wr32(barrier + ITEM_RENDER, C.luaPad(function() draw(barrier) end, "the barrier button"))
    local ruins = {}
    for _, button in pairs(B.buttons[K.TAB_RUINS]) do ruins[#ruins + 1] = item(newTable, movedTo[button.index]) end
    places[#places + 1] = function(measure)
      local width, height = measure(ruins[1])
      if width == nil then return false end
      local xs, ys, taken = {}, {}, {}
      for _, ruin in ipairs(ruins) do
        local x, y = rd32(ruin + ITEM_X), rd32(ruin + ITEM_Y)
        if (x & 0xFFFFFFFF) == PLACED_BY_CONTROL then return false end
        xs[x], ys[y], taken[x .. "/" .. y] = true, true, true
      end
      local columns, rows = {}, {}
      for x in pairs(xs) do columns[#columns + 1] = x end
      for y in pairs(ys) do rows[#rows + 1] = y end
      table.sort(columns)
      table.sort(rows)
      local y = rows[#rows]
      local x = nil
      for _, column in ipairs(columns) do
        if not taken[column .. "/" .. y] then x = column end
      end
      if x == nil then                         -- no free spot: one column further right
        x = columns[#columns] + (#columns > 1 and columns[#columns] - columns[#columns - 1] or width)
      end
      wr32(barrier + ITEM_X, x)
      wr32(barrier + ITEM_Y, y)
      wr32(barrier + ITEM_WIDTH, width)
      wr32(barrier + ITEM_HEIGHT, height)
      wr16(barrier + ITEM_HIDDEN, 0)
      return true
    end
  end

  for _, reset in ipairs(resets) do
    local button = B.buttons[reset[1]][reset[2]]
    wr32(item(newTable, movedTo[button.index], ITEM_ACTION), core.allocateAssembly(templates.rockButton, {
      ROCK_LOCK = reset[3], ACTION = button.action,
    }))
  end

  if O.undo then C.undoButtons(G, added, guarded, O.undo) end
  if added.shieldZeroClick ~= nil then C.shieldZero(G, added.shieldZeroClick, added.shieldZeroDraw) end
  if added.wallSlider ~= nil then
    local ok, problem = pcall(C.wallControls, G, B, data, added.wallSlider, added.wallSliderPaint,
      added.wallSliderReset)
    if not ok then
      log(ERROR, "The wall height slider is off.")
      log(WARNING, tostring(problem))
    end
  end
  if added.compass ~= nil then
    local ok, problem = pcall(C.compassItem, G, added.compass, O.undo)
    if not ok then
      log(ERROR, "The castle editor compass is off.")
      log(WARNING, tostring(problem))
    end
  end
  if added.unitColourPanel ~= nil then
    local crests = {}
    for p = 0, K.PLAYERS do crests[p] = added["unitColour" .. p] end
    local ok, problem = pcall(C.unitColours, C.owner, G, B, data, added.unitColourPanel, crests)
    if not ok then
      log(ERROR, "Choosing unit colors separately is off.")
      log(WARNING, tostring(problem))
    end
  end
  if added.rotationHead ~= nil then
    local options = {}
    for i = 1, #K.ROTATIONS do options[i] = added["rotation" .. i] end
    local ok, problem = pcall(C.buildingRotation, C.owner, G, B, data, added.rotationHead, options)
    if not ok then
      wr16(added.rotationHead + ITEM_HIDDEN, 1)
      for _, option in ipairs(options) do wr16(option + ITEM_HIDDEN, 1) end
      log(ERROR, "The building rotation list is off.")
      log(WARNING, tostring(problem))
    end
  end
  if added.keepCrests ~= nil then
    data.crestTooltip = O.crestTooltip
    local ok, problem = pcall(C.keepCrests, G, B, data, added.keepCrests)
    if not ok then
      log(ERROR, "Choosing the active keep by its crest is off.")
      log(WARNING, tostring(problem))
    end
  end
  if O.ruinedCathedral then
    local watch = added.ruinWatch
    wr32(watch + ITEM_TYPE, TYPE_EVERY_FRAME)
    wr32(watch + ITEM_ACTION, C.luaPad(data.ruinWatch, "the ruined cathedral"))
  end

  -- The guard in front of the click handlers, which also places the barrier.
  local laidOut = core.allocate(4, true)
  wr32(laidOut, #places == 0 and 1 or 0)
  local layout = makeLayout(G, {}, {}, {}, places)
  local layoutPad = C.luaPad(function()
    if layout() then wr32(laidOut, 1) end
  end, "the castle layout")
  local guard = added.guard
  wr32(guard + ITEM_TYPE, TYPE_EVERY_FRAME)
  wr32(guard + ITEM_ACTION, core.allocateAssembly(templates.guard, {
    LAID_OUT = laidOut, LAYOUT = layoutPad, GUARDED = dwordList(guarded),
    ACTIVE_TAB = G.activeTab, ITEM_HIDDEN = ITEM_HIDDEN, ITEM_HEIGHT = ITEM_HEIGHT,
    ITEM_WIDTH = ITEM_WIDTH, ITEM_MENU = ITEM_MENU, MENU_X = MENU_X, MENU_Y = MENU_Y, ITEM_X = ITEM_X,
    ITEM_Y = ITEM_Y, MOUSE = G.mouse, IS_MOUSE_INSIDE = G.isMouseInside, ON_MAP = G.onMap,
    RECTS = data.rects, THE_MENU = B.menu,
  }))
  -- The band the floating panels share: this menu's items and its description line, which the
  -- building hover text move shifts left.
  lane.prepare(data, newTable, nil, G.hoverRender, O.hoverTextLeft and K.HOVER_TEXT_SHIFT or 0)
  return newTable, data
end

return true
