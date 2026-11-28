local layout = require("editor.layout")
local templates = layout.templates
local MODULE_NAME = layout.MODULE_NAME
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
local TYPE_EVERY_FRAME = layout.TYPE_EVERY_FRAME
local TYPE_CLICKABLE = layout.TYPE_CLICKABLE
local RENDER_NONE = layout.RENDER_NONE
local RENDER_SIMPLE = layout.RENDER_SIMPLE
local PLACED_BY_CONTROL = layout.PLACED_BY_CONTROL
local IMAGE_INDEX_MASK = layout.IMAGE_INDEX_MASK
local MENU_X = layout.MENU_X
local MENU_Y = layout.MENU_Y
local MENU_SCROLL = layout.MENU_SCROLL
local ROCKS = layout.ROCKS
local IRON_COMMAND = layout.IRON_COMMAND
local K = layout.K
local C = layout.C
local IMAGE_SIZE = layout.IMAGE_SIZE
local PENCIL_TARGET = layout.PENCIL_TARGET
local BOX_BLEND = layout.BOX_BLEND
local TOOLTIP_FONT = layout.TOOLTIP_FONT
local TOOLTIP_COLOUR = layout.TOOLTIP_COLOUR
local TOOLTIP_LINE = layout.TOOLTIP_LINE
local TOOLTIP_PADDING = layout.TOOLTIP_PADDING
local ALIGN_LEFT = layout.ALIGN_LEFT
local MAP_LAYER = layout.MAP_LAYER
local TEXTURES_MODE = layout.TEXTURES_MODE
local memory = require("editor.memory")
local scan = memory.scan
local expectBytes = memory.expectBytes
local item = memory.item
local writeCString = memory.writeCString
local dwordList = memory.dwordList
local rd32 = memory.rd32
local rd16 = memory.rd16
local rd8 = memory.rd8
local wr32 = memory.wr32
local wr16 = memory.wr16
local drawTooltipOnTop = require("editor.ui").drawTooltipOnTop
local keyCode = require("editor.pipette_native").keyCode
local lane = require("editor.lane")
local actions = require("editor.actions")

---------------------------------------------------------------------------------------
-- The heights menu: max height, the height tools' options, lost rocks (features 28, 29)
---------------------------------------------------------------------------------------

-- The words the height tool patches read (shared with the panel), the strength of raise, lower
-- and equalize, and where the raise and lower amounts are written (once patched). The height
-- range, snap, invert and the ignore boxes go back to their defaults outside the map editor
-- (templates.frameHook).
function C.heightWords()
  if C.heightState == nil then
    local function word(value)
      local address = core.allocate(4, true)
      wr32(address, value or 0)
      return address
    end
    local H = {
      reset = word(), breakRocks = word(), mode = word(K.ROCK_WHOLE), divisor = word(), count = word(),
      records = core.allocate(K.ROCK_RECORDS * 8, true), strength = {}, open = false,
      rangeMin = word(K.HEIGHT_RANGE_DEFAULT[1]), rangeMax = word(K.HEIGHT_RANGE_DEFAULT[2]), snap = word(1),
      invert = word(), ignoreWater = word(), ignoreFarmland = word(), seed = word(0x2F6B1D),
    }
    for tool, value in pairs(K.STRENGTH_DEFAULTS) do H.strength[tool] = value end
    wr32(H.divisor, K.STRENGTH_SUM - H.strength[K.EQUALIZE_TOOL])
    C.heightState = H
  end
  return C.heightState
end

-- The chosen strength into the game: the raise and lower commands' amounts (code immediates)
-- and equalize's divisor.
function C.applyStrength(H)
  if H.raiseAmount ~= nil then core.writeCodeInteger(H.raiseAmount, H.strength[K.RAISE_TOOL]) end
  if H.lowerAmount ~= nil then core.writeCodeInteger(H.lowerAmount, -H.strength[K.LOWER_TOOL]) end
  wr32(H.divisor, K.STRENGTH_SUM - H.strength[K.EQUALIZE_TOOL])
end

-- The items the heights menu gets, in the order they are inserted at the end of its tab.
K.HEIGHT_PANEL_ITEMS = { "heightReset", "heightBreak", "heightWater", "heightFarmland", "heightSnap", "heightInvert",
  "heightRange", "heightStrength", "heightMode", "heightRangeReset" }
function C.heightItems(O)
  local list = {}
  if O.maxHeight then list[#list + 1] = "maxHeight" end
  if O.heightTools then
    for _, kind in ipairs(K.HEIGHT_PANEL_ITEMS) do list[#list + 1] = kind end
    for i = 1, #K.ROCK_MODES do list[#list + 1] = "heightOption" .. i end
    list[#list + 1] = "heightPanel"
  end
  return list
end

-- Where the mouse is on the screen, in x: the largest x the menu's mouse test does not put the
-- mouse left of (the game keeps the position in its own form).
function C.mouseX(G)
  C.isMouseInside = C.isMouseInside or core.exposeCode(G.isMouseInside, 5, 1)
  local low, high = -1, 8192
  while high - low > 1 do
    local middle = (low + high) // 2
    if C.isMouseInside(G.mouse, -100000, -100000, 100000 + middle, 200000) ~= 0 then high = middle else low = middle end
  end
  return low
end

-- Moves the rest of each rock a height tool touched in Whole rock (the tiles rockCheck
-- remembered): every tile of the rock by the average change of its touched tiles, then what the
-- height tools do afterwards (path links per tile, walk layer, minimap).
function C.rockSettler(G, R, H)
  local validTiles = C.resolveValidTiles()
  local T = R.tileMap
  local links = core.exposeCode(R.links, 3, 1)
  local walk = core.exposeCode(R.walk, 4, 1)
  local redraw = core.exposeCode(R.redraw, 2, 1)
  local function baseAt(tile) return rd8(T + R.defaultHeight + tile) & 0xFF end
  return function()
    local count = math.min(rd32(H.count), K.ROCK_RECORDS)
    wr32(H.count, 0)
    local rocks, order = {}, {}
    for i = 0, count - 1 do
      local at = H.records + i * 8
      local tile, id, old = rd32(at), rd16(at + 4) & 0xFFFF, rd8(at + 6) & 0xFF
      local rock = rocks[id]
      if rock == nil then
        rock = { old = {} }
        rocks[id] = rock
        order[#order + 1] = id
      end
      if rock.old[tile] == nil then rock.old[tile] = old end
    end
    local changed = false
    for _, id in ipairs(order) do
      local rock = rocks[id]
      local sum, n = 0, 0
      for tile, old in pairs(rock.old) do
        sum = sum + baseAt(tile) - old
        n = n + 1
      end
      local delta = sum >= 0 and math.floor(sum / n + 0.5) or -math.floor(-sum / n + 0.5)
      local slot = G.firstRock - K.ROCK_SLOT.inUse + (id - 1) * G.rockSize
      local rx, ry = rd16(slot + K.ROCK_POSITION.x) & 0xFFFF, rd16(slot + K.ROCK_POSITION.y) & 0xFFFF
      local number, moved = K.FIRST_ROCK_NUMBER + id, false
      for y = math.max(0, ry - K.ROCK_REACH), math.min(K.MAP_SIZE - 1, ry + K.ROCK_REACH) do
        local row = rd32(R.rows + y * 12)
        for x = math.max(0, rx - K.ROCK_REACH), math.min(K.MAP_SIZE - 1, rx + K.ROCK_REACH) do
          local tile = row + x
          if rd8(validTiles + y * K.MAP_SIZE + x) ~= 0 and tile >= 0 and tile < K.MAP_TILES
              and (rd16(T + R.organism + tile * 2) & 0xFFFF) == number then
            local height = math.max(0, math.min(0xFF, (rock.old[tile] or baseAt(tile)) + delta))
            if height ~= baseAt(tile) then
              core.writeByte(T + R.defaultHeight + tile, height)
              local live = height
              if rd32(T + R.logic + tile * 4) & K.RIVER_TERRAIN ~= 0 then live = math.max(0, height - K.RIVER_DEPTH) end
              core.writeByte(T + R.height + tile, live)
              links(R.pathFinding, y, tile)
              moved = true
            end
          end
        end
      end
      if moved then
        walk(R.pathFinding, K.WALK_RADIUS, rx, ry)
        changed = true
      end
    end
    if changed then
      wr32(T + R.logicFlag, 1)
      wr32(R.macroFlag, 1)
      redraw(R.minimap, 2)
    end
  end
end

-- Rock slots in use that no tile of the map names any more (all their tiles were taken over,
-- by shrubs placed on a rock the raise and lower tools broke): freed the way removeRock frees a
-- slot (zeroed), without touching any tile. Answers how many.
function C.removeLostRocks(G, R)
  local T = R.tileMap
  local named = {}
  for tile = 0, K.MAP_TILES - 1 do
    local number = rd16(T + R.organism + tile * 2) & 0xFFFF
    if number >= K.FIRST_ROCK_NUMBER then named[number - K.FIRST_ROCK_NUMBER] = true end
  end
  local zeros = {}
  for i = 1, G.rockSize do zeros[i] = 0 end
  local removed = 0
  for id = 1, G.rockSlots do
    local inUse = G.firstRock + (id - 1) * G.rockSize
    if rd16(inUse) ~= 0 and not named[id] then
      core.writeBytes(inUse - K.ROCK_SLOT.inUse, zeros)
      removed = removed + 1
    end
  end
  return removed
end

-- The heights panel, above the menu while a height tool is chosen, in rows from the bottom:
-- Reset ground textures, Break rock tiles, Ignore water, Ignore farmland; for raise, lower and
-- equalize Snap to range, Invert (equalize), the height range and the strength; on top the rock
-- height list (it opens upwards). The two sliders follow the mouse while its button is held.
function C.makeHeightPanel(G, data, H, items, leftHeld)
  local rect, listRect = C.takeRect(data), C.takeRect(data)
  local owner = nil
  local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
  local colourBox = core.exposeCode(G.colourBox, 6, 1)
  local textWidth = core.exposeCode(G.textWidth, 4, 1)
  local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
  local renderGM = core.exposeCode(G.renderGM, 5, 1)
  local buffer = core.allocate(128, true)
  local P = K.HEIGHT_PANEL
  local function width(text)
    writeCString(buffer, text)
    return textWidth(G.textManager, buffer, #text, TOOLTIP_FONT)
  end
  local function write(text, x, y)
    writeCString(buffer, text)
    shadowedText(G.textManager, buffer, x, y, ALIGN_LEFT, TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
  end
  local function place(address, x, y, w, h)
    wr32(address + ITEM_X, x)
    wr32(address + ITEM_Y, y)
    wr32(address + ITEM_WIDTH, w)
    wr32(address + ITEM_HEIGHT, h)
    wr16(address + ITEM_HIDDEN, 0)
  end
  local function modeName(mode)
    for _, entry in ipairs(K.ROCK_MODES) do
      if entry[1] == mode then return entry[2] end
    end
    return "?"
  end
  local box = K.CHECK_BOX_SIZE
  local checks = {
    { item = items.reset, word = H.reset, label = "Reset ground textures" },
    { item = items.breakRocks, word = H.breakRocks, label = "Break rock tiles" },
    { item = items.water, word = H.ignoreWater, label = "Ignore water" },
    { item = items.farmland, word = H.ignoreFarmland, label = "Ignore farmland" },
    { item = items.snap, word = H.snap, label = "Snap to range" },
    { item = items.invert, word = H.invert, label = "Invert" },
  }
  local byItem = {}
  for _, check in ipairs(checks) do byItem[check.item] = check end

  -- A slider's value under the mouse: lo .. hi over the item's width.
  local function valueAt(address, lo, hi)
    local left = rd32(G.menu + MENU_X) + rd32(address + ITEM_X)
    local w = math.max(1, rd32(address + ITEM_WIDTH))
    local value = lo + ((C.mouseX(G) - left) * (hi - lo) + w // 2) // w
    return math.max(lo, math.min(hi, value))
  end
  local function follow()
    if H.drag == nil then return end
    if not leftHeld() then
      H.drag = nil
      return
    end
    local tool = rd32(G.subtype)
    if H.drag == "strength" then
      if H.strength[tool] == nil then return end
      local value = valueAt(items.strength, 1, K.STRENGTH_MOST)
      if value ~= H.strength[tool] then
        H.strength[tool] = value
        C.applyStrength(H)
      end
    else
      local value = valueAt(items.range, 0, 0xFF)
      if H.drag == "min" then
        wr32(H.rangeMin, math.min(value, rd32(H.rangeMax)))
      else
        wr32(H.rangeMax, math.max(value, rd32(H.rangeMin)))
      end
    end
  end
  C.heightPanelValueAt = valueAt

  return function()
    for _, address in ipairs(items.all) do wr16(address + ITEM_HIDDEN, 1) end
    follow()
    local tool = rd32(G.subtype)
    local strength = H.strength[tool]
    local ranged = strength ~= nil
    -- The rows: { kind, item } entries with their widths.
    local rows = { { checks[1], checks[2], checks[3], checks[4] } }
    if ranged then
      local row = { checks[5] }
      if tool == K.EQUALIZE_TOOL then row[#row + 1] = checks[6] end
      row[#row + 1] = { item = items.strength, slider = "strength" }
      rows[#rows + 1] = row
      -- the range slider (a pixel per height) and its Reset button on a row of their own
      rows[#rows + 1] = { { item = items.range, slider = "range" },
        { item = items.rangeReset, button = true, label = "Reset" } }
    end
    rows[#rows + 1] = { { item = items.mode, list = true } }
    local modeWidth = 0
    for _, entry in ipairs(K.ROCK_MODES) do modeWidth = math.max(modeWidth, width(entry[2])) end
    local listLabel = "Rock height changes:"
    local rangeLabel = string.format("Height range %d - %d", rd32(H.rangeMin), rd32(H.rangeMax))
    local panelWidth = 0
    for _, row in ipairs(rows) do
      row.width = 0
      for _, element in ipairs(row) do
        if element.list then
          element.width = width(listLabel) + TOOLTIP_PADDING + modeWidth + 3 * TOOLTIP_PADDING + width("v")
        elseif element.slider == "range" then
          element.label, element.track = rangeLabel, P.rangeSlider
          element.width = width("Height range 255 - 255") + TOOLTIP_PADDING + P.rangeSlider
        elseif element.button then
          element.width = width(element.label) + 2 * TOOLTIP_PADDING
        elseif element.slider == "strength" then
          element.label, element.track = string.format("Strength %d", strength), P.slider
          element.width = width("Strength 16") + TOOLTIP_PADDING + P.slider
        else
          element.width = box + TOOLTIP_PADDING + width(element.label)
        end
        row.width = row.width + element.width
      end
      row.width = row.width + P.gap * (#row - 1)
      panelWidth = math.max(panelWidth, row.width)
    end
    local total = panelWidth + 2 * TOOLTIP_PADDING
    local height = #rows * box + (#rows - 1) * P.rowGap + 2 * TOOLTIP_PADDING
    local menuX = rd32(G.menu + MENU_X)
    owner = owner or { items = items.all }      -- what editor/lane.lua places
    local left, top = lane.spot(G, data, owner, total, height)
    local bottom = top + height
    C.markRect(rect, left, top, total, height)
    for r, row in ipairs(rows) do
      row.y = bottom - TOOLTIP_PADDING - r * box - (r - 1) * P.rowGap
      local x = left + TOOLTIP_PADDING + (panelWidth - row.width) // 2
      for _, element in ipairs(row) do
        element.x = x
        if element.track ~= nil then
          place(element.item, x + element.width - element.track, row.y, element.track, box)
        else
          place(element.item, x, row.y, element.width, box)
        end
        x = x + element.width + P.gap
      end
    end
    local list = rows[#rows][1]
    local options = #K.ROCK_MODES
    local listTop = top - P.dropdown - options * P.optionHeight
    if H.open then
      for i = 1, options do
        place(items.options[i], list.x, listTop + (i - 1) * P.optionHeight, list.width, P.optionHeight)
      end
      C.markRect(listRect, list.x, listTop, list.width, options * P.optionHeight)
    else
      C.markRect(listRect, 0, 0, 0, 0)
    end

    local offsetX = menuX - rd32(G.menu + MENU_SCROLL) + rd32(G.cameraX)
    local offsetY = rd32(G.menu + MENU_Y) + rd32(G.cameraY)
    local white = rd32(G.pixelFormat) == 0x565 and 0xFFFF or 0x7FFF
    local function frame(l, t, r, b)
      colourBox(G.pencil, l, t, r, t + 1, white)
      colourBox(G.pencil, l, b - 1, r, b, white)
      colourBox(G.pencil, l, t, l + 1, b, white)
      colourBox(G.pencil, r - 1, t, r, b, white)
    end
    local target = rd32(G.pencil + PENCIL_TARGET)
    wr32(G.pencil + PENCIL_TARGET, MAP_LAYER)
    roundedBox(G.pencil, offsetX + left, offsetY + top, offsetX + left + total, offsetY + bottom, BOX_BLEND)
    for _, row in ipairs(rows) do
      for _, element in ipairs(row) do
        local address = element.item
        if element.track == nil and rd16(address + ITEM_HOVERED) ~= 0 then
          local l, t = offsetX + rd32(address + ITEM_X), offsetY + rd32(address + ITEM_Y)
          roundedBox(G.pencil, l, t, l + rd32(address + ITEM_WIDTH), t + rd32(address + ITEM_HEIGHT), BOX_BLEND)
        end
        if element.list then
          local headX = offsetX + element.x + width(listLabel) + TOOLTIP_PADDING
          element.headX = headX
          frame(headX, offsetY + row.y + 3, offsetX + element.x + element.width, offsetY + row.y + box - 3)
        elseif element.button then
          frame(offsetX + element.x, offsetY + row.y + 3, offsetX + element.x + element.width, offsetY + row.y + box - 3)
        elseif element.track ~= nil then
          local l = offsetX + rd32(address + ITEM_X)
          local middle = offsetY + row.y + box // 2
          local t, b = middle - P.sliderHeight // 2, middle + P.sliderHeight // 2
          roundedBox(G.pencil, l, t, l + element.track, b, BOX_BLEND)
          if element.slider == "strength" then
            local filled = l + (element.track * strength) // K.STRENGTH_MOST
            colourBox(G.pencil, l, middle - 1, filled, middle + 1, white)
            colourBox(G.pencil, filled - 2, t - 3, filled + 2, b + 3, white)
          else
            local low = l + (element.track * rd32(H.rangeMin)) // 0xFF
            local high = l + (element.track * rd32(H.rangeMax)) // 0xFF
            colourBox(G.pencil, low, middle - 2, math.max(low + 1, high), middle + 2, white)
            colourBox(G.pencil, low - 2, t - 3, low + 2, b + 3, white)
            colourBox(G.pencil, high - 2, t - 3, high + 2, b + 3, white)
          end
          frame(l, t, l + element.track, b)
        end
      end
    end
    if H.open then
      local l = offsetX + list.x
      roundedBox(G.pencil, l, offsetY + listTop, l + list.width, offsetY + top - P.dropdown, BOX_BLEND)
      for i = 1, options do
        local address = items.options[i]
        local ot = offsetY + rd32(address + ITEM_Y)
        if rd16(address + ITEM_HOVERED) ~= 0 then roundedBox(G.pencil, l, ot, l + list.width, ot + P.optionHeight, BOX_BLEND) end
        if K.ROCK_MODES[i][1] == rd32(H.mode) then frame(l, ot, l + list.width, ot + P.optionHeight) end
      end
    end
    wr32(G.pencil + PENCIL_TARGET, target)

    local mode = rd32(G.textures + TEXTURES_MODE)
    wr32(G.textures + TEXTURES_MODE, MAP_LAYER)
    for _, row in ipairs(rows) do
      for _, element in ipairs(row) do
        local check = byItem[element.item]
        if check ~= nil then
          local image = G.buttonImages + (rd32(check.word) ~= 0 and K.CHECKED_IMAGE or K.UNCHECKED_IMAGE) * IMAGE_SIZE
          local picture = rd32(image + 4)
          if rd16(element.item + ITEM_HOVERED) ~= 0 then picture = picture + 1 end
          renderGM(G.textures, rd32(image), picture, offsetX + element.x, offsetY + row.y)
        end
      end
    end
    wr32(G.textures + TEXTURES_MODE, mode)

    local layer = rd32(G.textLayer)
    wr32(G.textLayer, MAP_LAYER)
    for _, row in ipairs(rows) do
      local textY = offsetY + row.y + (box - TOOLTIP_LINE) // 2 + 2
      for _, element in ipairs(row) do
        if byItem[element.item] ~= nil then
          write(element.label, offsetX + element.x + box + TOOLTIP_PADDING, textY)
        elseif element.list then
          write(listLabel, offsetX + element.x, textY)
          write(modeName(rd32(H.mode)), element.headX + TOOLTIP_PADDING, textY)
          write("v", offsetX + element.x + element.width - TOOLTIP_PADDING - width("v"), textY)
        elseif element.button then
          write(element.label, offsetX + element.x + TOOLTIP_PADDING, textY)
        else
          write(element.label, offsetX + element.x, textY)
        end
      end
    end
    if H.open then
      for i = 1, options do
        local ot = offsetY + rd32(items.options[i] + ITEM_Y)
        write(K.ROCK_MODES[i][2], offsetX + list.x + TOOLTIP_PADDING, ot + (P.optionHeight - TOOLTIP_LINE) // 2 + 2)
      end
    end
    wr32(G.textLayer, layer)
    drawTooltipOnTop(data)
  end
end

-- The heights menu's new items and the lost rocks button (called while the landscape menu's
-- new table is built; M holds what buildTable has at hand).
function C.heightsMenu(M)
  local G, O, data, added = M.G, M.O, M.data, M.added
  -- Max height: a copy of the min height button with command 22, the next picture and the user
  -- control the iron button took (the iron goes, or, kept, moves to the end of the row).
  if O.maxHeight then
    local into = added.maxHeight
    M.copyOf(K.MIN_HEIGHT_TOOL, into)
    local image = rd32(into + ITEM_IMAGE)
    wr32(into + ITEM_IMAGE, (image & ~IMAGE_INDEX_MASK & 0xFFFFFFFF) | ((image & IMAGE_INDEX_MASK) + 1))
    wr32(into + ITEM_PARAM, K.MAX_HEIGHT_TOOL)
    wr32(into + ITEM_Y, K.MAX_HEIGHT_CONTROL)
    wr32(into + ITEM_TEXT, 0)
    M.tooltips[#M.tooltips + 1] = { item = into, name = K.MAX_HEIGHT_NAME }
    if not (O.noHeightsIron and O.textures) and G.buttons[IRON_COMMAND] ~= nil then
      local row = {}
      for _, param in ipairs(K.HEIGHTS_TOP_ROW) do row[#row + 1] = M.button(param) end
      row[#row + 1] = into
      row[#row + 1] = M.button(IRON_COMMAND)
      M.rows[#M.rows + 1] = row
      M.newButtons[into] = true
    end
  end

  if O.heightTools then
    local H = C.heightWords()
    local items = {
      reset = added.heightReset, breakRocks = added.heightBreak, mode = added.heightMode,
      strength = added.heightStrength, water = added.heightWater, farmland = added.heightFarmland,
      rangeReset = added.heightRangeReset,
      snap = added.heightSnap, invert = added.heightInvert, range = added.heightRange, options = {},
    }
    for i = 1, #K.ROCK_MODES do items.options[i] = added["heightOption" .. i] end
    items.all = {}
    for _, kind in ipairs(K.HEIGHT_PANEL_ITEMS) do items.all[#items.all + 1] = added[kind] end
    for _, address in ipairs(items.options) do items.all[#items.all + 1] = address end
    local function button(address, fn, what)
      wr32(address + ITEM_TYPE, TYPE_CLICKABLE)
      wr32(address + ITEM_ACTION, C.luaPad(fn, what))
      wr32(address + ITEM_RENDER_TYPE, RENDER_NONE)
      wr32(address + ITEM_TEXT, 0)
      wr16(address + ITEM_CONTROL, -1)
      wr16(address + ITEM_HIDDEN, 1)
      M.guarded[#M.guarded + 1] = address
      M.guarded[#M.guarded + 1] = K.HEIGHTS_TAB
    end
    local function flip(word) wr32(word, rd32(word) ~= 0 and 0 or 1) end
    button(items.reset, function() flip(H.reset) end, "the Reset ground textures box")
    button(items.breakRocks, function() flip(H.breakRocks) end, "the Break rock tiles box")
    button(items.water, function() flip(H.ignoreWater) end, "the Ignore water box")
    button(items.farmland, function() flip(H.ignoreFarmland) end, "the Ignore farmland box")
    button(items.snap, function() flip(H.snap) end, "the Snap to range box")
    button(items.invert, function()
      flip(H.invert)
      H.keyInvert = false
    end, "the Invert box")
    button(items.mode, function() H.open = not H.open end, "the rock mode list")
    for i, entry in ipairs(K.ROCK_MODES) do
      button(items.options[i], function()
        wr32(H.mode, entry[1])
        H.open = false
      end, "the rock mode list")
    end
    -- The sliders: a click sets the value under the mouse and starts following the mouse; the
    -- height range moves the nearer handle (a click outside the range: the one on that side).
    button(items.strength, function()
      local tool = rd32(G.subtype)
      if H.strength[tool] == nil then return end
      H.strength[tool] = C.heightPanelValueAt(items.strength, 1, K.STRENGTH_MOST)
      C.applyStrength(H)
      H.drag = "strength"
    end, "the strength slider")
    button(items.rangeReset, function()
      wr32(H.rangeMin, K.HEIGHT_RANGE_DEFAULT[1])
      wr32(H.rangeMax, K.HEIGHT_RANGE_DEFAULT[2])
    end, "the height range Reset button")
    button(items.range, function()
      local value = C.heightPanelValueAt(items.range, 0, 0xFF)
      local low, high = rd32(H.rangeMin), rd32(H.rangeMax)
      if value < low or (value <= high and value - low <= high - value) then
        H.drag = "min"
        wr32(H.rangeMin, math.min(value, high))
      else
        H.drag = "max"
        wr32(H.rangeMax, math.max(value, low))
      end
    end, "the height range slider")
    local R = C.resolvePipette(G)
    local asyncKey = core.exposeCode(core.allocateAssembly(templates.undoKeyState, { IMPORT = R.keyState }), 1, 0)
    local function down(key) return key ~= nil and (asyncKey(key) % 0x10000) >= 0x8000 end
    local function leftHeld() return down(K.LEFT_BUTTON) end
    local panel = added.heightPanel
    local commands = {}
    for _, tool in ipairs(K.HEIGHT_TOOLS) do commands[#commands + 1] = tool end
    commands[#commands + 1] = -1
    wr32(panel + ITEM_TYPE, TYPE_CLICKABLE)    -- no size, so never under the mouse
    wr32(panel + ITEM_RENDER_TYPE, RENDER_SIMPLE)
    wr32(panel + ITEM_RENDER, core.allocateAssembly(templates.toolPanel, {
      SUBTYPE = G.subtype, COMMANDS = dwordList(commands), PANEL_ITEMS = dwordList(items.all),
      ITEM_HIDDEN = ITEM_HIDDEN,
      PAD = C.luaPad(C.makeHeightPanel(G, data, H, items, leftHeld), "the heights panel"),
    }))
    -- Every frame something was remembered: the rest of a rock moved in Whole rock; while the
    -- equalize tool is chosen: its invert key (inverts while held, unless Invert is ticked).
    local settle = C.rockSettler(G, R, H)
    local key = O.invertKey ~= nil and keyCode(O.invertKey) or nil
    local invertHeld = actions.hold("equalize-invert")
    local tick = added.heightTick
    wr32(tick + ITEM_TYPE, TYPE_EVERY_FRAME)
    wr32(tick + ITEM_ACTION, C.assemble("heightTick", {
      COUNT = H.count, SUBTYPE = G.subtype, EQUALIZE_TOOL = K.EQUALIZE_TOOL,
      PAD = C.luaPad(function()
        if rd32(H.count) ~= 0 then settle() end
        local held = rd32(G.subtype) == K.EQUALIZE_TOOL and rd32(R.menuGuard) == -1
          and (invertHeld() or (key ~= nil and down(key)))
        if held and not H.keyInvert and rd32(H.invert) == 0 then
          wr32(H.invert, 1)
          H.keyInvert = true
        elseif not held and H.keyInvert then
          wr32(H.invert, 0)
          H.keyInvert = false
        end
      end, "the heights tick"),
    }))
    data.heights = H
  end


  -- The lost rocks button, bottom right of the Rocks menu (both Rocks tabs).
  if O.lostRocks then
    local R = C.resolvePipette(G)
    local roundedBox = core.exposeCode(G.roundedBox, 6, 1)
    local textWidth = core.exposeCode(G.textWidth, 4, 1)
    local shadowedText = core.exposeCode(G.shadowedText, 10, 1)
    local buffer = core.allocate(64, true)
    local B = K.LOST_ROCKS_BUTTON
    local report = "Takes rocks off the map's list that no tile has any more"
    for _, tab in ipairs({ ROCKS, K.ROCKS_SKIRMISH }) do
      local into = added["lostRocks" .. tab]
      if into ~= nil then
        wr32(into + ITEM_TYPE, TYPE_CLICKABLE)
        wr32(into + ITEM_ACTION, C.luaPad(function()
          if O.undo ~= nil then O.undo.beginEdit() end
          local removed = C.removeLostRocks(G, R)
          report = removed == 0 and "No lost rocks on this map"
            or string.format("Removed %d lost rock%s", removed, removed == 1 and "" or "s")
          log(INFO, MODULE_NAME .. ": " .. report)
        end, "the lost rocks button"))
        wr32(into + ITEM_TEXT, 0)
        wr16(into + ITEM_CONTROL, -1)
        wr16(into + ITEM_HIDDEN, 1)
        local buttons = {}
        for _, rock in ipairs(G.rockButtons) do
          if rock.block == tab then buttons[#buttons + 1] = item(M.newTable, M.moved(rock.index)) end
        end
        local box = added["invisible" .. tab]
        M.places[#M.places + 1] = function(measure)
          local right, bottom = nil, nil
          for _, address in ipairs(buttons) do
            local x = rd32(address + ITEM_X)
            if (x & 0xFFFFFFFF) == PLACED_BY_CONTROL then return false end
            local w, h = measure(address)
            if w == nil then return false end
            right = math.max(right or 0, x + w)
            bottom = math.max(bottom or 0, rd32(address + ITEM_Y) + h)
          end
          if right == nil then return true end
          writeCString(buffer, K.LOST_ROCKS_LABEL)
          local w = textWidth(G.textManager, buffer, #K.LOST_ROCKS_LABEL, TOOLTIP_FONT) + 2 * B.padding
          local y = bottom - B.height
          if box ~= nil and rd16(box + ITEM_HIDDEN) == 0 then
            y = math.max(y, rd32(box + ITEM_Y) + K.CHECK_BOX_SIZE + B.below)
          end
          wr32(into + ITEM_X, right + K.CHECK_BOX_GAP)
          wr32(into + ITEM_Y, y)
          wr32(into + ITEM_WIDTH, w)
          wr32(into + ITEM_HEIGHT, B.height)
          wr16(into + ITEM_HIDDEN, 0)
          return true
        end
        -- Drawn in the menu, like the tab numbers.
        wr32(into + ITEM_RENDER_TYPE, RENDER_SIMPLE)
        wr32(into + ITEM_RENDER, C.luaPad(function()
          if rd16(into + ITEM_HIDDEN) ~= 0 then return end
          local l = rd32(G.menu + MENU_X) - rd32(G.menu + MENU_SCROLL) + rd32(into + ITEM_X)
          local t = rd32(G.menu + MENU_Y) + rd32(into + ITEM_Y)
          local w = rd32(into + ITEM_WIDTH)
          roundedBox(G.pencil, l, t, l + w, t + B.height, BOX_BLEND)
          if rd16(into + ITEM_HOVERED) ~= 0 then roundedBox(G.pencil, l, t, l + w, t + B.height, BOX_BLEND) end
          writeCString(buffer, K.LOST_ROCKS_LABEL)
          shadowedText(G.textManager, buffer, l + B.padding, t + (B.height - TOOLTIP_LINE) // 2 + 2, ALIGN_LEFT,
            TOOLTIP_COLOUR, 0, TOOLTIP_FONT, 0, 0)
        end, "the lost rocks button"))
        M.tooltips[#M.tooltips + 1] = { item = into, lines = function() return { report } end,
          raise = K.CHECK_BOX_TOOLTIP_RAISE }
      end
    end
  end
end

-- The height tools' patches (with the options on): rocks kept whole or erased, the ground's look
-- only reset when asked, raise and lower without wrapping, the strength.
-- allocateAssembly with every value as an unsigned 32-bit number (core.assemble writes them with
-- %X, so a negative one would not assemble); a failure names the template and its values.
function C.assemble(name, values)
  local clean, listed = {}, {}
  for key, value in pairs(values) do
    clean[key] = value & 0xFFFFFFFF
    listed[#listed + 1] = string.format("%s=0x%X", key, clean[key])
  end
  local ok, result = pcall(core.allocateAssembly, templates[name], clean)
  if not ok then
    table.sort(listed)
    error(string.format("%s: %s (%s)", name, tostring(result), table.concat(listed, " ")))
  end
  return result
end

function C.patchHeightTools(self, G, data)
  local H = data.heights
  local R = C.resolvePipette(G)
  local T = R.tileMap
  local check = C.assemble("rockCheck", {
    ORGANISM = T + R.organism, FIRST_ROCK_NUMBER = K.FIRST_ROCK_NUMBER, ROCK_MODE = H.mode,
    MODE_ERASE = K.ROCK_ERASE, MODE_WHOLE = K.ROCK_WHOLE, RECORD_COUNT = H.count, RECORD_MOST = K.ROCK_RECORDS,
    RECORDS = H.records, BASE_HEIGHT = T + R.defaultHeight, BREAK_ROCKS = H.breakRocks,
    LANDSCAPE = R.landscape, REMOVE_ROCK = R.removeRock,
  })
  local raiseAnd = scan(K.AOB_RAISE_AND, "raiseLand's rock flag")
  local raiseAdd = scan(K.AOB_RAISE_ADD, "raiseLand's amount")
  local levelAnd = scan(K.AOB_LEVEL_AND, "the equalize tool's rock flag")
  local levelRise = scan(K.AOB_LEVEL_RISE, "the equalize tool's step up")
  local levelFall = scan(K.AOB_LEVEL_FALL, "the equalize tool's step down")
  local levelGround = scan(K.AOB_LEVEL_DECORATION, "the equalize tool's ground")
  local plateauAnd = scan(K.AOB_PLATEAU_AND, "the plateau tools' rock flag")
  local plateauGround = scan(K.AOB_PLATEAU_DECORATION, "the plateau tools' ground")
  local minGround = scan(K.AOB_MIN_DECORATION, "the min height tool's ground")
  local minRock = minGround + K.MIN_DECORATION.size
  expectBytes(minRock, { 0xF6, 0x84, 0xAF }, "the min and max height tools' rock")
  local raiseAmount = scan(K.AOB_RAISE_AMOUNT, "the raise land command") + K.AMOUNT_VALUE
  local lowerAmount = scan(K.AOB_LOWER_AMOUNT, "the lower land command") + K.AMOUNT_VALUE
  local raiseRange = scan(K.AOB_RAISE_RANGE, "raiseLand's limits") + K.RAISE_RANGE.site
  local levelRange = scan(K.AOB_LEVEL_RANGE, "the equalize tool's limits") + K.LEVEL_RANGE.site
  local levelAverage = scan(K.AOB_LEVEL_AVERAGE, "the equalize tool's middle height") + K.LEVEL_AVERAGE.site
  local levelEqual = scan(K.AOB_LEVEL_EQUAL, "the equalize tool's step")
  local filter = C.heightFilter(G, data)

  -- Every stub first, so that a failure leaves the game's code as it is.
  local stubs = {}
  stubs[#stubs + 1] = { raiseAnd, K.RAISE_AND.size, C.assemble("raiseRock", {
    ROCK_CHECK = check, LOGIC = rd32(raiseAnd + K.RAISE_AND.logic), BACK = raiseAnd + K.RAISE_AND.size,
  }) }
  stubs[#stubs + 1] = { raiseAdd, K.RAISE_ADD.size, C.assemble("raiseAmount", {
    HEIGHT = rd32(raiseAdd + K.RAISE_ADD.height), DECORATION = rd32(raiseAdd + K.RAISE_ADD.decoration),
    RESET = H.reset, BACK = raiseAdd + K.RAISE_ADD.size,
  }) }
  stubs[#stubs + 1] = { levelAnd, K.LEVEL_AND.size, C.assemble("brushRock", {
    ROCK_CHECK = check, MAY_BREAK = 1, LOGIC = rd32(levelAnd + K.LEVEL_AND.logic), BACK = levelAnd + K.LEVEL_AND.size,
  }) }
  stubs[#stubs + 1] = { levelRise, K.LEVEL_RISE.size, C.assemble("levelRise", {
    DIVISOR = H.divisor, INVERT = H.invert, HEIGHT_STORE = levelRise + K.LEVEL_RISE.store,
  }) }
  stubs[#stubs + 1] = { levelFall, K.LEVEL_FALL.size, C.assemble("levelFall", {
    DIVISOR = H.divisor, INVERT = H.invert, HEIGHT_STORE = levelFall + K.LEVEL_FALL.size,
  }) }
  local RR = K.RAISE_RANGE
  stubs[#stubs + 1] = { raiseRange, RR.size, C.assemble("raiseRange", {
    GAME_LOWEST = rd32(raiseRange + RR.lowest), GAME_HIGHEST = rd32(raiseRange + RR.lowest) + (rd8(raiseRange + RR.highestAdd) & 0xFF),
    SUBTYPE = G.subtype, RAISE_TOOL = K.RAISE_TOOL, LOWER_TOOL = K.LOWER_TOOL, RANGE_MIN = H.rangeMin,
    RANGE_MAX = H.rangeMax, BACK = raiseRange + RR.size,
  }) }
  stubs[#stubs + 1] = { levelRange, K.LEVEL_RANGE.size, C.assemble("levelRange", {
    HEIGHT = rd32(levelRange + K.LEVEL_RANGE.height), RANGE_MIN = H.rangeMin, RANGE_MAX = H.rangeMax,
    BACK = levelRange + K.LEVEL_RANGE.size,
  }) }
  local LA = K.LEVEL_AVERAGE
  stubs[#stubs + 1] = { levelAverage, LA.size, C.assemble("levelAverage", {
    HEIGHT_FILTER = filter, AVERAGE_NEXT = levelAverage - LA.site + LA.next,
    HEIGHT = rd32(levelAverage - LA.site + LA.height), BACK = levelAverage + LA.size,
  }) }
  local LE = K.LEVEL_EQUAL
  stubs[#stubs + 1] = { levelEqual, LE.size, C.assemble("levelEqual", {
    HEIGHT = rd32(levelEqual + LE.height), FALL = levelEqual + LE.size, INVERT = H.invert, NO_STEP = levelEqual + LE.noStep,
    SEED = H.seed, RANDOM_MULTIPLIER = K.RANDOM_MULTIPLIER, RANDOM_INCREMENT = K.RANDOM_INCREMENT,
    STRENGTH_SUM = K.STRENGTH_SUM, DIVISOR = H.divisor, HEIGHT_STORE = levelRise + K.LEVEL_RISE.store,
  }) }
  stubs[#stubs + 1] = { levelGround, K.LEVEL_DECORATION.size, C.assemble("levelGround", {
    RESET = H.reset, DECORATION = rd32(levelGround + K.LEVEL_DECORATION.decoration),
    BACK = levelGround + K.LEVEL_DECORATION.size,
  }) }
  stubs[#stubs + 1] = { plateauAnd, K.PLATEAU_AND.size, C.assemble("brushRock", {
    ROCK_CHECK = check, MAY_BREAK = 0, LOGIC = rd32(plateauAnd + K.PLATEAU_AND.logic),
    BACK = plateauAnd + K.PLATEAU_AND.size,
  }) }
  stubs[#stubs + 1] = { plateauGround, K.PLATEAU_DECORATION.size, C.assemble("plateauGround", {
    RESET = H.reset, DECORATION = rd32(plateauGround + K.PLATEAU_DECORATION.decoration),
    BACK = plateauGround + K.PLATEAU_DECORATION.size,
  }) }
  local minStub = C.assemble("minMaxRock", {
    RESET = H.reset, DECORATION = rd32(minGround + K.MIN_DECORATION.decoration), ROCK_CHECK = check,
    AFTER_AND = minRock + K.MIN_ROCK.afterAnd, AND_SITE = minRock + K.MIN_ROCK.andSite,
  })
  for _, stub in ipairs(stubs) do C.patchJump(self, stub[1], stub[2], stub[3]) end
  -- Min height's `and byte [DECORATION],0xF3` goes: the rock patch resets the look when asked.
  self.saved = self.saved or {}
  table.insert(self.saved, { address = minGround, bytes = core.readBytes(minGround, K.MIN_DECORATION.size) })
  local nops = {}
  for i = 1, K.MIN_DECORATION.size do nops[i] = 0x90 end
  core.writeCode(minGround, nops)
  C.patchJump(self, minRock, K.MIN_ROCK.size, minStub)
  for _, at in ipairs({ raiseAmount, lowerAmount }) do
    table.insert(self.saved, { address = at, bytes = core.readBytes(at, 4) })
  end
  H.raiseAmount, H.lowerAmount = raiseAmount, lowerAmount
  C.applyStrength(H)
end

return true
